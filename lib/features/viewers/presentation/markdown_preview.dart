/// Rendered Markdown, as the brief's "toggle between source and rendered
/// preview" requires.
///
/// Renders the *live buffer*, not the saved file, so the preview follows what
/// is being typed rather than what was last written to disk.
///
/// Links are shown but not followed: the app has no network permission, and
/// opening a browser from a preview would be the one place it reached out. A
/// tap explains that instead of silently doing nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';

class MarkdownPreview extends StatelessWidget {
  const MarkdownPreview({
    required this.source,
    required this.onLinkTapped,
    super.key,
  });

  final String source;

  /// Called with the href of a tapped link, so the shell can explain why
  /// nothing opened.
  final ValueChanged<String> onLinkTapped;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppColorTokens tokens = theme.extension<AppColorTokens>()!;

    if (source.trim().isEmpty) {
      return Center(
        child: Text(
          'Nothing to preview yet',
          style: theme.textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
        ),
      );
    }

    return ColoredBox(
      color: tokens.background,
      child: Markdown(
        data: source,
        selectable: true,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        onTapLink: (String text, String? href, String title) {
          if (href != null) {
            onLinkTapped(href);
          }
        },
        styleSheet: _styleSheet(theme, tokens),
      ),
    );
  }

  /// Maps the app's own tokens onto the renderer, so the preview belongs to
  /// this app rather than looking like a default Material document.
  MarkdownStyleSheet _styleSheet(ThemeData theme, AppColorTokens tokens) {
    final TextStyle mono = TextStyle(
      fontFamily: 'JetBrains Mono',
      fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) - 1,
      color: tokens.textPrimary,
    );

    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
      h1: theme.textTheme.headlineSmall?.copyWith(color: tokens.textPrimary),
      h2: theme.textTheme.titleLarge?.copyWith(color: tokens.textPrimary),
      h3: theme.textTheme.titleMedium?.copyWith(color: tokens.textPrimary),
      a: TextStyle(
        color: tokens.accent,
        decoration: TextDecoration.underline,
        decorationColor: tokens.accent,
      ),
      code: mono,
      codeblockDecoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      blockquoteDecoration: BoxDecoration(
        color: tokens.surface,
        border: Border(left: BorderSide(color: tokens.accent, width: 3)),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      tableBorder: TableBorder.all(color: tokens.border),
      tableHead: theme.textTheme.bodyMedium?.copyWith(
        color: tokens.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      tableBody: theme.textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
    );
  }
}
