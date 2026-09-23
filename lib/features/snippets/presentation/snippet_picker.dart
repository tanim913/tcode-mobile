/// Pick a snippet to insert.
///
/// Modelled on the outline sheet: an in-memory list, a pure ranking function,
/// and `Navigator.pop` returning what was chosen.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/core/utils/fuzzy_matcher.dart';
import 'package:pocket_code/data/models/snippet.dart';
import 'package:pocket_code/features/commands/presentation/palette_scaffold.dart';

/// A snippet plus the match that ranked it.
@immutable
class RankedSnippet {
  const RankedSnippet({required this.snippet, required this.indices});

  final Snippet snippet;

  /// Indices into the prefix, for the highlight.
  final List<int> indices;
}

/// Filters [snippets] by [query].
///
/// An empty query keeps the order they were defined in — the library is the
/// user's own list, and reordering it on open would make it unfamiliar.
List<RankedSnippet> rankSnippets(List<Snippet> snippets, String query) {
  final String pattern = query.trim();
  if (pattern.isEmpty) {
    return snippets
        .map((Snippet s) => RankedSnippet(snippet: s, indices: const <int>[]))
        .toList();
  }

  final List<({RankedSnippet ranked, int score})> scored =
      <({RankedSnippet ranked, int score})>[];
  for (final Snippet snippet in snippets) {
    final FuzzyMatch? onPrefix = FuzzyMatcher.match(pattern, snippet.prefix);
    if (onPrefix != null) {
      scored.add((
        ranked: RankedSnippet(snippet: snippet, indices: onPrefix.indices),
        score: onPrefix.score + 100,
      ));
      continue;
    }
    // The description is searched too, so "loop" finds a snippet named `fori`.
    if (snippet.description.isEmpty) {
      continue;
    }
    final FuzzyMatch? onDescription =
        FuzzyMatcher.match(pattern, snippet.description);
    if (onDescription != null) {
      scored.add((
        ranked: RankedSnippet(snippet: snippet, indices: const <int>[]),
        score: onDescription.score,
      ));
    }
  }
  scored.sort((({RankedSnippet ranked, int score}) a,
          ({RankedSnippet ranked, int score}) b) =>
      b.score.compareTo(a.score));
  return scored
      .map((({RankedSnippet ranked, int score}) e) => e.ranked)
      .toList();
}

/// Shows the picker. Returns the snippet chosen, or null.
Future<Snippet?> showSnippetPicker(
  BuildContext context, {
  required List<Snippet> snippets,
  required String languageLabel,
}) {
  return showPaletteSheet<Snippet>(
    context: context,
    builder: (BuildContext context, ScrollController scrollController) =>
        _SnippetSheet(
      snippets: snippets,
      languageLabel: languageLabel,
      scrollController: scrollController,
    ),
  );
}

class _SnippetSheet extends StatefulWidget {
  const _SnippetSheet({
    required this.snippets,
    required this.languageLabel,
    required this.scrollController,
  });

  final List<Snippet> snippets;
  final String languageLabel;
  final ScrollController scrollController;

  @override
  State<_SnippetSheet> createState() => _SnippetSheetState();
}

class _SnippetSheetState extends State<_SnippetSheet> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<RankedSnippet> results =
        rankSnippets(widget.snippets, _query.text);

    return PaletteScaffold(
      controller: _query,
      hintText: 'Search snippets',
      semanticsLabel: 'Snippets',
      onChanged: (_) => setState(() {}),
      onSubmitted: () {
        if (results.isNotEmpty) {
          Navigator.of(context).pop(results.first.snippet);
        }
      },
      resultCount: results.length,
      emptyMessage: widget.snippets.isEmpty
          ? 'No snippets yet. Add them in Settings › Editor › Snippets.'
          : 'No snippet matches that.',
      footer: Text('For ${widget.languageLabel}'),
      child: ListView.builder(
        controller: widget.scrollController,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: results.length,
        itemBuilder: (BuildContext context, int i) => _SnippetRow(
          ranked: results[i],
          onTap: () => Navigator.of(context).pop(results[i].snippet),
        ),
      ),
    );
  }
}

class _SnippetRow extends StatelessWidget {
  const _SnippetRow({required this.ranked, required this.onTap});

  final RankedSnippet ranked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    final Snippet snippet = ranked.snippet;
    // One line of the body, so the row says what it will insert.
    final String preview = snippet.body.split('\n').first.trim();

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: snippet.description.isEmpty
          ? snippet.prefix
          : '${snippet.prefix}, ${snippet.description}',
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSizes.primaryTouchTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: <Widget>[
                Icon(Icons.short_text, size: 16, color: tokens.textMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      HighlightedText(
                        text: snippet.prefix,
                        indices: ranked.indices,
                        highlightColour: tokens.accent,
                      ),
                      Text(
                        snippet.description.isEmpty
                            ? preview
                            : snippet.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: tokens.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
