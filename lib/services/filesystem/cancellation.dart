/// Cooperative cancellation for long-running file operations.
///
/// Deliberately not `Completer`-based: a recursive copy needs to check "should
/// I stop?" between every entry, which is a synchronous question. The token is
/// passed down through the isolate boundary as a flag holder.
library;

import 'package:pocket_code/core/errors/failures.dart';

class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  /// Call between units of work. Throws so the operation unwinds cleanly
  /// instead of silently returning a half-finished result.
  void throwIfCancelled({String? path}) {
    if (_cancelled) {
      throw CancelledFailure(path: path);
    }
  }
}

/// Reported while a recursive operation runs, so the progress dialog can show
/// something specific rather than an indeterminate spinner.
class FileOperationProgress {
  const FileOperationProgress({
    required this.completed,
    required this.total,
    required this.currentPath,
  });

  final int completed;

  /// May be 0 while the operation is still counting what it has to do.
  final int total;

  final String currentPath;

  double? get fraction => total <= 0 ? null : (completed / total).clamp(0.0, 1.0);
}

typedef ProgressCallback = void Function(FileOperationProgress progress);
