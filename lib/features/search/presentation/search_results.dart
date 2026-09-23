/// The results half of the workspace search screen: the summary line, one
/// group per file, a row per match, and the empty-state hint.
///
/// Split out of `search_panel.dart` for size. Stateless, like `search_inputs.dart`.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/services/search/workspace_search.dart';

/// What the caller does with a chosen match.
typedef SearchHitCallback = void Function(FileMatches file, SearchMatch match);

class SearchSummary extends StatelessWidget {
  const SearchSummary({
    required this.results,
    required this.tokens,
    super.key,
  });

  final SearchResults results;
  final AppColorTokens tokens;

  @override
  Widget build(BuildContext context) {
    final int matches = results.matchCount;
    final int files = results.files.length;
    final String head = '$matches ${matches == 1 ? 'match' : 'matches'} in '
        '$files ${files == 1 ? 'file' : 'files'}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              head,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.textSecondary),
            ),
            // Both of these are the panel refusing to imply it searched more
            // than it did.
            if (results.truncated)
              Text(
                'Stopped at $matches matches. Narrow the search to see the rest.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: tokens.warning),
              ),
            if (results.filesSkipped > 0)
              Text(
                '${results.filesSkipped} skipped as too large or not text',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: tokens.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

class SearchFileGroup extends StatelessWidget {
  const SearchFileGroup({
    required this.group,
    required this.onOpenHit,
    super.key,
  });

  final FileMatches group;
  final SearchHitCallback onOpenHit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppColorTokens tokens = theme.extension<AppColorTokens>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          color: tokens.sidebar,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  group.file.relativePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: tokens.textSecondary),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${group.matches.length}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ),
        for (final SearchMatch match in group.matches)
          SearchMatchRow(
            match: match,
            tokens: tokens,
            onTap: () => onOpenHit(group, match),
          ),
      ],
    );
  }
}

class SearchMatchRow extends StatelessWidget {
  const SearchMatchRow({
    required this.match,
    required this.tokens,
    required this.onTap,
    super.key,
  });

  final SearchMatch match;
  final AppColorTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Long lines are trimmed around the hit rather than from the start: a
    // minified line would otherwise show 200 characters of nothing relevant.
    final int from = (match.start - 24).clamp(0, match.lineText.length);
    final String prefix = match.lineText.substring(from, match.start);
    final String hit =
        match.lineText.substring(match.start, match.start + match.length);
    final String suffix = match.lineText.substring(match.start + match.length);

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: 'Line ${match.line}: ${match.lineText.trim()}',
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppSizes.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 44,
                child: Text(
                  '${match.line}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: tokens.textMuted),
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'JetBrains Mono',
                      color: tokens.textSecondary,
                    ),
                    children: <TextSpan>[
                      if (from > 0) const TextSpan(text: '…'),
                      TextSpan(text: prefix),
                      TextSpan(
                        text: hit,
                        style: TextStyle(
                          color: tokens.accent,
                          fontWeight: FontWeight.w700,
                          backgroundColor:
                              tokens.accent.withValues(alpha: 0.14),
                        ),
                      ),
                      TextSpan(text: suffix),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SearchHint extends StatelessWidget {
  const SearchHint({
    required this.icon,
    required this.text,
    required this.tokens,
    super.key,
  });

  final IconData icon;
  final String text;
  final AppColorTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 30, color: tokens.textMuted),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
