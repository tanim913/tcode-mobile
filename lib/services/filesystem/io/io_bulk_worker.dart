/// Recursive file operations, executed on a background isolate.
///
/// The brief forbids running recursive copy, delete, or size counting on the UI
/// isolate — a 10,000-file tree would freeze the app for seconds. Isolates do
/// not share memory, so progress comes back over a [SendPort] and cancellation
/// goes out over one.
///
/// The loops `await` every [_yieldEvery] entries. That is not a delay: it hands
/// control back to the isolate's event loop just long enough for a pending
/// cancel message to be delivered, which is the only way to interrupt otherwise
/// synchronous file work.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// How many entries to process between cancellation checks. Small enough that
/// Cancel feels immediate, large enough that yielding is not the bottleneck.
const int _yieldEvery = 32;

enum BulkOp { copy, delete, stats }

/// Sent to the worker to start a job.
class BulkRequest {
  const BulkRequest({
    required this.op,
    required this.sourcePath,
    required this.replyPort,
    this.destinationPath,
  });

  final BulkOp op;
  final String sourcePath;
  final String? destinationPath;
  final SendPort replyPort;
}

/// Progress update from the worker.
class BulkProgress {
  const BulkProgress(this.completed, this.total, this.currentPath);

  final int completed;
  final int total;
  final String currentPath;
}

/// Terminal message: the job finished.
class BulkDone {
  const BulkDone({
    this.fileCount = 0,
    this.folderCount = 0,
    this.totalBytes = 0,
  });

  final int fileCount;
  final int folderCount;
  final int totalBytes;
}

/// Terminal message: the job failed. The error is carried as a string because
/// arbitrary exception objects are not always sendable between isolates.
class BulkError {
  const BulkError(this.kind, this.message, this.path);

  /// One of: 'permission', 'notFound', 'exists', 'full', 'cancelled', 'other'.
  final String kind;
  final String message;
  final String? path;
}

/// Sent from the main isolate to ask the worker to stop.
const String kCancelMessage = 'cancel';

