/// Loads folder children and flattens the tree into rows for the list view.
///
/// Loading is lazy and cached: a folder's children are fetched on first expand
/// and kept until an explicit refresh. Collapsing does not discard them, so
/// re-expanding is instant.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/constants/app_info.dart';
import 'package:pocket_code/core/constants/durations.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/features/explorer/application/tree_state.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';

class TreeController extends Notifier<TreeState> {
  /// Raw children per `rootIndex:folderId`, before sorting or filtering.
  final Map<String, List<FileSystemNode>> _children =
      <String, List<FileSystemNode>>{};

  /// One watcher per expanded folder, on providers that can watch at all.
  final Map<String, StreamSubscription<FileChangeEvent>> _watchers =
      <String, StreamSubscription<FileChangeEvent>>{};

  /// Coalesces bursts: a single save can emit several events, and re-reading
  /// the folder once per event would thrash the list.
  final Map<String, Timer> _watchDebounce = <String, Timer>{};

  @override
  TreeState build() {
    // Rebuilding the rows when settings change means toggling "show hidden
    // files" is instant — no folder is re-read from disk.
    ref.listen(settingsProvider, (AppSettings? _, AppSettings _) {
      state = state.copyWith(rows: _flatten());
    });
    // Explicit type argument: the state itself is nullable, so inference
    // cannot tell `OpenWorkspace?` (the state) from the nullable "previous".
    ref.listen<OpenWorkspace?>(workspaceProvider,
        (OpenWorkspace? previous, OpenWorkspace? next) {
      if (previous != next) {
        _cancelWatchers();
        _children.clear();
        state = const TreeState();
        unawaited(_loadRoots());
      }
    });
    ref.onDispose(_cancelWatchers);

    if (ref.read(workspaceProvider) != null) {
      // Deferred to a microtask: _loadRoots reads `state`, and reading it from
      // inside build() is reading a provider that has not finished
      // initialising. This path is taken when a workspace already exists when
      // the tree is first watched — restoring a session, or a test.
      Future<void>.microtask(_loadRoots);
    }
    return const TreeState();
  }

  String _key(int rootIndex, String nodeId) => '$rootIndex:$nodeId';

  /// Starts watching a folder, if this provider can watch at all.
  ///
  /// `ProviderCapabilities.canWatch` is false for SAF and for the browser, and
  /// those providers return an empty stream — so this is a no-op there rather
  /// than a polling loop pretending to be a watcher.
  void _watchFolder(int rootIndex, String folderId) {
    final String key = _key(rootIndex, folderId);
    if (_watchers.containsKey(key)) {
      return;
    }
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(rootIndex);
    if (root == null || !root.provider.capabilities.canWatch) {
      return;
    }
    _watchers[key] = root.provider.watch(folderId).listen(
      (FileChangeEvent _) {
        _watchDebounce[key]?.cancel();
        _watchDebounce[key] = Timer(AppDurations.watchDebounce, () {
          unawaited(refreshFolder(rootIndex, folderId));
        });
      },
      // A watcher that dies must not take the explorer with it: the folder is
      // still usable, it just stops updating by itself until the next refresh.
      onError: (Object _) => _unwatchFolder(key),
    );
  }

  void _unwatchFolder(String key) {
    _watchers.remove(key)?.cancel();
    _watchDebounce.remove(key)?.cancel();
  }

  void _cancelWatchers() {
    for (final StreamSubscription<FileChangeEvent> sub in _watchers.values) {
      sub.cancel();
    }
    for (final Timer timer in _watchDebounce.values) {
      timer.cancel();
    }
    _watchers.clear();
    _watchDebounce.clear();
  }

  Future<void> _loadRoots() async {
    final OpenWorkspace? workspace = ref.read(workspaceProvider);
    if (workspace == null) {
      return;
    }
    for (int i = 0; i < workspace.roots.length; i++) {
      final LiveRoot root = workspace.roots[i];
      // Roots start expanded: an explorer that opens showing nothing is not
      // useful, and a root's own children are one cheap listing.
      state = state.copyWith(
        expanded: <String>{...state.expanded, _key(i, root.root.rootId)},
      );
      await _loadChildren(i, root.root.rootId);
    }
  }

