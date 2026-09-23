/// The main screen: top bar, tab strip, explorer panel, editor, breadcrumbs and
/// status bar.
///
/// This is the only place that knows how the pieces fit together. Features
/// expose widgets and controllers; the shell wires them and owns the dialogs,
/// because only it has a [BuildContext] that outlives a single panel.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/constants/app_info.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/core/utils/relative_path.dart';
import 'package:pocket_code/data/models/accessory_key.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/features/commands/application/shell_commands.dart';
import 'package:pocket_code/features/commands/presentation/command_palette.dart';
import 'package:pocket_code/features/commands/presentation/command_shortcuts.dart';
import 'package:pocket_code/features/commands/presentation/quick_open.dart';
import 'package:pocket_code/features/editor/application/edit_lock.dart';
import 'package:pocket_code/features/editor/application/editor_actions.dart';
import 'package:pocket_code/features/editor/presentation/editor_pane.dart';
import 'package:pocket_code/features/editor/presentation/toolbars/accessory_bar.dart';
import 'package:pocket_code/features/editor/presentation/toolbars/bottom_toolbar.dart';
import 'package:pocket_code/features/explorer/application/tree_controller.dart';
import 'package:pocket_code/features/explorer/presentation/explorer_panel.dart';
import 'package:pocket_code/features/history/application/history_controller.dart';
import 'package:pocket_code/features/runner/application/run_session.dart';
import 'package:pocket_code/features/runner/presentation/run_pane.dart';
import 'package:pocket_code/features/search/presentation/search_panel.dart';
import 'package:pocket_code/features/settings/presentation/settings_screen.dart';
import 'package:pocket_code/features/shell/presentation/breadcrumbs.dart';
import 'package:pocket_code/features/shell/presentation/close_prompt.dart';
import 'package:pocket_code/features/shell/presentation/explorer_scaffold.dart';
import 'package:pocket_code/features/shell/presentation/shell_editor_actions.dart';
import 'package:pocket_code/features/shell/presentation/shell_repo_actions.dart';
import 'package:pocket_code/features/shell/presentation/shell_toolbar_actions.dart';
import 'package:pocket_code/features/shell/presentation/top_bar.dart';
import 'package:pocket_code/features/tabs/application/tabs_controller.dart';
import 'package:pocket_code/features/tabs/application/tabs_state.dart';
import 'package:pocket_code/features/tabs/presentation/tab_strip.dart';
import 'package:pocket_code/features/workspace/application/session_controller.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/runner/html_bundler.dart';
import 'package:pocket_code/services/runner/python_runtime.dart';
import 'package:pocket_code/services/runner/run_target.dart';
import 'package:pocket_code/services/search/file_indexer.dart';
import 'package:pocket_code/services/search/search_scope.dart';
import 'package:pocket_code/services/search/workspace_search.dart';
import 'package:re_editor/re_editor.dart';

class EditorShell extends ConsumerStatefulWidget {
  const EditorShell({super.key});

  @override
  ConsumerState<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends ConsumerState<EditorShell>
    with
        WidgetsBindingObserver,
        ShellEditorActions<EditorShell>,
        ShellToolbarActions<EditorShell>,
        ShellRepoActions<EditorShell> {
  @override
  final ExplorerPanelController panel = ExplorerPanelController();

  bool _dockedOpened = false;

  /// Delay before history housekeeping runs. Long enough to be well clear of
  /// the first frames and any session restore, which matter more than tidying.
  static const Duration _sweepDelay = Duration(seconds: 6);

  Timer? _sweep;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Housekeeping, well after the first frame. It cannot go to an isolate —
    // every step is an async provider call, and SAF and web have none — so it
    // yields between folders instead.
    _sweep = Timer(
      _sweepDelay,
      () => unawaited(ref.read(fileHistoryProvider).sweep()),
    );
    // Registered once. The handlers read live state through `ref` when they
    // run, so they never go stale and never need re-registering.
    ref
        .read(commandRegistryProvider)
        .registerAll(
          buildShellCommands(
            ref,
            ShellCommandHooks(
              openSettings: _openSettings,
              toggleExplorer: () async => panel.toggle(),
              goToLine: promptGoToLine,
              closeWorkspace: _closeWorkspace,
              closeActiveTab: _closeActiveTab,
              quickOpen: _quickOpen,
              showOutline: openOutline,
              searchWorkspace: _searchWorkspace,
              formatDocument: formatDocument,
              runDocument: runDocument,
              jumpToMatchingBracket: jumpToBracket,
              insertSnippet: openSnippetPicker,
              compareWithSaved: openCompareWithSaved,
              showFileHistory: openFileHistory,
              proposeChanges: proposeWorkspaceChanges,
            ),
          ),
        );
  }

