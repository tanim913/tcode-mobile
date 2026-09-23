/// [FileSystemProvider] backed by `dart:io`.
///
/// Used for the app's own Projects folder on Android (which always works, with
/// no permissions), for the Android `full` flavour's All-files-access mode, and
/// as the target of the unit tests — which is why this implementation gets the
/// most test coverage of the three.
///
/// Ids are absolute paths.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/text_format.dart';
import 'package:pocket_code/services/filesystem/cancellation.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/filesystem/io/io_bulk_worker.dart';
import 'package:pocket_code/services/filesystem/text_codec.dart';

class IoFileSystemProvider implements FileSystemProvider {
  const IoFileSystemProvider();

  @override
  String get schemeId => 'io';

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        canWatch: true,
        canResolveAbsolutePath: true,
        supportsAtomicWrite: true,
        canMoveAcrossFolders: true,
      );

  // --- Reading -------------------------------------------------------------

  @override
  Future<List<FileSystemNode>> list(String folderId) async {
    return _guard(folderId, () async {
      final Directory dir = Directory(folderId);
      if (!dir.existsSync()) {
        throw NotFoundFailure(path: folderId);
      }
      final List<FileSystemNode> nodes = <FileSystemNode>[];
      await for (final FileSystemEntity entity in dir.list(followLinks: false)) {
        final FileSystemNode? node = await _toNode(entity);
        if (node != null) {
          nodes.add(node);
        }
      }
      return nodes;
    });
  }

  @override
  Future<FileSystemNode> stat(String id) async {
    return _guard(id, () async {
      final FileSystemEntityType type = await FileSystemEntity.type(id);
      switch (type) {
        case FileSystemEntityType.directory:
          return _folderNode(Directory(id), await Directory(id).stat());
        case FileSystemEntityType.file:
          return _fileNode(File(id), await File(id).stat());
        case FileSystemEntityType.notFound:
          throw NotFoundFailure(path: id);
        default:
          // A link or socket. Report it as a file so it can at least be seen.
          return _fileNode(File(id), await File(id).stat());
      }
    });
  }

  @override
  Future<bool> exists(String id) async {
    final FileSystemEntityType type = await FileSystemEntity.type(id);
    return type != FileSystemEntityType.notFound;
  }

  @override
  Future<Uint8List> readBytes(String id) {
    return _guard(id, () => File(id).readAsBytes());
  }

  @override
  Future<TextFileContents> readText(String id, {TextEncoding? encoding}) async {
    final Uint8List bytes = await readBytes(id);
    return TextCodec.decode(bytes, forced: encoding);
  }

  // --- Writing -------------------------------------------------------------

  @override
  Future<void> writeBytes(String id, Uint8List bytes) {
    return _guard(id, () => _atomicWrite(id, bytes));
  }

  @override
  Future<void> writeText(String id, String text, TextFormat format) {
    return writeBytes(id, TextCodec.encodeText(text, format));
  }

  /// Writes to a temporary file beside the target, then renames over it.
  ///
  /// Rename is atomic within a filesystem, so a crash or a battery death mid-
  /// write leaves the original file intact rather than truncated. The temp file
  /// must live in the same directory for that guarantee to hold — /tmp is
  /// usually a different mount.
  Future<void> _atomicWrite(String id, Uint8List bytes) async {
    final String dir = p.dirname(id);
    final String temp = p.join(
      dir,
      '.${p.basename(id)}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final File tempFile = File(temp);
    try {
      await tempFile.writeAsBytes(bytes, flush: true);
      await tempFile.rename(id);
    } on FileSystemException {
      // Clean up the temp file so a failed save does not litter the folder.
      if (tempFile.existsSync()) {
        try {
          await tempFile.delete();
        } on FileSystemException {
          // Nothing further to do; the original error is what matters.
        }
      }
      rethrow;
    }
  }

  // --- Structure -----------------------------------------------------------

  @override
  Future<FileNode> createFile(String parentId, String name) async {
    final String path = childId(parentId, name);
    return _guard(path, () async {
      final File file = File(path);
      if (file.existsSync() || Directory(path).existsSync()) {
        throw AlreadyExistsFailure(path: path);
      }
      await file.create(recursive: true);
      return _fileNode(file, await file.stat());
    });
  }

  @override
  Future<FolderNode> createFolder(String parentId, String name) async {
    final String path = childId(parentId, name);
    return _guard(path, () async {
      final Directory dir = Directory(path);
      if (dir.existsSync() || File(path).existsSync()) {
        throw AlreadyExistsFailure(path: path);
      }
      await dir.create(recursive: true);
      return _folderNode(dir, await dir.stat());
    });
  }

  @override
  Future<FileSystemNode> rename(String id, String newName) async {
    final String target = childId(p.dirname(id), newName);
    return _guard(id, () async {
      if (target == id) {
        return stat(id);
      }
      if (await exists(target)) {
        throw AlreadyExistsFailure(path: target);
      }
      final FileSystemEntityType type = await FileSystemEntity.type(id);
      if (type == FileSystemEntityType.directory) {
        await Directory(id).rename(target);
      } else {
        await File(id).rename(target);
      }
      return stat(target);
    });
  }

  @override
  Future<FileSystemNode> move(
    String id,
    String newParentId, {
    String? newName,
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    final String target = childId(newParentId, newName ?? p.basename(id));
    _assertNotIntoOwnDescendant(id, newParentId);

    return _guard(id, () async {
      if (await exists(target)) {
        throw AlreadyExistsFailure(path: target);
      }
      final FileSystemEntityType type = await FileSystemEntity.type(id);
      try {
        // Same-filesystem move is a rename: instant, no copying.
        if (type == FileSystemEntityType.directory) {
          await Directory(id).rename(target);
        } else {
          await File(id).rename(target);
        }
      } on FileSystemException {
        // Across filesystems rename fails, so fall back to copy-then-delete.
        await _runBulk(BulkOp.copy, id, onProgress, token, destination: target);
        await _runBulk(BulkOp.delete, id, null, token);
      }
      return stat(target);
    });
  }

  @override
  Future<FileSystemNode> copy(
    String id,
    String newParentId, {
    String? newName,
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    final String target = childId(newParentId, newName ?? p.basename(id));
    _assertNotIntoOwnDescendant(id, newParentId);
    if (await exists(target)) {
      throw AlreadyExistsFailure(path: target);
    }
    await _runBulk(BulkOp.copy, id, onProgress, token, destination: target);
    return stat(target);
  }

  @override
  Future<void> delete(
    String id, {
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    await _runBulk(BulkOp.delete, id, onProgress, token);
  }

  @override
  Future<FolderStats> folderStats(
    String id, {
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    final BulkDone done =
        await _runBulk(BulkOp.stats, id, onProgress, token);
    return FolderStats(
      fileCount: done.fileCount,
      folderCount: done.folderCount,
      totalBytes: done.totalBytes,
    );
  }

  // --- Watching ------------------------------------------------------------

  @override
  Stream<FileChangeEvent> watch(String folderId) {
    late StreamController<FileChangeEvent> controller;
    StreamSubscription<FileSystemEvent>? sub;

    controller = StreamController<FileChangeEvent>(
      onListen: () {
        try {
          sub = Directory(folderId).watch().listen(
            (FileSystemEvent event) => controller.add(_toChange(event)),
            // Watchers die when the folder is deleted. That is not a crash.
            onError: (Object _) => controller.close(),
          );
        } on FileSystemException {
          // Platform or filesystem does not support watching. Close quietly;
          // the explorer still refreshes on resume and pull-to-refresh.
          controller.close();
        }
      },
      onCancel: () async => sub?.cancel(),
    );
    return controller.stream;
  }

  FileChangeEvent _toChange(FileSystemEvent event) {
    return switch (event.type) {
      FileSystemEvent.create =>
        FileChangeEvent(kind: FileChangeKind.created, id: event.path),
      FileSystemEvent.delete =>
        FileChangeEvent(kind: FileChangeKind.deleted, id: event.path),
      FileSystemEvent.move => FileChangeEvent(
          kind: FileChangeKind.moved,
          id: event.path,
          newId: event is FileSystemMoveEvent ? event.destination : null,
        ),
      _ => FileChangeEvent(kind: FileChangeKind.modified, id: event.path),
    };
  }

  // --- Identity ------------------------------------------------------------

  @override
  String childId(String parentId, String name) => p.join(parentId, name);

  @override
  String? parentOf(String id) {
    final String parent = p.dirname(id);
    return parent == id ? null : parent;
  }

  @override
  String nameOf(String id) => p.basename(id);

  // --- internals -----------------------------------------------------------

  /// Blocks the one move that corrupts a tree: dragging a folder into itself.
  void _assertNotIntoOwnDescendant(String sourceId, String destinationParentId) {
    final String source = p.normalize(sourceId);
    final String dest = p.normalize(destinationParentId);
    if (dest == source || p.isWithin(source, dest)) {
      throw const UnsupportedOperationFailure(
        what: 'A folder cannot be moved or copied into itself.',
      );
    }
  }

  Future<FileSystemNode?> _toNode(FileSystemEntity entity) async {
    try {
      final FileStat stat = await entity.stat();
      if (stat.type == FileSystemEntityType.directory) {
        return _folderNode(entity, stat);
      }
      return _fileNode(entity, stat);
    } on FileSystemException {
      // The entry vanished between listing and stat-ing. Skip it rather than
      // failing the whole directory listing.
      return null;
    }
  }

  FileNode _fileNode(FileSystemEntity entity, FileStat stat) {
    final String path = entity.path;
    return FileNode(
      id: path,
      name: p.basename(path),
      displayPath: path,
      parentId: parentOf(path),
      modified: stat.modified,
      size: stat.size,
    );
  }

  FolderNode _folderNode(FileSystemEntity entity, FileStat stat) {
    final String path = entity.path;
    return FolderNode(
      id: path,
      name: p.basename(path),
      displayPath: path,
      parentId: parentOf(path),
      modified: stat.modified,
    );
  }

  /// Runs one recursive job on a background isolate, forwarding progress and
  /// wiring the cancellation token to the worker's control port.
  Future<BulkDone> _runBulk(
    BulkOp op,
    String source,
    ProgressCallback? onProgress,
    CancellationToken? token, {
    String? destination,
  }) async {
    // Cancelling before the work starts must not spawn an isolate at all.
    if (token?.isCancelled ?? false) {
      throw CancelledFailure(path: source);
    }

    final ReceivePort reply = ReceivePort();
    final Completer<BulkDone> completer = Completer<BulkDone>();
    SendPort? control;
    Timer? cancelPoll;

    final Isolate isolate = await Isolate.spawn(
      bulkWorkerMain,
      BulkRequest(
        op: op,
        sourcePath: source,
        destinationPath: destination,
        replyPort: reply.sendPort,
      ),
      onError: reply.sendPort,
      onExit: reply.sendPort,
    );

    reply.listen((Object? message) {
      switch (message) {
        case final SendPort port:
          control = port;
          if (token != null) {
            // Relay at once if cancellation already happened while the isolate
            // was starting, so a fast job cannot outrun the first poll tick.
            if (token.isCancelled) {
              port.send(kCancelMessage);
            } else {
              // The token is a plain flag on this isolate, so it otherwise has
              // to be polled and relayed. 100ms is imperceptible for a button.
              cancelPoll =
                  Timer.periodic(const Duration(milliseconds: 100), (Timer t) {
                if (token.isCancelled) {
                  control?.send(kCancelMessage);
                  t.cancel();
                }
              });
            }
          }
        case final BulkProgress progress:
          onProgress?.call(
            FileOperationProgress(
              completed: progress.completed,
              total: progress.total,
              currentPath: progress.currentPath,
            ),
          );
        case final BulkDone done:
          if (!completer.isCompleted) {
            completer.complete(done);
          }
        case final BulkError error:
          if (!completer.isCompleted) {
            completer.completeError(_failureFor(error));
          }
        case null:
          // onExit fires with null. If nothing completed us, the worker died.
          if (!completer.isCompleted) {
            completer.completeError(
              UnknownFailure(
                detail: 'The operation stopped unexpectedly.',
                path: source,
              ),
            );
          }
      }
    });

    try {
      return await completer.future;
    } finally {
      cancelPoll?.cancel();
      reply.close();
      isolate.kill(priority: Isolate.immediate);
    }
  }

  AppFailure _failureFor(BulkError error) {
    return switch (error.kind) {
      'permission' => PermissionDeniedFailure(path: error.path),
      'notFound' => NotFoundFailure(path: error.path),
      'exists' => AlreadyExistsFailure(path: error.path),
      'full' => StorageFullFailure(path: error.path),
      'tooLong' => PathTooLongFailure(path: error.path),
      'cancelled' => CancelledFailure(path: error.path),
      _ => UnknownFailure(detail: error.message, path: error.path),
    };
  }

  /// Runs [body], converting OS errors into typed failures.
  ///
  /// Rule 6 of the brief: a file system error must never crash the app. Every
  /// path into `dart:io` goes through here.
  Future<T> _guard<T>(String path, Future<T> Function() body) async {
    try {
      return await body();
    } on AppFailure {
      rethrow;
    } on FileSystemException catch (e) {
      final int? code = e.osError?.errorCode;
      throw switch (code) {
        1 || 13 || 5 => PermissionDeniedFailure(path: path, cause: e),
        2 => NotFoundFailure(path: path, cause: e),
        17 => AlreadyExistsFailure(path: path, cause: e),
        28 => StorageFullFailure(path: path, cause: e),
        36 => PathTooLongFailure(path: path, cause: e),
        _ => UnknownFailure(detail: e.message, path: path, cause: e),
      };
    } on Object catch (e) {
      throw UnknownFailure(detail: e.toString(), path: path, cause: e);
    }
  }
}