  Future<void> _loadChildren(int rootIndex, String folderId) async {
    final OpenWorkspace? workspace = ref.read(workspaceProvider);
    final LiveRoot? root = workspace?.rootAt(rootIndex);
    if (root == null) {
      return;
    }
    final String key = _key(rootIndex, folderId);

    // Only show a spinner if the listing is actually slow. Flashing one for
    // 40ms reads as a glitch.
    final Timer spinner = Timer(AppDurations.listingSpinnerThreshold, () {
      state = state.copyWith(
        loading: <String>{...state.loading, key},
        rows: _flatten(),
      );
    });

    try {
      final List<FileSystemNode> children = await root.provider.list(folderId);
      _children[key] = children;
      // Watch only what is actually on screen. Watching the whole tree would
      // hold an inotify handle per folder, and Android caps those.
      _watchFolder(rootIndex, folderId);
      state = state.copyWith(clearError: true);
    } on AppFailure catch (failure) {
      // A folder that cannot be read collapses again with the reason shown,
      // rather than sitting open and empty as if it really were empty.
      state = state.copyWith(
        expanded: <String>{...state.expanded}..remove(key),
        error: '${failure.message}. ${failure.hint}',
      );
    } finally {
      spinner.cancel();
      state = state.copyWith(
        loading: <String>{...state.loading}..remove(key),
        rows: _flatten(),
      );
    }
  }

  /// Expands or collapses a folder, loading its children on first expand.
  Future<void> toggle(TreeRow row) async {
    if (!row.isFolder) {
      return;
    }
    final String key = row.key;
    if (state.expanded.contains(key)) {
      state = state.copyWith(
        expanded: <String>{...state.expanded}..remove(key),
      );
      // A collapsed folder is not visible, so nothing needs to notice it change.
      _unwatchFolder(key);
      state = state.copyWith(rows: _flatten());
      return;
    }
    state = state.copyWith(expanded: <String>{...state.expanded, key});
    if (_children.containsKey(key)) {
      // Already cached from a previous expand — no listing, no flicker.
      state = state.copyWith(rows: _flatten());
      return;
    }
    await _loadChildren(row.rootIndex, row.node.id);
  }

  /// Re-reads a folder from disk, discarding the cache for it.
  Future<void> refresh([TreeRow? row]) async {
    if (row == null) {
      _children.clear();
      state = state.copyWith(rows: <TreeRow>[]);
      final Set<String> wasExpanded = state.expanded;
      await _loadRoots();
      // Re-fetch everything the user had open, so a refresh does not collapse
      // the tree they were working in.
      for (final String key in wasExpanded) {
        final int split = key.indexOf(':');
        if (split < 0) {
          continue;
        }
        final int rootIndex = int.tryParse(key.substring(0, split)) ?? 0;
        final String id = key.substring(split + 1);
        if (!_children.containsKey(key)) {
          await _loadChildren(rootIndex, id);
        }
      }
      return;
    }
    _children.remove(row.key);
    await _loadChildren(row.rootIndex, row.node.id);
  }

  /// Re-reads one folder by id, for callers that changed its contents without
  /// having a [TreeRow] in hand — a paste, a drag-and-drop move, an undo.
  ///
  /// A folder that was never expanded has nothing cached to go stale, so this
  /// only re-flattens; the next expand reads the current contents anyway.
  Future<void> refreshFolder(int rootIndex, String folderId) async {
    final String key = _key(rootIndex, folderId);
    if (!_children.containsKey(key)) {
      state = state.copyWith(rows: _flatten());
      return;
    }
    _children.remove(key);
    await _loadChildren(rootIndex, folderId);
  }

  /// Expands [folderId] by id, loading it if needed. Used by drag-and-drop,
  /// which hovers over a collapsed folder and must open it without a row.
  Future<void> expandFolder(int rootIndex, String folderId) async {
    final String key = _key(rootIndex, folderId);
    if (state.expanded.contains(key)) {
      return;
    }
    state = state.copyWith(expanded: <String>{...state.expanded, key});
    if (_children.containsKey(key)) {
      state = state.copyWith(rows: _flatten());
      return;
    }
    await _loadChildren(rootIndex, folderId);
  }

  /// The root folder id for a workspace root, or null if the index is stale.
  String? rootIdFor(int rootIndex) =>
      ref.read(workspaceProvider)?.rootAt(rootIndex)?.root.rootId;

  /// Surfaces a failed operation in the panel's inline error strip.
  void reportFailure(AppFailure failure) {
    state = state.copyWith(error: '${failure.message}. ${failure.hint}');
  }

