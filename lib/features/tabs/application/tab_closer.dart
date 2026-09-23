/// Closing tabs, and reopening the last one closed.
///
/// Split out of `TabsController` for size. The rule worth keeping in view is
/// that closing never decides on its own whether unsaved work may be discarded:
/// [close] reports that a prompt is needed and the UI owns the dialog.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/features/tabs/application/tabs_state.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';

mixin TabCloser on Notifier<TabsState> {
  final List<ClosedTab> _closed = <ClosedTab>[];

  // Implemented by `TabsController`.
  void replaceTab(int index, OpenTab tab);
  void disposeControllerFor(String key);
  void restoreEditorState(EditorState editorState);
  Future<void> open(FileNode node, int rootIndex, {bool preview});

  /// Closes the tab at [index], releasing its editor controller.
  ///
  /// Returns false if the caller should prompt first — that is, the tab is
  /// dirty and the "confirm closing unsaved files" setting is on. The UI owns
  /// the dialog; this class only reports that one is needed.
  bool close(int index, {bool force = false}) {
    if (index < 0 || index >= state.tabs.length) {
      return true;
    }
    final OpenTab tab = state.tabs[index];
    if (!force &&
        tab.isDirty &&
        ref.read(settingsProvider).confirmCloseUnsaved) {
      return false;
    }

    _closed.insert(
      0,
      ClosedTab(
        fileId: tab.node.id,
        rootIndex: tab.rootIndex,
        name: tab.node.name,
        editorState: tab.editorState,
      ),
    );
    if (_closed.length > AppLimits.reopenableTabHistory) {
      _closed.removeLast();
    }

    disposeControllerFor(tab.key);
    final List<OpenTab> tabs = List<OpenTab>.of(state.tabs)..removeAt(index);

    // Activate the neighbour on the left, which is what a user expects after
    // closing the rightmost tab.
    int active = state.activeIndex;
    if (tabs.isEmpty) {
      active = -1;
    } else if (index < active) {
      active -= 1;
    } else if (index == active) {
      active = index > 0 ? index - 1 : 0;
    }

    state = state.copyWith(tabs: tabs, activeIndex: active);
    return true;
  }

  /// Closes every tab except [index]. Dirty tabs are kept unless [force].
  void closeOthers(int index, {bool force = false}) {
    final OpenTab? keep =
        index >= 0 && index < state.tabs.length ? state.tabs[index] : null;
    if (keep == null) {
      return;
    }
    _closeWhere((OpenTab t) => t.key != keep.key, force: force);
  }

  void closeToTheRight(int index, {bool force = false}) {
    if (index < 0 || index >= state.tabs.length) {
      return;
    }
    final Set<String> doomed =
        state.tabs.skip(index + 1).map((OpenTab t) => t.key).toSet();
    _closeWhere((OpenTab t) => doomed.contains(t.key), force: force);
  }

  void closeSaved() => _closeWhere((OpenTab t) => !t.isDirty, force: true);

  void closeAll({bool force = false}) =>
      _closeWhere((OpenTab _) => true, force: force);

  void _closeWhere(bool Function(OpenTab) predicate, {required bool force}) {
    final bool confirm = ref.read(settingsProvider).confirmCloseUnsaved;
    for (int i = state.tabs.length - 1; i >= 0; i--) {
      final OpenTab tab = state.tabs[i];
      if (!predicate(tab)) {
        continue;
      }
      if (!force && tab.isDirty && confirm) {
        continue;
      }
      close(i, force: true);
    }
  }

  /// Tabs that still need a save prompt before a bulk close can finish.
  List<int> dirtyTabIndices() => <int>[
        for (int i = 0; i < state.tabs.length; i++)
          if (state.tabs[i].isDirty) i,
      ];

  /// Reopens the most recently closed tab, if its file still exists.
  Future<void> reopenClosed() async {
    if (_closed.isEmpty) {
      return;
    }
    final ClosedTab closed = _closed.removeAt(0);
    final LiveRoot? root =
        ref.read(workspaceProvider)?.rootAt(closed.rootIndex);
    if (root == null) {
      return;
    }
    try {
      final FileSystemNode node = await root.provider.stat(closed.fileId);
      if (node is FileNode) {
        await open(node, closed.rootIndex, preview: false);
        restoreEditorState(closed.editorState);
      }
    } on AppFailure {
      // The file was deleted since it was closed. Drop it silently and let the
      // user try again for the next one in the history.
    }
  }

  void clearClosedHistory() => _closed.clear();
}
