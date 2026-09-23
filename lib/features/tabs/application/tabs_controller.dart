/// Owns every open tab and its lifecycle.
///
/// Two rules shape this class:
///
/// * **One editor controller per open tab**, held by [TabEditorControllers]
///   rather than in a widget, so switching tabs keeps each file's undo history,
///   cursor and scroll intact and switching back is instant.
/// * **Dirtiness is derived**, by comparing the buffer against the last saved
///   text, not tracked as a flag. Typing a character and undoing it leaves the
///   tab genuinely clean, which a flag would get wrong.
///
/// Three concerns live in their own files because they are self-contained and
/// this class was outgrowing the size convention: the editor controllers
/// (`tab_editor_controllers.dart`), saving (`tab_saver.dart`) and closing
/// (`tab_closer.dart`).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/core/utils/relative_path.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/features/history/application/history_controller.dart';
import 'package:pocket_code/features/tabs/application/document_loader.dart';
import 'package:pocket_code/features/tabs/application/tab_closer.dart';
import 'package:pocket_code/features/tabs/application/tab_editor_controllers.dart';
import 'package:pocket_code/features/tabs/application/tab_saver.dart';
import 'package:pocket_code/features/tabs/application/tabs_state.dart';
import 'package:pocket_code/features/workspace/application/recents_controller.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';
import 'package:re_editor/re_editor.dart';