  void clearError() => state = state.copyWith(clearError: true);

  /// Creates a file in [parentId] and re-reads that folder so the new entry
  /// appears. Returns the new node's id, or null if creation failed.
  Future<String?> createFile(int rootIndex, String parentId, String name) async {
    return _create(
      rootIndex,
      parentId,
      (LiveRoot root) => root.provider.createFile(parentId, name),
    );
  }

  Future<String?> createFolder(
    int rootIndex,
    String parentId,
    String name,
  ) async {
    return _create(
      rootIndex,
      parentId,
      (LiveRoot root) => root.provider.createFolder(parentId, name),
    );
  }

  Future<String?> _create(
    int rootIndex,
    String parentId,
    Future<FileSystemNode> Function(LiveRoot) action,
  ) async {
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(rootIndex);
    if (root == null) {
      return null;
    }
    try {
      final FileSystemNode created = await action(root);
      // Expand the parent so the new item is visible, then re-read it.
      state = state.copyWith(
        expanded: <String>{...state.expanded, _key(rootIndex, parentId)},
        clearError: true,
      );
      _children.remove(_key(rootIndex, parentId));
      await _loadChildren(rootIndex, parentId);
      return created.id;
    } on AppFailure catch (failure) {
      state = state.copyWith(error: '${failure.message}. ${failure.hint}');
      return null;
    }
  }

  /// Deletes an entry and refreshes its parent folder.
  Future<bool> delete(TreeRow row) async {
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(row.rootIndex);
    if (root == null) {
      return false;
    }
    try {
      await root.provider.delete(row.node.id);
      final String parentId =
          root.provider.parentOf(row.node.id) ?? root.root.rootId;
      _children.remove(_key(row.rootIndex, parentId));
      await _loadChildren(row.rootIndex, parentId);
      state = state.copyWith(clearError: true);
      return true;
    } on AppFailure catch (failure) {
      state = state.copyWith(error: '${failure.message}. ${failure.hint}');
      return false;
    }
  }

  /// Renames an entry in place and refreshes its parent folder.
  Future<bool> rename(TreeRow row, String newName) async {
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(row.rootIndex);
    if (root == null) {
      return false;
    }
    try {
      await root.provider.rename(row.node.id, newName);
      final String parentId =
          root.provider.parentOf(row.node.id) ?? root.root.rootId;
      _children.remove(_key(row.rootIndex, parentId));
      await _loadChildren(row.rootIndex, parentId);
      state = state.copyWith(clearError: true);
      return true;
    } on AppFailure catch (failure) {
      state = state.copyWith(error: '${failure.message}. ${failure.hint}');
      return false;
    }
  }

  /// The folder a new item should go into, given the currently selected row.
  ///
  /// Matches what a user expects: with a folder selected, create inside it;
  /// with a file selected, create beside it.
  String targetFolderFor(TreeRow? row, int rootIndex) {
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(rootIndex);
    final String rootId = root?.root.rootId ?? '';
    if (row == null) {
      return rootId;
    }
    if (row.isFolder) {
      return row.node.id;
    }
    return root?.provider.parentOf(row.node.id) ?? rootId;
  }

  void collapseAll() {
    final OpenWorkspace? workspace = ref.read(workspaceProvider);
    if (workspace == null) {
      return;
    }
    // Roots stay open: collapsing them too would leave a blank panel.
    final Set<String> rootKeys = <String>{
      for (int i = 0; i < workspace.roots.length; i++)
        _key(i, workspace.roots[i].root.rootId),
    };
    // Commit the new expanded set BEFORE flattening: _flatten reads
    // state.expanded, and copyWith evaluates its arguments against the old
    // state, so doing both in one call would rebuild the old rows.
    // Everything that just collapsed stops being watched; the roots stay.
    for (final String key in _watchers.keys.toList()) {
      if (!rootKeys.contains(key)) {
        _unwatchFolder(key);
      }
    }
    state = state.copyWith(expanded: rootKeys);
    state = state.copyWith(rows: _flatten());
  }

  void setActiveFile(String? fileId) {
    state = state.copyWith(activeFileId: fileId, rows: state.rows);
  }