/// Entry point for [Isolate.spawn].
Future<void> bulkWorkerMain(BulkRequest request) async {
  final ReceivePort control = ReceivePort();
  bool cancelled = false;
  control.listen((Object? message) {
    if (message == kCancelMessage) {
      cancelled = true;
    }
  });
  // Hand the main isolate a way to cancel us.
  request.replyPort.send(control.sendPort);

  bool isCancelled() => cancelled;

  try {
    switch (request.op) {
      case BulkOp.stats:
        final BulkDone result = await _stats(
          request.sourcePath,
          request.replyPort,
          isCancelled,
        );
        request.replyPort.send(result);
      case BulkOp.delete:
        await _delete(request.sourcePath, request.replyPort, isCancelled);
        request.replyPort.send(const BulkDone());
      case BulkOp.copy:
        await _copy(
          request.sourcePath,
          request.destinationPath!,
          request.replyPort,
          isCancelled,
        );
        request.replyPort.send(const BulkDone());
    }
  } on _Cancelled {
    request.replyPort.send(
      const BulkError('cancelled', 'Operation cancelled', null),
    );
  } on _NotFound catch (e) {
    request.replyPort.send(
      BulkError('notFound', 'File no longer exists', e.path),
    );
  } on FileSystemException catch (e) {
    request.replyPort.send(
      BulkError(_classify(e), e.message, e.path),
    );
  } on Object catch (e) {
    request.replyPort.send(BulkError('other', e.toString(), null));
  } finally {
    control.close();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// The source vanished before the job started. Distinct from a
/// [FileSystemException] because a synthesised one carries no errno, and the
/// errno is what [_classify] reads to pick a typed failure.
class _NotFound implements Exception {
  const _NotFound(this.path);

  final String path;
}

/// Maps an OS errno onto the app's typed failure kinds.
String _classify(FileSystemException e) {
  final int? code = e.osError?.errorCode;
  // 1 EPERM, 13 EACCES on POSIX; 5 ERROR_ACCESS_DENIED on Windows.
  if (code == 1 || code == 13 || code == 5) {
    return 'permission';
  }
  // 2 ENOENT.
  if (code == 2) {
    return 'notFound';
  }
  // 17 EEXIST.
  if (code == 17) {
    return 'exists';
  }
  // 28 ENOSPC.
  if (code == 28) {
    return 'full';
  }
  // 36 ENAMETOOLONG.
  if (code == 36) {
    return 'tooLong';
  }
  return 'other';
}

Future<BulkDone> _stats(
  String path,
  SendPort reply,
  bool Function() isCancelled,
) async {
  int files = 0;
  int folders = 0;
  int bytes = 0;
  int seen = 0;

  final FileSystemEntityType type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.file) {
    final File f = File(path);
    return BulkDone(fileCount: 1, totalBytes: await f.length());
  }

  await for (final FileSystemEntity entity
      in Directory(path).list(recursive: true, followLinks: false)) {
    if (isCancelled()) {
      throw const _Cancelled();
    }
    if (entity is File) {
      files++;
      // A file can vanish mid-walk; that is not an error for a size estimate.
      try {
        bytes += await entity.length();
      } on FileSystemException {
        continue;
      }
    } else if (entity is Directory) {
      folders++;
    }
    if (++seen % _yieldEvery == 0) {
      reply.send(BulkProgress(seen, 0, entity.path));
      await Future<void>.delayed(Duration.zero);
    }
  }
  return BulkDone(fileCount: files, folderCount: folders, totalBytes: bytes);
}

Future<void> _delete(
  String path,
  SendPort reply,
  bool Function() isCancelled,
) async {
  final FileSystemEntityType type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.notFound) {
    throw _NotFound(path);
  }
  if (type != FileSystemEntityType.directory) {
    await File(path).delete();
    return;
  }

  // Collect first so there is a real total to show, then delete deepest-first
  // so directories are empty by the time they are removed.
  final List<FileSystemEntity> entries = <FileSystemEntity>[];
  await for (final FileSystemEntity e
      in Directory(path).list(recursive: true, followLinks: false)) {
    if (isCancelled()) {
      throw const _Cancelled();
    }
    entries.add(e);
  }
  entries.sort(
    (FileSystemEntity a, FileSystemEntity b) => b.path.length.compareTo(a.path.length),
  );

  int done = 0;
  for (final FileSystemEntity e in entries) {
    if (isCancelled()) {
      throw const _Cancelled();
    }
    try {
      await e.delete();
    } on FileSystemException {
      // Already gone, or a directory that is not yet empty because a child
      // failed. Keep going and let the final rmdir report the real problem.
    }
    if (++done % _yieldEvery == 0) {
      reply.send(BulkProgress(done, entries.length, e.path));
      await Future<void>.delayed(Duration.zero);
    }
  }
  await Directory(path).delete();
}

Future<void> _copy(
  String source,
  String destination,
  SendPort reply,
  bool Function() isCancelled,
) async {
  final FileSystemEntityType type = FileSystemEntity.typeSync(source);
  if (type == FileSystemEntityType.notFound) {
    throw _NotFound(source);
  }
  if (type != FileSystemEntityType.directory) {
    await File(source).copy(destination);
    return;
  }

  await Directory(destination).create(recursive: true);

  final List<FileSystemEntity> entries = <FileSystemEntity>[];
  await for (final FileSystemEntity e
      in Directory(source).list(recursive: true, followLinks: false)) {
    if (isCancelled()) {
      throw const _Cancelled();
    }
    entries.add(e);
  }

  int done = 0;
  for (final FileSystemEntity e in entries) {
    if (isCancelled()) {
      throw const _Cancelled();
    }
    final String relative = p.relative(e.path, from: source);
    final String target = p.join(destination, relative);
    if (e is Directory) {
      await Directory(target).create(recursive: true);
    } else if (e is File) {
      await Directory(p.dirname(target)).create(recursive: true);
      await e.copy(target);
    }
    if (++done % _yieldEvery == 0) {
      reply.send(BulkProgress(done, entries.length, e.path));
      await Future<void>.delayed(Duration.zero);
    }
  }
}
