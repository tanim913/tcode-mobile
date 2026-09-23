/// Saves and restores the workspace session, and writes hot-exit backups.
///
/// Two jobs, deliberately in one place because they are two halves of the same
/// promise: *nothing you had open is lost, and nothing you typed is lost*.
///
/// * The **session** (which roots and tabs were open, and where the cursor was)
///   is written whenever it changes, debounced so typing does not cause a write
///   per keystroke.
/// * **Hot-exit backups** (the actual text of unsaved buffers) are written when
///   the app is paused, regardless of the auto-save setting, because the OS may
///   kill the process at any point afterwards without warning.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/data/models/workspace.dart';
import 'package:pocket_code/data/repositories/session_repository.dart';
import 'package:pocket_code/features/tabs/application/tabs_controller.dart';
import 'package:pocket_code/features/tabs/application/tabs_state.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/filesystem/root_resolver.dart';

/// Debounce for session writes. Long enough that a burst of tab switches costs
/// one write, short enough that a crash loses at most this much context.
const Duration _sessionWriteDebounce = Duration(milliseconds: 800);

class SessionController {
  SessionController(this._ref);

  final Ref _ref;
  Timer? _debounce;
  bool _restoring = false;

  SessionRepository? get _repository => _ref.read(sessionRepositoryProvider);

  /// Schedules a session write. Safe to call on every change.
  void markDirty() {
    if (_restoring) {
      return;
    }
    // No repository means session persistence is unavailable on this platform
    // or this launch. Starting a debounce that can only no-op would leave a
    // timer running for nothing.
    if (_repository == null) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(_sessionWriteDebounce, () => unawaited(saveNow()));
  }

  Future<void> saveNow() async {
    final SessionRepository? repository = _repository;
    final OpenWorkspace? workspace = _ref.read(workspaceProvider);
    if (repository == null) {
      return;
    }
    if (workspace == null) {
      await repository.clearSession();
      return;
    }
    final TabsState tabs = _ref.read(tabsProvider);
    await repository.saveSession(
      SavedSession(
        roots: workspace.workspace.roots,
        workspaceName: workspace.workspace.name,
        activeTabIndex: tabs.activeIndex,
        tabs: <SavedTab>[
          for (final OpenTab tab in tabs.tabs)
            SavedTab(
              rootIndex: tab.rootIndex,
              fileId: tab.node.id,
              name: tab.node.name,
              editorState: tab.editorState,
              isPreview: tab.isPreview,
              wasDirty: tab.isDirty,
            ),
        ],
      ),
    );
  }

  /// Writes every unsaved buffer to app-private storage.
  ///
  /// Called when the app is paused. Runs regardless of the auto-save setting:
  /// a user who turned auto-save off still does not expect to lose work to the
  /// OS reclaiming memory.
  Future<void> backupUnsavedBuffers() async {
    final SessionRepository? repository = _repository;
    if (repository == null) {
      return;
    }
    for (final OpenTab tab in _ref.read(tabsProvider).tabs) {
      if (tab.isDirty) {
        await repository.writeBackup(tab.key, tab.text);
      } else {
        await repository.deleteBackup(tab.key);
      }
    }
    await saveNow();
  }

  /// Reopens the workspace, tabs, cursor positions and unsaved buffers from the
  /// last session. Returns false when there was nothing to restore.
  Future<bool> restore() async {
    final SessionRepository? repository = _repository;
    if (repository == null || !_ref.read(settingsProvider).restoreSession) {
      return false;
    }
    final SavedSession? session = await repository.loadSession();
    if (session == null || session.roots.isEmpty) {
      return false;
    }

    _restoring = true;
    try {
      // Only the `io` and `web-fsa` schemes can be reopened without a fresh
      // user gesture. A SAF root needs its permission re-checked, which is
      // handled when that provider lands; until then such a root is skipped
      // rather than silently failing later.
      final List<LiveRoot> roots = <LiveRoot>[];
      for (final WorkspaceRoot root in session.roots) {
        final FileSystemProvider? provider = await providerForRoot(root);
        if (provider == null || !await provider.exists(root.rootId)) {
          continue;
        }
        roots.add(LiveRoot(root: root, provider: provider));
      }
      if (roots.isEmpty) {
        await repository.clearSession();
        return false;
      }

      _ref.read(workspaceProvider.notifier).adoptRestored(
            Workspace(
              roots: roots.map((LiveRoot r) => r.root).toList(),
              name: session.workspaceName,
            ),
            roots,
          );

      final TabsController tabs = _ref.read(tabsProvider.notifier);
      for (final SavedTab saved in session.tabs) {
        final LiveRoot? root =
            saved.rootIndex < roots.length ? roots[saved.rootIndex] : null;
        if (root == null) {
          continue;
        }
        try {
          final FileSystemNode node = await root.provider.stat(saved.fileId);
          if (node is! FileNode) {
            continue;
          }
          await tabs.open(node, saved.rootIndex, preview: saved.isPreview);

          // Restore the unsaved buffer, so the tab comes back dirty with the
          // user's text rather than what is on disk.
          if (saved.wasDirty) {
            final String? backup = await repository.readBackup(
              '${saved.rootIndex}:${saved.fileId}',
            );
            if (backup != null) {
              tabs.restoreUnsavedBuffer(saved.rootIndex, saved.fileId, backup);
            }
          }
          tabs.restoreEditorState(saved.editorState);
        } on Object {
          // A file deleted since last run is simply not reopened.
          continue;
        }
      }
      if (session.activeTabIndex >= 0) {
        tabs.setActive(session.activeTabIndex);
      }
      return true;
    } finally {
      _restoring = false;
    }
  }

  /// Removes backups once they have been restored, so a later crash cannot
  /// resurrect stale text over newer edits.
  Future<void> purgeBackups() async => _repository?.purgeBackups();

  void dispose() => _debounce?.cancel();
}

final Provider<SessionController> sessionControllerProvider =
    Provider<SessionController>((Ref ref) {
  final SessionController controller = SessionController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});
