/// Move, copy, duplicate and delete, with conflict handling and undo.
///
/// One place for all of it on purpose: cut-and-paste, Duplicate and drag-and-drop
/// are the same operation reached three ways, and the conflict rules, the
/// copy-naming and the into-my-own-descendant guard must not drift between them.
///
/// Nothing here touches the widget tree. Anything that needs the user — the
/// Replace / Keep Both / Skip question — arrives as a [ConflictResolver]
/// callback, which is what lets the whole file be tested without pumping a UI.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/core/constants/app_info.dart';
import 'package:pocket_code/core/constants/durations.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/core/utils/relative_path.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/features/explorer/application/copy_naming.dart';
import 'package:pocket_code/features/explorer/application/tree_controller.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';
import 'package:pocket_code/services/clipboard/file_clipboard.dart';
import 'package:pocket_code/services/filesystem/cancellation.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';

/// What to do about one name that already exists in the destination.
enum ConflictChoice { replace, keepBoth, skip }

@immutable
class ConflictRequest {
  const ConflictRequest({
    required this.name,
    required this.isFolder,
    required this.offerApplyToAll,
  });

  final String name;
  final bool isFolder;

  /// True when more than one item in this operation collides, which is the only
  /// time "Apply to all" means anything.
  final bool offerApplyToAll;
}

@immutable
class ConflictDecision {
  const ConflictDecision(this.choice, {this.applyToAll = false});

  final ConflictChoice choice;
  final bool applyToAll;
}

/// Asks the user about one conflict. Returning null cancels the whole
/// operation, which is what dismissing the dialog means.
typedef ConflictResolver = Future<ConflictDecision?> Function(
  ConflictRequest request,
);

@immutable
class FileOpOutcome {
  const FileOpOutcome({
    this.changed = 0,
    this.skipped = 0,
    this.failure,
    this.cancelled = false,
  });

  const FileOpOutcome.failed(AppFailure this.failure)
      : changed = 0,
        skipped = 0,
        cancelled = false;

  /// Items actually moved or copied.
  final int changed;

  /// Items the user chose to skip, or that were already where they were asked
  /// to go.
  final int skipped;

  final AppFailure? failure;
  final bool cancelled;

  bool get ok => failure == null;
}

/// One deleted entry, parked in the trash and rememberable enough to put back.
@immutable
class TrashedEntry {
  const TrashedEntry({
    required this.rootIndex,
    required this.trashedId,
    required this.originalParentId,
    required this.name,
  });

  final int rootIndex;
  final String trashedId;
  final String originalParentId;
  final String name;
}

/// One delete, as a unit of undo.
@immutable
class TrashBatch {
  const TrashBatch({
    required this.rootIndex,
    required this.batchFolderId,
    required this.entries,
  });

  final int rootIndex;

  /// The `.trash/<stamp>` folder holding this batch, deleted on purge.
  final String batchFolderId;

  final List<TrashedEntry> entries;

  bool get isEmpty => entries.isEmpty;

  /// "3 items deleted" / "main.dart deleted".
  String get summary => entries.length == 1
      ? '${entries.single.name} deleted'
      : '${entries.length} items deleted';
}

class DeleteOutcome {
  const DeleteOutcome({required this.outcome, this.batch});

  final FileOpOutcome outcome;

  /// Null when nothing reached the trash, so there is nothing to undo.
  final TrashBatch? batch;
}

class FileOperations {
  FileOperations(this._ref);

  final Ref _ref;

  /// Purge timers, one per batch, so a second delete does not cancel the first
  /// one's undo window.
  final Map<String, Timer> _purgeTimers = <String, Timer>{};

  TreeController get _tree => _ref.read(treeProvider.notifier);

  LiveRoot? _rootAt(int index) => _ref.read(workspaceProvider)?.rootAt(index);

  // --- Guards --------------------------------------------------------------

  /// Whether [id] is [ancestor] or lives underneath it.
  ///
  /// Walks up with [FileSystemProvider.parentOf] rather than comparing strings,
  /// because ids are opaque: a SAF `content://` URI is not a path and string
  /// prefixes on it mean nothing.
  static bool isWithin(FileSystemProvider provider, String ancestor, String id) {
    String? current = id;
    final Set<String> seen = <String>{};
    while (current != null && current.isNotEmpty && seen.add(current)) {
      if (current == ancestor) {
        return true;
      }
      current = provider.parentOf(current);
    }
    return false;
  }

