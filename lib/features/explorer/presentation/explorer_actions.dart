/// Dispatches explorer context-menu actions.
///
/// Held apart from the panel widget so the panel stays about layout and this
/// stays about behaviour. Everything here needs a [BuildContext] (dialogs,
/// snackbars) and a [WidgetRef], so it takes both rather than trying to be a
/// pure controller.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/core/constants/durations.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/features/explorer/application/file_details.dart';
import 'package:pocket_code/features/explorer/application/file_operations.dart';
import 'package:pocket_code/features/explorer/application/tree_controller.dart';
import 'package:pocket_code/features/explorer/application/tree_state.dart';
import 'package:pocket_code/features/explorer/presentation/conflict_dialog.dart';
import 'package:pocket_code/features/explorer/presentation/delete_dialog.dart';
import 'package:pocket_code/features/explorer/presentation/progress_dialog.dart';
import 'package:pocket_code/features/explorer/presentation/properties_dialog.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';
import 'package:pocket_code/services/archive/zip_service.dart';
import 'package:pocket_code/services/clipboard/file_clipboard.dart';
import 'package:pocket_code/services/filesystem/cancellation.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/share/share_factory.dart';

class ExplorerActions {
  const ExplorerActions({required this.ref, required this.context});

  final WidgetRef ref;
  final BuildContext context;

  FileOperations get _ops => ref.read(fileOperationsProvider);

  TreeController get _tree => ref.read(treeProvider.notifier);

  // --- Clipboard ------------------------------------------------------------

  void cut(List<ClipboardItem> items) {
    ref.read(fileClipboardProvider.notifier).cut(items);
    _toast('${_count(items.length)} ready to move');
  }

  void copy(List<ClipboardItem> items) {
    ref.read(fileClipboardProvider.notifier).copy(items);
    _toast('${_count(items.length)} ready to paste');
  }

  /// Pastes the clipboard into [targetFolderId].
  ///
  /// A cut is a move, and the clipboard is cleared afterwards so the same items
  /// cannot be "moved" twice from a stale clipboard.
  Future<void> paste(int rootIndex, String targetFolderId) async {
    final FileClipboard clipboard = ref.read(fileClipboardProvider);
    if (clipboard.isEmpty) {
      return;
    }
    final bool move = clipboard.isCut;
    final FileOpOutcome? outcome = await runWithProgress<FileOpOutcome>(
      context,
      title: move ? 'Moving' : 'Copying',
      action: (ProgressCallback onProgress, CancellationToken token) =>
          _ops.transfer(
        items: clipboard.items,
        targetRootIndex: rootIndex,
        targetFolderId: targetFolderId,
        move: move,
        resolve: _resolveConflict,
        onProgress: onProgress,
        token: token,
      ),
    );
    if (move && (outcome?.ok ?? false)) {
      ref.read(fileClipboardProvider.notifier).clear();
    }
    await _finish(outcome, rootIndex, targetFolderId);
  }

  Future<void> duplicate(List<ClipboardItem> items) async {
    if (items.isEmpty) {
      return;
    }
    final FileOpOutcome? outcome = await runWithProgress<FileOpOutcome>(
      context,
      title: 'Duplicating',
      action: (ProgressCallback onProgress, CancellationToken token) =>
          _ops.duplicate(items, onProgress: onProgress, token: token),
    );
    final ClipboardItem first = items.first;
    await _finish(
      outcome,
      first.rootIndex,
      _parentOf(first) ?? '',
    );
  }

  // --- Delete and undo ------------------------------------------------------