  /// Expands every ancestor of [fileId] so the file becomes visible, then marks
  /// it active. Used by "reveal in explorer" and by opening a file from search.
  Future<void> reveal(int rootIndex, String fileId) async {
    final OpenWorkspace? workspace = ref.read(workspaceProvider);
    final LiveRoot? root = workspace?.rootAt(rootIndex);
    if (root == null) {
      return;
    }
    final List<String> ancestors = <String>[];
    String? current = root.provider.parentOf(fileId);
    final String rootId = root.root.rootId;
    // Walk up to the root, collecting folders that need opening.
    while (current != null && current.isNotEmpty && current != rootId) {
      ancestors.insert(0, current);
      final String? next = root.provider.parentOf(current);
      if (next == current) {
        break;
      }
      current = next;
    }
    ancestors.insert(0, rootId);

    for (final String folderId in ancestors) {
      final String key = _key(rootIndex, folderId);
      state = state.copyWith(expanded: <String>{...state.expanded, key});
      if (!_children.containsKey(key)) {
        await _loadChildren(rootIndex, folderId);
      }
    }
    state = state.copyWith(activeFileId: fileId, rows: _flatten());
  }

  /// Index of [fileId] in the current rows, so the list can scroll to it.
  int indexOfFile(String fileId) =>
      state.rows.indexWhere((TreeRow r) => r.node.id == fileId);

  /// Walks the expanded tree depth-first, producing the flat row list.
  ///
  /// Cost is proportional to the number of *visible* rows, not to the size of
  /// the workspace, because collapsed folders contribute exactly one row.
  List<TreeRow> _flatten() {
    final OpenWorkspace? workspace = ref.read(workspaceProvider);
    if (workspace == null) {
      return const <TreeRow>[];
    }
    final AppSettings settings = ref.read(settingsProvider);
    final List<TreeRow> rows = <TreeRow>[];
    final bool multiRoot = workspace.isMultiRoot;

    for (int i = 0; i < workspace.roots.length; i++) {
      final LiveRoot root = workspace.roots[i];
      final String rootKey = _key(i, root.root.rootId);
      final bool rootExpanded = state.expanded.contains(rootKey);

      if (multiRoot) {
        // Each root is its own collapsible section header.
        rows.add(
          TreeRow(
            node: FolderNode(
              id: root.root.rootId,
              name: root.root.name,
              displayPath: root.root.displayPath ?? root.root.rootId,
            ),
            depth: 0,
            rootIndex: i,
            isExpanded: rootExpanded,
            isLoading: state.loading.contains(rootKey),
            isRootHeader: true,
          ),
        );
      }
      if (rootExpanded) {
        _appendChildren(
          rows: rows,
          rootIndex: i,
          folderId: root.root.rootId,
          depth: multiRoot ? 1 : 0,
          settings: settings,
        );
      }
    }
    return rows;
  }

  void _appendChildren({
    required List<TreeRow> rows,
    required int rootIndex,
    required String folderId,
    required int depth,
    required AppSettings settings,
  }) {
    final String key = _key(rootIndex, folderId);
    final List<FileSystemNode>? raw = _children[key];
    if (raw == null) {
      return;
    }
    final List<FileSystemNode> visible = TreeOrdering.sort(
      TreeOrdering.filter(
        // The undo trash is the app's own bookkeeping, not the user's content.
        // It is filtered here rather than in the exclude list so that turning
        // "show hidden files" on cannot expose it and invite someone to edit
        // inside a folder that is about to be purged.
        raw
            .where((FileSystemNode n) => n.name != AppInfo.trashFolderName)
            .toList(),
        showHidden: settings.showHiddenFiles,
        excludePatterns: settings.excludePatterns,
      ),
      settings.sortOrder,
    );

    for (final FileSystemNode node in visible) {
      final String childKey = _key(rootIndex, node.id);
      final bool expanded = state.expanded.contains(childKey);
      rows.add(
        TreeRow(
          node: node,
          depth: depth,
          rootIndex: rootIndex,
          isExpanded: expanded,
          isLoading: state.loading.contains(childKey),
        ),
      );
      if (expanded && node is FolderNode) {
        _appendChildren(
          rows: rows,
          rootIndex: rootIndex,
          folderId: node.id,
          depth: depth + 1,
          settings: settings,
        );
      }
    }
  }
}

final NotifierProvider<TreeController, TreeState> treeProvider =
    NotifierProvider<TreeController, TreeState>(TreeController.new);