class TabsController extends Notifier<TabsState>
    with TabEditorControllers, TabSaver, TabCloser {
  static const DocumentLoader _loader = DocumentLoader();

  @override
  TabsState build() {
    ref.listen<OpenWorkspace?>(workspaceProvider,
        (OpenWorkspace? previous, OpenWorkspace? next) {
      if (previous != next) {
        _disposeAll();
        state = const TabsState();
      }
    });
    ref.onDispose(() {
      cancelAutoSave();
      _disposeAll();
    });
    return const TabsState();
  }

  // --- Editing --------------------------------------------------------------

  @override
  void onBufferChanged(String key) {
    final int index = state.indexOfKey(key);
    if (index < 0) {
      return;
    }
    final CodeLineEditingController? controller = controllerForKey(key);
    if (controller == null) {
      return;
    }
    final OpenTab tab = state.tabs[index];
    final String text = controller.text;
    final EditorState editorState = editorStateOf(controller);

    if (tab.text == text &&
        tab.editorState.extentLine == editorState.extentLine &&
        tab.editorState.extentOffset == editorState.extentOffset) {
      return;
    }

    // Editing a preview tab pins it, exactly like VS Code: the user has
    // invested in this file, so the next opened file must not replace it.
    final bool pin = tab.isPreview && tab.text != text;

    replaceTab(
      index,
      tab.copyWith(
        text: text,
        editorState: editorState,
        isPreview: pin ? false : null,
      ),
    );
    scheduleAutoSave();
  }

  // --- Opening --------------------------------------------------------------

  /// Opens [node], or focuses it if already open.
  ///
  /// [preview] mirrors VS Code's single-click behaviour: the tab is temporary
  /// and the next previewed file replaces it, until it is edited or pinned.
  @override
  Future<void> open(
    FileNode node,
    int rootIndex, {
    bool preview = true,
  }) async {
    final String key = '$rootIndex:${node.id}';
    final int existing = state.indexOfKey(key);
    if (existing >= 0) {
      // Reopening a previewed file by double tap pins it.
      if (!preview && state.tabs[existing].isPreview) {
        replaceTab(existing, state.tabs[existing].copyWith(isPreview: false));
      }
      setActive(existing);
      return;
    }

    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(rootIndex);
    if (root == null) {
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final OpenTab tab = await _loader.load(
        node: node,
        rootIndex: rootIndex,
        provider: root.provider,
        settings: ref.read(settingsProvider),
        preview: preview,
      );

      // A preview tab is replaced rather than added, so single-clicking through
      // a folder does not leave a trail of tabs behind.
      final int previewIndex =
          state.tabs.indexWhere((OpenTab t) => t.isPreview && !t.isDirty);
      final List<OpenTab> tabs = List<OpenTab>.of(state.tabs);
      int index;
      if (preview && previewIndex >= 0) {
        disposeControllerFor(tabs[previewIndex].key);
        tabs[previewIndex] = tab;
        index = previewIndex;
      } else {
        tabs.add(tab);
        index = tabs.length - 1;
      }

      state = state.copyWith(
        tabs: tabs,
        activeIndex: index,
        isLoading: false,
        clearError: true,
      );
      // Prime the controller so the editor has content on its first frame.
      controllerFor(tab);
      setTextSilently(tab.key, tab.text);
      // Bookkeeping, unawaited: opening a file must not wait on it.
      unawaited(ref.read(recentsProvider.notifier).recordFile(
            providerScheme: root.provider.schemeId,
            fileId: node.id,
            name: node.name,
            displayPath: node.displayPath,
          ));
    } on AppFailure catch (failure) {
      state = state.copyWith(isLoading: false, error: failure);
    }
  }

  void setActive(int index) {
    if (index < 0 || index >= state.tabs.length || index == state.activeIndex) {
      return;
    }
    state = state.copyWith(activeIndex: index);
  }

  /// Moves a tab, for drag-to-reorder.
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.tabs.length) {
      return;
    }
    final List<OpenTab> tabs = List<OpenTab>.of(state.tabs);
    final OpenTab moved = tabs.removeAt(oldIndex);
    final int target = newIndex.clamp(0, tabs.length);
    tabs.insert(target, moved);

    // Keep the same tab active across the move, wherever it landed.
    final OpenTab? active = state.active;
    final int activeIndex = active == null
        ? -1
        : tabs.indexWhere((OpenTab t) => t.key == active.key);
    state = state.copyWith(tabs: tabs, activeIndex: activeIndex);
  }

  /// Puts a recovered hot-exit buffer back into a tab.
  ///
  /// The tab keeps the text that was on disk as its `savedText`, so it comes
  /// back correctly marked dirty and the user can still see what changed by
  /// saving or reloading.
  void restoreUnsavedBuffer(int rootIndex, String fileId, String text) {
    final int index = state.indexOfKey('$rootIndex:$fileId');
    if (index < 0) {
      return;
    }
    final OpenTab tab = state.tabs[index];
    replaceTab(index, tab.copyWith(text: text));
    setTextSilently(tab.key, text);
  }

  /// Puts the cursor and selection back, for reopen and session restore.
  @override
  void restoreEditorState(EditorState editorState) {
    final OpenTab? tab = state.active;
    if (tab == null) {
      return;
    }
    final CodeLineEditingController? controller = controllerForKey(tab.key);
    if (controller == null) {
      return;
    }
    final int lineCount = controller.lineCount;
    // Clamp: the file may have been edited elsewhere and be shorter now.
    final int line = editorState.extentLine.clamp(0, lineCount - 1);
    controller.selection = CodeLineSelection.collapsed(
      index: line,
      offset: editorState.extentOffset
          .clamp(0, controller.codeLines[line].text.length),
    );
    controller.makeCursorCenterIfInvisible();
  }

  // --- External changes -----------------------------------------------------

  /// Marks a tab as changed on disk, or silently reloads it if it is clean.
  ///
  /// A clean buffer has nothing to lose, so reloading is strictly better than
  /// nagging. A dirty one must never be overwritten without asking.
  Future<void> onExternalChange(String fileId) async {
    final int index = state.tabs.indexWhere((OpenTab t) => t.node.id == fileId);
    if (index < 0) {
      return;
    }
    final OpenTab tab = state.tabs[index];
    if (tab.isDirty) {
      replaceTab(index, tab.copyWith(externallyChanged: true));
      return;
    }
    await reload(index);
  }

  Future<void> reload(int index) async {
    if (index < 0 || index >= state.tabs.length) {
      return;
    }
    final OpenTab tab = state.tabs[index];
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(tab.rootIndex);
    if (root == null) {
      return;
    }
    try {
      final OpenTab fresh = await _loader.load(
        node: tab.node,
        rootIndex: tab.rootIndex,
        provider: root.provider,
        settings: ref.read(settingsProvider),
        preview: tab.isPreview,
      );
      replaceTab(index, fresh);
      setTextSilently(fresh.key, fresh.text);
    } on AppFailure catch (failure) {
      state = state.copyWith(error: failure);
    }
  }

  /// Keeps the current buffer and clears the external-change banner. The next
  /// save overwrites what is on disk, which is what the user chose.
  void keepMyChanges(int index) {
    if (index < 0 || index >= state.tabs.length) {
      return;
    }
    replaceTab(index, state.tabs[index].copyWith(externallyChanged: false));
  }

  void dismissNotice(int index) {
    if (index < 0 || index >= state.tabs.length) {
      return;
    }
    replaceTab(index, state.tabs[index].copyWith(clearNotice: true));
  }

  /// Updates every tab whose path sits under [oldId] after a move or rename.
  void onPathChanged(String oldId, String newId) {
    final List<OpenTab> tabs = <OpenTab>[];
    bool changed = false;
    for (final OpenTab tab in state.tabs) {
      if (tab.node.id == oldId) {
        tabs.add(tab.copyWith(node: _rebase(tab.node, oldId, newId)));
        changed = true;
      } else if (tab.node.id.startsWith('$oldId/')) {
        final String updated = newId + tab.node.id.substring(oldId.length);
        tabs.add(tab.copyWith(node: _rebase(tab.node, tab.node.id, updated)));
        changed = true;
      } else {
        tabs.add(tab);
      }
    }
    if (changed) {
      state = state.copyWith(tabs: tabs);
    }
    _followHistory(oldId, newId);
  }

  /// Keeps a file's recorded history attached to it after a rename or move.
  ///
  /// Covers files that are not open too, by rebasing on the relative path
  /// prefix — which is why the history key is built from that path rather than
  /// from a provider id.
  void _followHistory(String oldId, String newId) {
    final OpenWorkspace? workspace = ref.read(workspaceProvider);
    if (workspace == null) {
      return;
    }
    for (final LiveRoot root in workspace.roots) {
      final String oldRelative = relativePathIn(
        root.provider,
        root.root.rootId,
        oldId,
        fallback: '',
      );
      final String newRelative = relativePathIn(
        root.provider,
        root.root.rootId,
        newId,
        fallback: '',
      );
      if (oldRelative.isEmpty || newRelative.isEmpty) {
        continue;
      }
      unawaited(ref.read(fileHistoryProvider).onPathChanged(
            provider: root.provider,
            rootId: root.root.rootId,
            oldRelative: oldRelative,
            newRelative: newRelative,
            name: root.provider.nameOf(newId),
            displayPath: newId,
          ));
    }
  }

  FileNode _rebase(FileNode node, String oldId, String newId) {
    final int slash = newId.lastIndexOf(RegExp(r'[/\\]'));
    return node.copyWith(
      id: newId,
      name: slash < 0 ? newId : newId.substring(slash + 1),
      displayPath: newId,
    );
  }

  // --- internals ------------------------------------------------------------

  @override
  void replaceTab(int index, OpenTab tab) {
    final List<OpenTab> tabs = List<OpenTab>.of(state.tabs);
    tabs[index] = tab;
    state = state.copyWith(tabs: tabs);
  }

  void _disposeAll() {
    disposeAllControllers();
    clearClosedHistory();
  }
}

final NotifierProvider<TabsController, TabsState> tabsProvider =
    NotifierProvider<TabsController, TabsState>(TabsController.new);
