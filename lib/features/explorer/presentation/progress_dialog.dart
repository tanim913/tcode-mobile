/// Progress with Cancel for recursive file operations.
///
/// The dialog *owns* the operation rather than being shown beside it. That
/// removes the race where a fast operation finishes before its dialog has been
/// pushed and the close call lands on a route that does not exist yet.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/services/filesystem/cancellation.dart';

/// Runs [action] behind a modal progress dialog and returns its result.
///
/// Returns null only if the route was popped without a result, which the
/// callers treat as a cancel.
Future<T?> runWithProgress<T>(
  BuildContext context, {
  required String title,
  required Future<T> Function(ProgressCallback onProgress, CancellationToken token)
      action,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) =>
        _ProgressDialog<T>(title: title, action: action),
  );
}

class _ProgressDialog<T> extends StatefulWidget {
  const _ProgressDialog({required this.title, required this.action});

  final String title;
  final Future<T> Function(ProgressCallback onProgress, CancellationToken token)
      action;

  @override
  State<_ProgressDialog<T>> createState() => _ProgressDialogState<T>();
}

class _ProgressDialogState<T> extends State<_ProgressDialog<T>> {
  final CancellationToken _token = CancellationToken();
  final ValueNotifier<FileOperationProgress?> _progress =
      ValueNotifier<FileOperationProgress?>(null);

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final T result = await widget.action(
      (FileOperationProgress progress) => _progress.value = progress,
      _token,
    );
    if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      // Cancelling has to go through the button: a back gesture that closed the
      // dialog while a recursive copy kept running would leave a half-finished
      // folder with nothing on screen to say so.
      canPop: false,
      child: AlertDialog(
        title: Text(widget.title),
        content: ValueListenableBuilder<FileOperationProgress?>(
          valueListenable: _progress,
          builder: (
            BuildContext context,
            FileOperationProgress? progress,
            Widget? child,
          ) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LinearProgressIndicator(value: progress?.fraction),
                const SizedBox(height: 12),
                Text(
                  progress == null
                      ? 'Preparing…'
                      : progress.total > 0
                          ? '${progress.completed} of ${progress.total}'
                          : 'Working…',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: _token.isCancelled ? null : _token.cancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
