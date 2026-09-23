/// Remembers which workspaces and files were opened recently.
///
/// Availability is **not** checked on write. A folder can disappear between
/// sessions — a removed SD card, a revoked SAF grant — and checking every time
/// would mean touching storage constantly for information only ever read when
/// the list is shown. `RecentWorkspace`'s own doc comment sets that rule;
/// [checkAvailability] is what the welcome screen calls.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/data/models/workspace.dart';
import 'package:pocket_code/data/repositories/recents_repository.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';

/// Puts [entry] at the front of [current], dropping any older entry with the
/// same key and trimming to [max].
///
/// Pure, and the whole of the list's behaviour: reopening something already in
/// the list must move it rather than duplicate it.
List<T> promote<T>(
  List<T> current,
  T entry,
  String Function(T) keyOf,
  int max,
) {
  final String key = keyOf(entry);
  return <T>[
    entry,
    ...current.where((T other) => keyOf(other) != key),
  ].take(max).toList();
}

/// Identity of a recent file across providers.
String recentFileKey(RecentFile file) =>
    '${file.providerScheme}|${file.fileId}';

class RecentsController extends Notifier<RecentItems> {
  @override
  RecentItems build() => ref.read(initialRecentsProvider);

  Future<void> _persist(RecentItems next) async {
    state = next;
    await ref.read(recentsRepositoryProvider)?.save(next);
  }

  /// Records a workspace as just opened.
  Future<void> recordWorkspace(Workspace workspace) {
    final RecentWorkspace entry = RecentWorkspace(
      name: workspace.displayName,
      roots: workspace.roots,
      lastOpened: DateTime.now(),
      filePath: workspace.filePath,
    );
    return _persist(
      state.copyWith(
        workspaces: promote(
          state.workspaces,
          entry,
          (RecentWorkspace w) => w.key,
          AppLimits.maxRecentWorkspaces,
        ),
      ),
    );
  }

  /// Records a file as just opened.
  Future<void> recordFile({
    required String providerScheme,
    required String fileId,
    required String name,
    String? displayPath,
  }) {
    final RecentFile entry = RecentFile(
      providerScheme: providerScheme,
      fileId: fileId,
      name: name,
      lastOpened: DateTime.now(),
      displayPath: displayPath,
    );
    return _persist(
      state.copyWith(
        files: promote(
          state.files,
          entry,
          recentFileKey,
          AppLimits.maxRecentFiles,
        ),
      ),
    );
  }

  Future<void> removeWorkspace(String key) => _persist(
        state.copyWith(
          workspaces: state.workspaces
              .where((RecentWorkspace w) => w.key != key)
              .toList(),
        ),
      );

  Future<void> clear() => _persist(const RecentItems());

  /// Marks entries whose folder can no longer be reached.
  ///
  /// Called when the list is shown, so a missing folder appears as unavailable
  /// with Remove rather than failing when it is tapped.
  Future<void> checkAvailability(
    Future<FileSystemProvider?> Function(WorkspaceRoot) resolve,
  ) async {
    final List<RecentWorkspace> checked = <RecentWorkspace>[];
    for (final RecentWorkspace workspace in state.workspaces) {
      bool available = workspace.roots.isNotEmpty;
      for (final WorkspaceRoot root in workspace.roots) {
        final FileSystemProvider? provider = await resolve(root);
        if (provider == null || !await provider.exists(root.rootId)) {
          available = false;
          break;
        }
      }
      checked.add(workspace.copyWith(available: available));
    }
    // Not persisted: availability describes this moment, and writing it would
    // leave a folder that came back still looking missing next launch.
    state = state.copyWith(workspaces: checked);
  }
}

final NotifierProvider<RecentsController, RecentItems> recentsProvider =
    NotifierProvider<RecentsController, RecentItems>(RecentsController.new);