  /// Opens the palette, then runs whatever was picked.
  Future<void> _openPalette() async {
    await showCommandPalette(
      context,
      registry: ref.read(commandRegistryProvider),
    );
  }

  /// Walks the workspace and lets the user pick a file by name.
  ///
  /// The walk starts when the sheet opens rather than being cached: a cached
  /// index goes stale the moment a file is created, and showing a file that no
  /// longer exists is worse than waiting a moment.
  Future<void> _quickOpen() async {
    if (ref.read(workspaceProvider) == null) {
      return;
    }
    final IndexedFile? chosen =
        await showQuickOpen(context, index: _indexWorkspace());
    if (chosen == null || !mounted) {
      return;
    }
    await _openFile(chosen.node, chosen.rootIndex);
  }

  /// Builds a fresh index of the workspace for a search or Quick Open.
  ///
  /// Rebuilt each time rather than cached: an index goes stale the moment a
  /// file is created, and offering a file that no longer exists is worse than
  /// waiting a moment.
  ///
  /// With a [scope], only that folder's root is walked, and the walk starts at
  /// the folder — so Find in Folder lists nothing outside it.
  Future<FileIndex> _indexWorkspace({SearchScope? scope}) {
    final OpenWorkspace? workspace = ref.read(workspaceProvider);
    if (workspace == null) {
      return Future<FileIndex>.value(const FileIndex.empty());
    }
    final AppSettings settings = ref.read(settingsProvider);
    return const FileIndexer().build(
      <IndexRoot>[
        for (int i = 0; i < workspace.roots.length; i++)
          if (scope == null || scope.rootIndex == i)
            IndexRoot(
              provider: workspace.roots[i].provider,
              rootId: workspace.roots[i].root.rootId,
              rootIndex: i,
              startId: scope?.folderId,
              startPath: scope?.relativePath ?? '',
            ),
      ],
      showHidden: settings.showHiddenFiles,
      excludePatterns: settings.excludePatterns,
    );
  }

  FileSystemProvider _providerFor(int rootIndex) =>
      ref.read(workspaceProvider)!.roots[rootIndex].provider;

  /// Opens the workspace search screen.
  Future<void> _searchWorkspace() => _openSearch();

  /// "Find in Folder…" from the explorer: the same search, confined to
  /// [folder].
  Future<void> _findInFolder(FolderNode folder, int rootIndex) async {
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(rootIndex);
    if (root == null) {
      return;
    }
    final SearchScope scope = SearchScope(
      rootIndex: rootIndex,
      folderId: folder.id,
      // Walked, never split: a SAF id is a percent-encoded URI.
      relativePath: relativePathIn(
        root.provider,
        root.root.rootId,
        folder.id,
        fallback: folder.name,
      ),
      name: folder.name,
    );
    // The search screen covers everything anyway; leaving the drawer open
    // underneath would greet the user with it on the way back.
    panel.close();
    await _openSearch(scope: scope);
  }