  /// The message shown whenever someone tries to put a folder inside itself.
  /// Shared by paste and drag-and-drop so the wording cannot drift.
  static const UnsupportedOperationFailure intoOwnDescendant =
      UnsupportedOperationFailure(
    what: 'A folder cannot be moved or copied into itself or into a folder '
        'inside it. Choose a destination outside that folder.',
  );

  // --- Move / copy ---------------------------------------------------------

  /// Moves or copies [items] into [targetFolderId].
  ///
  /// Same-folder copies auto-name (`main copy.dart`) with no question asked;
  /// same-folder moves are a no-op. A name taken in a *different* folder goes
  /// to [resolve].
  Future<FileOpOutcome> transfer({
    required List<ClipboardItem> items,
    required int targetRootIndex,
    required String targetFolderId,
    required bool move,
    required ConflictResolver resolve,
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    if (items.isEmpty) {
      return const FileOpOutcome();
    }
    final LiveRoot? target = _rootAt(targetRootIndex);
    if (target == null) {
      return const FileOpOutcome.failed(
        UnknownFailure(
          detail: 'That workspace folder is no longer open. Reopen it and try '
              'again.',
        ),
      );
    }
    final FileSystemProvider provider = target.provider;

    // Everything must come from the same storage: move() and copy() take ids
    // this provider issued, and there is no cross-provider transfer today.
    for (final ClipboardItem item in items) {
      if (_rootAt(item.rootIndex)?.provider != provider) {
        return const FileOpOutcome.failed(
          UnsupportedOperationFailure(
            what: 'Items can only be moved between folders in the same '
                'workspace root. Copy the file open in the editor instead.',
          ),
        );
      }
      if (item.isFolder && isWithin(provider, item.node.id, targetFolderId)) {
        return const FileOpOutcome.failed(intoOwnDescendant);
      }
    }

    final Set<String> taken;
    try {
      taken = (await provider.list(targetFolderId))
          .map((FileSystemNode n) => n.name)
          .toSet();
    } on AppFailure catch (failure) {
      return FileOpOutcome.failed(failure);
    }

    // Counted up front so the first dialog already knows whether offering
    // "Apply to all" is honest.
    final int conflicts = items
        .where((ClipboardItem item) =>
            provider.parentOf(item.node.id) != targetFolderId &&
            taken.contains(item.node.name))
        .length;

    final Set<String> sourceFolders = <String>{};
    ConflictDecision? applyToAll;
    int changed = 0;
    int skipped = 0;

    for (final ClipboardItem item in items) {
      if (token?.isCancelled ?? false) {
        return FileOpOutcome(changed: changed, skipped: skipped, cancelled: true);
      }
      final String sourceParent =
          provider.parentOf(item.node.id) ?? target.root.rootId;
      final bool sameFolder = sourceParent == targetFolderId;

      // Dropping something back where it already lives changes nothing, and
      // saying so with a dialog would be noise.
      if (sameFolder && move) {
        skipped++;
        continue;
      }

      String name = item.node.name;
      if (sameFolder) {
        name = CopyNaming.nextCopyName(name, taken);
      } else if (taken.contains(name)) {
        final ConflictDecision? decision = applyToAll ??
            await resolve(
              ConflictRequest(
                name: name,
                isFolder: item.isFolder,
                offerApplyToAll: conflicts > 1,
              ),
            );
        if (decision == null) {
          return FileOpOutcome(
            changed: changed,
            skipped: skipped,
            cancelled: true,
          );
        }
        if (decision.applyToAll) {
          applyToAll = decision;
        }
        switch (decision.choice) {
          case ConflictChoice.skip:
            skipped++;
            continue;
          case ConflictChoice.keepBoth:
            name = CopyNaming.nextCopyName(name, taken);
          case ConflictChoice.replace:
            // The thing being replaced goes to the trash rather than being
            // deleted, so "Replace" is survivable.
            final DeleteOutcome removal = await moveToTrash(<ClipboardItem>[
              ClipboardItem(
                rootIndex: targetRootIndex,
                node: FileNode(
                  id: provider.childId(targetFolderId, name),
                  name: name,
                  displayPath: provider.childId(targetFolderId, name),
                  parentId: targetFolderId,
                ),
              ),
            ]);
            if (!removal.outcome.ok) {
              return removal.outcome;
            }
            taken.remove(name);
        }
      }

      try {
        if (move) {
          await provider.move(
            item.node.id,
            targetFolderId,
            newName: name,
            onProgress: onProgress,
            token: token,
          );
        } else {
          await provider.copy(
            item.node.id,
            targetFolderId,
            newName: name,
            onProgress: onProgress,
            token: token,
          );
        }
      } on AppFailure catch (failure) {
        await _refreshAll(targetRootIndex, <String>{
          targetFolderId,
          ...sourceFolders,
        });
        if (failure is CancelledFailure) {
          return FileOpOutcome(
            changed: changed,
            skipped: skipped,
            cancelled: true,
          );
        }
        return FileOpOutcome.failed(failure);
      }

      taken.add(name);
      changed++;
      if (move) {
        sourceFolders.add(sourceParent);
      }
    }

    await _refreshAll(targetRootIndex, <String>{
      targetFolderId,
      ...sourceFolders,
    });
    return FileOpOutcome(changed: changed, skipped: skipped);
  }

  /// Copies each of [items] beside itself with a `copy` name.
  Future<FileOpOutcome> duplicate(
    List<ClipboardItem> items, {
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    int changed = 0;
    for (final ClipboardItem item in items) {
      final LiveRoot? root = _rootAt(item.rootIndex);
      if (root == null) {
        continue;
      }
      final String parent =
          root.provider.parentOf(item.node.id) ?? root.root.rootId;
      final FileOpOutcome outcome = await transfer(
        items: <ClipboardItem>[item],
        targetRootIndex: item.rootIndex,
        targetFolderId: parent,
        move: false,
        // Same-folder copies auto-name, so no conflict can reach the user here.
        resolve: (ConflictRequest _) async => null,
        onProgress: onProgress,
        token: token,
      );
      if (!outcome.ok || outcome.cancelled) {
        return outcome;
      }
      changed += outcome.changed;
    }
    return FileOpOutcome(changed: changed);
  }

  // --- Delete, trash and undo ----------------------------------------------

  /// Moves [items] into the workspace's `.trash` folder so the delete can be
  /// undone, and schedules the real delete for after the undo window.
  ///
  /// The trash lives at the workspace root rather than in app-private storage
  /// because a move only works within one provider: shipping a SAF folder to
  /// the app sandbox would be a recursive copy plus delete, which is slow and
  /// not atomic. The folder is filtered out of the tree so it never reads as
  /// user content.
  Future<DeleteOutcome> moveToTrash(
    List<ClipboardItem> items, {
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    if (items.isEmpty) {
      return const DeleteOutcome(outcome: FileOpOutcome());
    }
    final int rootIndex = items.first.rootIndex;
    final LiveRoot? root = _rootAt(rootIndex);
    if (root == null) {
      return const DeleteOutcome(
        outcome: FileOpOutcome.failed(
          UnknownFailure(
            detail: 'That workspace folder is no longer open. Reopen it and '
                'try again.',
          ),
        ),
      );
    }
    final FileSystemProvider provider = root.provider;

    final List<TrashedEntry> entries = <TrashedEntry>[];
    final Set<String> parents = <String>{};
    String? batchFolderId;
    try {
      batchFolderId = await _createBatchFolder(provider, root.root.rootId);
      for (int i = 0; i < items.length; i++) {
        token?.throwIfCancelled();
        final ClipboardItem item = items[i];
        final String parent =
            provider.parentOf(item.node.id) ?? root.root.rootId;
        // Each item gets its own numbered slot: two files called `main.dart`
        // from different folders would otherwise collide inside the batch.
        final FolderNode slot =
            await provider.createFolder(batchFolderId, '$i');
        final FileSystemNode moved = await provider.move(
          item.node.id,
          slot.id,
          onProgress: onProgress,
          token: token,
        );
        entries.add(
          TrashedEntry(
            rootIndex: rootIndex,
            trashedId: moved.id,
            originalParentId: parent,
            name: item.node.name,
          ),
        );
        parents.add(parent);
      }
    } on AppFailure catch (failure) {
      await _refreshAll(rootIndex, parents);
      return DeleteOutcome(
        outcome: failure is CancelledFailure
            ? FileOpOutcome(changed: entries.length, cancelled: true)
            : FileOpOutcome.failed(failure),
        batch: entries.isEmpty || batchFolderId == null
            ? null
            : TrashBatch(
                rootIndex: rootIndex,
                batchFolderId: batchFolderId,
                entries: entries,
              ),
      );
    }

    await _refreshAll(rootIndex, parents);
    final TrashBatch batch = TrashBatch(
      rootIndex: rootIndex,
      batchFolderId: batchFolderId,
      entries: entries,
    );
    schedulePurge(batch);
    return DeleteOutcome(
      outcome: FileOpOutcome(changed: entries.length),
      batch: batch,
    );
  }

  /// Puts a trashed batch back where it came from.
  Future<FileOpOutcome> restore(TrashBatch batch) async {
    _purgeTimers.remove(batch.batchFolderId)?.cancel();
    final LiveRoot? root = _rootAt(batch.rootIndex);
    if (root == null) {
      return const FileOpOutcome.failed(
        UnknownFailure(
          detail: 'That workspace folder is no longer open, so the deleted '
              'items cannot be put back.',
        ),
      );
    }
    final Set<String> parents = <String>{};
    int restored = 0;
    AppFailure? failure;
    for (final TrashedEntry entry in batch.entries) {
      try {
        await root.provider.move(
          entry.trashedId,
          entry.originalParentId,
          newName: entry.name,
        );
        parents.add(entry.originalParentId);
        restored++;
      } on AppFailure catch (error) {
        // Keep going: one item whose folder vanished must not strand the rest
        // in the trash.
        failure = error;
      }
    }
    await _purgeFolder(root.provider, batch.batchFolderId);
    await _refreshAll(batch.rootIndex, parents);
    return failure == null
        ? FileOpOutcome(changed: restored)
        : FileOpOutcome.failed(failure);
  }

  /// Deletes a batch for real once the undo window closes.
  void schedulePurge(TrashBatch batch) {
    _purgeTimers[batch.batchFolderId]?.cancel();
    _purgeTimers[batch.batchFolderId] = Timer(AppDurations.undoWindow, () {
      _purgeTimers.remove(batch.batchFolderId);
      final LiveRoot? root = _rootAt(batch.rootIndex);
      if (root != null) {
        unawaited(_purgeFolder(root.provider, batch.batchFolderId));
      }
    });
  }

  /// Drops every pending purge timer. Called when the provider is torn down.
  void dispose() {
    for (final Timer timer in _purgeTimers.values) {
      timer.cancel();
    }
    _purgeTimers.clear();
  }

  Future<void> _purgeFolder(FileSystemProvider provider, String id) async {
    try {
      await provider.delete(id);
    } on AppFailure {
      // A purge is housekeeping. If it fails the items stay in a hidden folder
      // the user never sees; telling them about it would be noise.
    }
  }

  Future<String> _createBatchFolder(
    FileSystemProvider provider,
    String rootId,
  ) async {
    final String trashId = provider.childId(rootId, AppInfo.trashFolderName);
    if (!await provider.exists(trashId)) {
      await provider.createFolder(rootId, AppInfo.trashFolderName);
    }
    // Microseconds, because two deletes in the same millisecond are entirely
    // possible from a multi-select.
    final String stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final FolderNode folder = await provider.createFolder(trashId, stamp);
    return folder.id;
  }

  // --- Paths ---------------------------------------------------------------

  /// Path of [node] relative to its workspace root, with forward slashes.
  ///
  /// Built by walking parents rather than by string surgery, so it is correct
  /// for providers whose ids are URIs. Falls back to the display path if the
  /// walk never reaches the root.
  String relativePath(int rootIndex, FileSystemNode node) {
    final LiveRoot? root = _rootAt(rootIndex);
    if (root == null) {
      return node.name;
    }
    return relativePathIn(
      root.provider,
      root.root.rootId,
      node.id,
      fallback: node.displayPath,
    );
  }

  Future<void> _refreshAll(int rootIndex, Set<String> folderIds) async {
    for (final String id in folderIds) {
      await _tree.refreshFolder(rootIndex, id);
    }
  }
}

final Provider<FileOperations> fileOperationsProvider =
    Provider<FileOperations>((Ref ref) {
  final FileOperations operations = FileOperations(ref);
  ref.onDispose(operations.dispose);
  return operations;
});
