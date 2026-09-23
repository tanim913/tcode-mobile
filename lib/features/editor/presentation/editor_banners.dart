/// The strips and placeholders the editor pane shows around, or instead of, a
/// document: a disk-conflict banner, a one-line notice, and the full-pane
/// message used for "no file open" and for a load failure.
///
/// Split out of `editor_pane.dart` to keep that file inside the size
/// convention. They are pure presentation — no Riverpod, no state — so they
/// stay trivially testable and reusable.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';

/// Shown when the file changed on disk while the buffer was dirty. Both options
/// are destructive in opposite directions, so neither happens automatically.
class ConflictBanner extends StatelessWidget {
  const ConflictBanner({
    required this.name,
    required this.tokens,
    required this.onReload,
    required this.onKeepMine,
    super.key,
  });

  final String name;
  final AppColorTokens tokens;
  final VoidCallback onReload;
  final VoidCallback onKeepMine;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      color: tokens.danger.withValues(alpha: 0.14),
      child: Row(
        children: <Widget>[
          Icon(Icons.sync_problem_outlined, size: 15, color: tokens.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$name changed on disk, and you have unsaved changes.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(onPressed: onReload, child: const Text('Reload')),
          TextButton(onPressed: onKeepMine, child: const Text('Keep mine')),
        ],
      ),
    );
  }
}

class EditorNotice extends StatelessWidget {
  const EditorNotice({
    required this.message,
    required this.tokens,
    required this.onDismiss,
    super.key,
  });

  final String message;
  final AppColorTokens tokens;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      color: tokens.warning.withValues(alpha: 0.14),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline, size: 15, color: tokens.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
          IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, size: 15),
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class EditorMessage extends StatelessWidget {
  const EditorMessage({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
    required this.tokens,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final AppColorTokens tokens;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: tokens.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 34, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Text(
                  body,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
