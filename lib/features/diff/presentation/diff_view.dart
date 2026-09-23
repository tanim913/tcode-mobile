/// A unified diff, rendered for a phone.
///
/// **Unified, not side by side, and that is a decision rather than a shortcut.**
/// Two panes at a code font on a 400px screen are about twenty columns each,
/// which is unreadable. A single column with a `+`/`-` gutter is the only shape
/// that works on this form factor.
///
/// No syntax highlighting: colouring a diff means running the grammar per line,
/// and `re_highlight` runs on the isolate machinery this app already documents
/// as unreliable. Added and removed lines are distinguished by background, the
/// same `withValues(alpha:)` treatment the conflict banner uses, so no new
/// colour tokens are needed.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/services/diff/line_diff.dart';

/// A short summary such as "3 changes · +2 −1", or that there are none.
String diffSummary(DiffResult diff) {
  final DiffStats stats = diff.stats;
  if (stats.isEmpty) {
    return 'No changes';
  }
  final int changes = stats.added + stats.removed;
  return '$changes change${changes == 1 ? '' : 's'} · '
      '+${stats.added} −${stats.removed}';
}

class DiffView extends StatelessWidget {
  const DiffView({
    required this.diff,
    required this.editor,
    super.key,
  });

  final DiffResult diff;

  /// The editor settings, so the diff is drawn in the same font the file is.
  final EditorSettings editor;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;

    if (!diff.hasChanges) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No changes',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: tokens.textMuted),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (diff.truncated)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            color: tokens.warning.withValues(alpha: 0.14),
            child: Text(
              'This file is too large to compare line by line, so every line '
              'is shown as replaced.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: diff.lines.length,
            itemBuilder: (BuildContext context, int i) => _DiffRow(
              line: diff.lines[i],
              tokens: tokens,
              editor: editor,
            ),
          ),
        ),
      ],
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.line,
    required this.tokens,
    required this.editor,
  });

  final DiffLine line;
  final AppColorTokens tokens;
  final EditorSettings editor;

  @override
  Widget build(BuildContext context) {
    final (Color? background, String marker, Color markerColour) =
        switch (line.op) {
      DiffOp.insert => (
          tokens.success.withValues(alpha: 0.14),
          '+',
          tokens.success,
        ),
      DiffOp.delete => (
          tokens.danger.withValues(alpha: 0.14),
          '−',
          tokens.danger,
        ),
      DiffOp.keep => (null, ' ', tokens.textMuted),
    };

    final TextStyle code = TextStyle(
      fontFamily: editor.fontFamily.family,
      fontFamilyFallback: const <String>['JetBrains Mono', 'monospace'],
      fontSize: editor.fontSize,
      height: editor.lineHeight,
      color: tokens.textPrimary,
    );

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: switch (line.op) {
        DiffOp.insert => 'Added: ${line.text}',
        DiffOp.delete => 'Removed: ${line.text}',
        DiffOp.keep => line.text,
      },
      child: ColoredBox(
        color: background ?? Colors.transparent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 46,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  '${line.oldLine ?? line.newLine ?? ''}',
                  textAlign: TextAlign.right,
                  style: code.copyWith(
                    color: tokens.textMuted,
                    fontSize: editor.fontSize - 2,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 14,
              child: Text(
                marker,
                style: code.copyWith(color: markerColour),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  line.text.isEmpty ? ' ' : line.text,
                  style: code,
                  softWrap: editor.wordWrap,
                  overflow: editor.wordWrap
                      ? TextOverflow.clip
                      : TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A full route for a comparison. A diff needs the whole screen on a phone.
class DiffScreen extends StatelessWidget {
  const DiffScreen({
    required this.title,
    required this.subtitle,
    required this.diff,
    required this.editor,
    this.onRestore,
    super.key,
  });

  final String title;

  /// Names both sides, so it is never ambiguous which way round it reads.
  final String subtitle;

  final DiffResult diff;
  final EditorSettings editor;

  /// Shown only when there is something to restore to.
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(title),
            Text(
              '$subtitle · ${diffSummary(diff)}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.textMuted),
            ),
          ],
        ),
        actions: <Widget>[
          if (onRestore != null)
            TextButton(onPressed: onRestore, child: const Text('Restore')),
        ],
      ),
      body: DiffView(diff: diff, editor: editor),
    );
  }
}