  /// Confirms, moves the items to the app trash, then offers Undo.
  ///
  /// The trash is what makes undo possible: a real delete could not be taken
  /// back. It is purged after the undo window closes.
  Future<void> delete(List<ClipboardItem> items, {required bool confirm}) async {
    if (items.isEmpty) {
      return;
    }
    if (confirm) {
      final bool go = await confirmDelete(
        context,
        headline: items.length == 1
            ? 'Delete "${items.first.node.name}"?'
            : 'Delete ${items.length} items?',
        details: _deleteDetails(items),
      );
      if (!go || !context.mounted) {
        return;
      }
    }

    final DeleteOutcome? result = await runWithProgress<DeleteOutcome>(
      context,
      title: 'Deleting',
      action: (ProgressCallback onProgress, CancellationToken token) =>
          _ops.moveToTrash(items, onProgress: onProgress, token: token),
    );
    if (result == null) {
      return;
    }

    final ClipboardItem first = items.first;
    await _finish(result.outcome, first.rootIndex, _parentOf(first) ?? '');

    final TrashBatch? batch = result.batch;
    if (batch == null || !context.mounted) {
      return;
    }
    // The purge is scheduled either way; Undo cancels it by restoring first.
    _ops.schedulePurge(batch);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: AppDurations.undoWindow,
        content: Text(
          items.length == 1
              ? 'Deleted "${items.first.node.name}"'
              : 'Deleted ${items.length} items',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            final FileOpOutcome restored = await _ops.restore(batch);
            await _finish(restored, first.rootIndex, _parentOf(first) ?? '');
          },
        ),
      ),
    );
  }

  /// Counts what a folder delete will actually destroy, off the UI isolate.
  Future<String?> _deleteDetails(List<ClipboardItem> items) async {
    if (items.length != 1 || items.first.node is! FolderNode) {
      return null;
    }
    final ClipboardItem item = items.first;
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(item.rootIndex);
    if (root == null) {
      return null;
    }
    try {
      final FolderStats stats = await root.provider.folderStats(item.node.id);
      if (stats.fileCount == 0 && stats.folderCount == 0) {
        return 'This folder is empty.';
      }
      return 'This folder contains ${_plural(stats.fileCount, 'file')}'
          '${stats.folderCount > 0 ? ' in ${_plural(stats.folderCount, 'subfolder')}' : ''}.';
    } on AppFailure {
      return null;
    }
  }

  // --- Paths ----------------------------------------------------------------

  // --- Share, Open with, ZIP ------------------------------------------------

  /// Shares a file's contents through the platform share sheet.
  ///
  /// Reads the bytes rather than passing a path: a SAF document and a browser
  /// handle have no path, and this must work for all three providers.
  Future<void> share(ClipboardItem item) async {
    await _withBytes(item, (Uint8List bytes) async {
      await createShareService()
          .shareFile(name: item.node.name, bytes: bytes);
    });
  }

  /// Hands the file to another app.
  Future<void> openWith(ClipboardItem item) async {
    await _withBytes(item, (Uint8List bytes) async {
      final bool opened = await createShareService()
          .openWith(name: item.node.name, bytes: bytes);
      if (!opened) {
        _toast('No app on this device opens ${item.node.name}');
      }
    });
  }

  Future<void> _withBytes(
    ClipboardItem item,
    Future<void> Function(Uint8List) action,
  ) async {
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(item.rootIndex);
    if (root == null) {
      return;
    }
    try {
      await action(await root.provider.readBytes(item.node.id));
    } on AppFailure catch (failure) {
      _toast('${failure.message}. ${failure.hint}');
    }
  }

  /// Zips a folder and offers it through the share sheet.
  ///
  /// Sharing rather than writing it back into the workspace: an archive of a
  /// folder, dropped inside that folder, is the kind of thing that ends up in
  /// the next archive.
  Future<void> exportZip(ClipboardItem item) async {
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(item.rootIndex);
    if (root == null) {
      return;
    }
    _toast('Zipping ${item.node.name}…');
    try {
      final Uint8List bytes = await const ZipService()
          .export(provider: root.provider, folderId: item.node.id);
      await createShareService()
          .shareFile(name: '${item.node.name}.zip', bytes: bytes);
    } on AppFailure catch (failure) {
      _toast('${failure.message}. ${failure.hint}');
    }
  }

  /// Picks a `.zip` and extracts it into [item].
  Future<void> importZip(ClipboardItem item) async {
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(item.rootIndex);
    if (root == null) {
      return;
    }
    // `pickFile` + `readAsBytes` rather than the `withData` parameter, which
    // v12 deprecates.
    final PlatformFile? picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['zip'],
      dialogTitle: 'Choose a ZIP to extract',
    );
    if (picked == null) {
      return;
    }
    final Uint8List bytes = await picked.readAsBytes();

    try {
      final int written = await const ZipService().import(
        provider: root.provider,
        folderId: item.node.id,
        bytes: bytes,
      );
      await _tree.refreshFolder(item.rootIndex, item.node.id);
      _toast(written == 1 ? 'Extracted 1 file' : 'Extracted $written files');
    } on AlreadyExistsFailure catch (failure) {
      // Overwriting is not undoable, so it is asked for rather than assumed.
      if (!context.mounted) {
        return;
      }
      final bool replace = await _confirmOverwrite(failure.path ?? 'a file');
      if (!replace) {
        return;
      }
      final int written = await const ZipService().import(
        provider: root.provider,
        folderId: item.node.id,
        bytes: bytes,
        overwrite: true,
      );
      await _tree.refreshFolder(item.rootIndex, item.node.id);
      _toast('Extracted $written files, replacing existing ones');
    } on AppFailure catch (failure) {
      _toast('${failure.message}. ${failure.hint}');
    }
  }

  Future<bool> _confirmOverwrite(String example) async {
    if (!context.mounted) {
      return false;
    }
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Replace existing files?'),
            content: Text(
              'This archive contains "$example", which already exists here.\n\n'
              'Replacing cannot be undone.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Replace'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> copyPath(ClipboardItem item) async {
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(item.rootIndex);
    if (root == null) {
      return;
    }
    // For providers that cannot resolve a real path (SAF, the browser) the
    // display path is the URI, which is still the most useful thing to hand
    // over — Properties shows both.
    await Clipboard.setData(ClipboardData(text: item.node.displayPath));
    _toast('Path copied');
  }

  Future<void> copyRelativePath(ClipboardItem item) async {
    await Clipboard.setData(
      ClipboardData(text: _ops.relativePath(item.rootIndex, item.node)),
    );
    _toast('Relative path copied');
  }

  // --- Properties -----------------------------------------------------------

  Future<void> showProperties(ClipboardItem item) async {
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(item.rootIndex);
    if (root == null) {
      return;
    }
    await showPropertiesDialog(
      context,
      title: item.node is FolderNode ? 'Folder details' : 'Properties',
      metadata: describeNode(provider: root.provider, node: item.node),
    );
  }

  // --- internals ------------------------------------------------------------

  Future<ConflictDecision?> _resolveConflict(ConflictRequest request) {
    if (!context.mounted) {
      return Future<ConflictDecision?>.value();
    }
    return showConflictDialog(context, request);
  }

  /// Refreshes the affected folder and reports anything the user should know.
  Future<void> _finish(
    FileOpOutcome? outcome,
    int rootIndex,
    String folderId,
  ) async {
    await _tree.refreshFolder(rootIndex, folderId);
    if (outcome == null || !context.mounted) {
      return;
    }
    if (outcome.cancelled) {
      _toast('Cancelled. Some items may already have been changed.');
      return;
    }
    final AppFailure? failure = outcome.failure;
    if (failure != null) {
      _toast('${failure.message}. ${failure.hint}');
    }
  }

  String? _parentOf(ClipboardItem item) {
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(item.rootIndex);
    return root?.provider.parentOf(item.node.id) ?? root?.root.rootId;
  }

  void _toast(String message) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String _count(int n) => _plural(n, 'item');

  static String _plural(int n, String noun) =>
      n == 1 ? '1 $noun' : '$n ${noun}s';
}

/// Wraps a [TreeRow] as a clipboard item.
ClipboardItem itemOf(TreeRow row) =>
    ClipboardItem(node: row.node, rootIndex: row.rootIndex);