  Future<void> _openSearch({SearchScope? scope}) async {
    if (ref.read(workspaceProvider) == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SearchPanel(
          initialScope: scope,
          onSearch: (SearchQuery query, SearchScope? scope) async =>
              const WorkspaceSearch().run(
            index: await _indexWorkspace(scope: scope),
            query: query,
            providerFor: _providerFor,
          ),
          onReplaceAll: _replaceAcrossWorkspace,
          onOpenHit: _openSearchHit,
        ),
      ),
    );
  }

  /// Opens the file a result came from and lands on the match.
  Future<void> _openSearchHit(FileMatches group, SearchMatch match) async {
    Navigator.of(context).pop();
    await _openFile(group.file.node, group.file.rootIndex);
    if (!mounted) {
      return;
    }
    final OpenTab? tab = ref.read(tabsProvider).active;
    if (tab != null) {
      EditorActions(ref.read(tabsProvider.notifier).controllerFor(tab))
          .goToLine(match.line);
    }
  }

  /// Rewrites every match across the workspace. Returns the files changed.
  ///
  /// An open tab is updated through its controller rather than on disk, so the
  /// buffer the user is looking at does not silently disagree with the file —
  /// and their undo history still works.
  Future<int> _replaceAcrossWorkspace(
    SearchQuery query,
    String replacement,
    SearchScope? scope,
  ) async {
    // Re-indexed with the same scope the results were shown with, so nothing
    // outside the folder the user was looking at is ever rewritten.
    final SearchResults results = await const WorkspaceSearch().run(
      index: await _indexWorkspace(scope: scope),
      query: query,
      providerFor: _providerFor,
    );

    final TabsController tabs = ref.read(tabsProvider.notifier);
    int changed = 0;
    for (final FileMatches group in results.files) {
      final FileSystemProvider provider = _providerFor(group.file.rootIndex);
      final String key = '${group.file.rootIndex}:${group.file.node.id}';
      final int openIndex = ref.read(tabsProvider).indexOfKey(key);

      try {
        if (openIndex >= 0) {
          final OpenTab open = ref.read(tabsProvider).tabs[openIndex];
          final CodeLineEditingController controller = tabs.controllerFor(open);
          controller.text =
              replaceAllInText(controller.text, query, replacement);
        } else {
          final TextFileContents contents =
              await provider.readText(group.file.node.id);
          await provider.writeText(
            group.file.node.id,
            replaceAllInText(contents.text, query, replacement),
            contents.format,
          );
        }
        changed++;
      } on AppFailure {
        // One unwritable file must not abort the rest; the count reported back
        // is what actually changed.
        continue;
      }
    }
    return changed;
  }

  /// Runs the active document, or explains why it cannot be run.
  ///
  /// Reads the live buffer rather than the file on disk, so Run previews what
  /// is on screen — including edits that have not been saved.
  @override
  Future<void> runDocument() async {
    final OpenTab? tab = ref.read(tabsProvider).active;
    final RunTarget target = runTargetFor(tab);
    if (tab == null || !target.canRun) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(target.explain(tab?.language.label ?? 'This')),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return;
    }

    final String source =
        ref.read(tabsProvider.notifier).controllerFor(tab).text;
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(tab.rootIndex);

    String html;
    List<String> notes = const <String>[];
    switch (target.kind) {
      case RunKind.htmlPage:
        // Siblings are inlined because a `loadHtmlString` page has no origin
        // and so cannot resolve `style.css` next to it.
        if (root != null) {
          final BundledPage bundled = await const HtmlBundler().bundle(
            html: source,
            fileId: tab.node.id,
            provider: root.provider,
          );
          html = withConsoleBridge(bundled.html);
          notes = bundled.notes;
        } else {
          html = withConsoleBridge(source);
        }
      case RunKind.javascript:
        html = javascriptHarness(source);
      case RunKind.python:
        html = await const PythonRuntime().harness(source);
      case RunKind.none:
        return;
    }

    ref.read(runSessionProvider.notifier).start(
          RunSession(
            tabKey: tab.key,
            title: tab.node.name,
            html: html,
            notes: notes,
          ),
        );
  }

  /// Closes whichever tab is active, prompting about unsaved work.
  Future<void> _closeActiveTab() async {
    final int index = ref.read(tabsProvider).activeIndex;
    if (index >= 0) {
      await closeTabAt(index);
    }
  }

  @override
  void dispose() {
    _sweep?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    panel.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.inactive ||
        lifecycle == AppLifecycleState.paused) {
      // "Save when the app loses focus" is a setting; the controller checks it.
      ref.read(tabsProvider.notifier).onFocusLost();
      // Hot exit runs regardless of that setting: the OS may kill the process
      // at any moment after this point, without another callback.
      unawaited(ref.read(sessionControllerProvider).backupUnsavedBuffers());
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  Future<void> _openFile(FileNode file, int rootIndex) async {
    await ref.read(tabsProvider.notifier).open(file, rootIndex);
    ref.read(treeProvider.notifier).setActiveFile(file.id);

    if (!mounted) {
      return;
    }
    // On a phone the panel covers half the editor, so leaving it open hides the
    // very thing the user just asked to see.
    final bool isPhone =
        MediaQuery.sizeOf(context).width < AppSizes.tabletBreakpoint;
    if (isPhone && ref.read(settingsProvider).closeExplorerAfterOpen) {
      panel.close();
    }
  }

  /// Which toolbar actions are available for the current tab.
  ///
  /// Computed rather than cached because it depends on the buffer's dirty and
  /// undo state, both of which change as you type.
  Set<EditorToolbarAction> _enabledActions(OpenTab? tab) {
    if (tab == null) {
      return const <EditorToolbarAction>{};
    }
    final EditorActions actions = EditorActions(
      ref.read(tabsProvider.notifier).controllerFor(tab),
    );
    return <EditorToolbarAction>{
      EditorToolbarAction.find,
      EditorToolbarAction.goToLine,
      EditorToolbarAction.wordWrap,
      // Always enabled: choosing it on a C file is how you learn *why* it
      // cannot run, which beats a grey row that explains nothing.
      EditorToolbarAction.run,
      if (actions.canUndo) EditorToolbarAction.undo,
      if (actions.canRedo) EditorToolbarAction.redo,
      if (tab.isDirty) EditorToolbarAction.save,
      if (ref.read(tabsProvider).anyDirty) EditorToolbarAction.saveAll,
      // Editing actions are pointless on a buffer that cannot be typed into,
      // whether that is the document's own restriction or the edit lock.
      if (isTabEditable(tab, ref.watch(editLockProvider)))
        ...<EditorToolbarAction>{
        EditorToolbarAction.indent,
        EditorToolbarAction.outdent,
        if (EditorActions.canComment(tab.language))
          EditorToolbarAction.toggleComment,
      },
    };
  }

  /// Root-relative path segments of the active file, for the breadcrumbs.
  List<String> _breadcrumbSegments(OpenTab tab) {
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(tab.rootIndex);
    if (root == null) {
      return <String>[tab.node.name];
    }
    // Walk up through the provider rather than splitting the id on slashes.
    // An id is opaque: a SAF id is a `content://` URI whose document part is
    // percent-encoded, and splitting it produced breadcrumbs like "%2Fnote.txt".
    final FileSystemProvider provider = root.provider;
    final List<String> segments = <String>[];
    String? id = tab.node.id;
    // Bounded so a provider whose parentOf never terminates cannot hang the UI.
    for (int depth = 0; id != null && id != root.root.rootId && depth < 64; depth++) {
      segments.insert(0, provider.nameOf(id));
      final String? parent = provider.parentOf(id);
      if (parent == id) {
        break;
      }
      id = parent;
    }
    return <String>[root.root.name, ...segments];
  }


  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context)
        .extension<AppColorTokens>()!;
    final TabsState tabsState = ref.watch(tabsProvider);
    // Any change to the tab set or the workspace is worth remembering; the
    // controller debounces so this costs one write per burst, not per keystroke.
    ref.read(sessionControllerProvider).markDirty();
    final OpenTab? tab = tabsState.active;
    final bool isPhone =
        MediaQuery.sizeOf(context).width < AppSizes.tabletBreakpoint;
    // Non-zero bottom inset means the soft keyboard is on screen — but it may
    // belong to a dialog stacked over the shell (Go to line, a close prompt),
    // not to the editor. Showing the accessory keys then would offer bracket
    // keys that the modal barrier swallows, and that would type into the
    // document rather than the dialog if they were reachable.
    final bool shellIsForeground = ModalRoute.of(context)?.isCurrent ?? true;
    final bool keyboardVisible =
        shellIsForeground && MediaQuery.viewInsetsOf(context).bottom > 0;

    if (!isPhone && !_dockedOpened) {
      _dockedOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        panel.openImmediately();
      });
    }

    return CommandShortcuts(
      registry: ref.read(commandRegistryProvider),
      child: PopScope(
        // The back button closes the explorer before it does anything else.
        canPop: !panel.isVisible,
        onPopInvokedWithResult: (bool didPop, _) {
          if (!didPop && panel.isVisible) {
            panel.close();
          }
        },
        child: Scaffold(
          backgroundColor: tokens.background,
          appBar: TopBar(
            panel: panel,
            onCommandPalette: _openPalette,
            onQuickOpen: _quickOpen,
            hasWorkspace: ref.watch(workspaceProvider) != null,
            canToggleEditing: canToggleEditing(tab),
            isEditable:
                tab != null && isTabEditable(tab, ref.watch(editLockProvider)),
            onToggleEditing: toggleEditing,
            title: tab?.node.name ?? AppInfo.name,
            isDirty: tab?.isDirty ?? false,
            anyDirty: tabsState.anyDirty,
            onSave: () => ref.read(tabsProvider.notifier).save(),
            onSaveAll: () => ref.read(tabsProvider.notifier).saveAll(),
            onCloseWorkspace: _closeWorkspace,
            onSettings: _openSettings,
          ),
          body: ExplorerScaffold(
            controller: panel,
            panel: ExplorerPanel(
              onOpenFile: _openFile,
              onCloseFolder: _closeWorkspace,
              onFindInFolder: _findInFolder,
              onProposeChanges: (FolderNode folder, int rootIndex) =>
                  proposeChanges(folder.id, folder.name, rootIndex),
            ),
            body: Column(
              children: <Widget>[
                TabStrip(
                  onAction: handleTabAction,
                  onCloseRequested: closeTabAt,
                ),
                if (tab != null)
                  Breadcrumbs(
                    segments: _breadcrumbSegments(tab),
                    onTapSegment: (int _) => panel.open(),
                  ),
                Expanded(child: EditorPane(onRerun: runDocument)),
                if (tab != null &&
                    tab.restriction != DocumentRestriction.binary &&
                    tab.restriction != DocumentRestriction.image)
                  StatusBarForTab(tab: tab),
                // The accessory bar replaces the toolbar while the keyboard is
                // up: both at once would eat a third of a phone screen, and the
                // keyboard is exactly when the bracket keys are wanted.
                if (tab != null)
                  if (keyboardVisible)
                    if (ref.watch(settingsProvider).showAccessoryBar)
                      AccessoryBar(
                        keys: AccessoryKeyLayouts.fromTokens(
                          ref.watch(settingsProvider).accessoryKeyTokens,
                        ),
                        onKey: handleAccessoryKey,
                        onScrub: handleAccessoryScrub,
                      )
                    else
                      const SizedBox.shrink()
                  else
                    EditorBottomToolbar(
                      enabled: _enabledActions(tab),
                      onAction: handleToolbarAction,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _closeWorkspace() async {
    final TabsController tabs = ref.read(tabsProvider.notifier);
    if (ref.read(tabsProvider).anyDirty) {
      final CloseChoice choice = await promptToCloseWorkspace(context);
      switch (choice) {
        case CloseChoice.cancel:
          return;
        case CloseChoice.discard:
          break;
        case CloseChoice.save:
          if (!await tabs.saveAll()) {
            return;
          }
      }
    }
    tabs.closeAll(force: true);
    ref.read(workspaceProvider.notifier).close();
  }
}

/// Isolates the status bar's rebuilds to the active tab's controller.
