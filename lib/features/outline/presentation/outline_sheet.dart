/// The outline, which doubles as Go to Symbol.
///
/// One surface for both because on a phone they are the same gesture: show me
/// what is in this file, let me jump to it. The list is searchable, so a long
/// file narrows the same way Quick Open does.
///
/// The heuristic is labelled honestly. [SymbolExtractor.outlineLabel] is
/// "Basic outline" and a language with no patterns says so rather than showing
/// an empty list that looks like a file with nothing in it.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/core/utils/fuzzy_matcher.dart';
import 'package:pocket_code/data/models/document_symbol.dart';
import 'package:pocket_code/features/commands/presentation/palette_scaffold.dart';
import 'package:pocket_code/services/language/symbol_extractor.dart';

/// A symbol plus the match that ranked it.
@immutable
class RankedSymbol {
  const RankedSymbol({required this.symbol, required this.indices});

  final DocumentSymbol symbol;

  /// Indices into the symbol name, for the highlight.
  final List<int> indices;
}

/// Filters [symbols] by [query].
///
/// An empty query keeps document order — an outline's whole point is structure,
/// and re-sorting it by score would destroy that. Only once the user types does
/// the list become a ranked search.
List<RankedSymbol> rankSymbols(List<DocumentSymbol> symbols, String query) {
  final String pattern = query.trim();
  if (pattern.isEmpty) {
    return symbols
        .map((DocumentSymbol s) =>
            RankedSymbol(symbol: s, indices: const <int>[]))
        .toList();
  }

  final List<({RankedSymbol ranked, int score})> scored =
      <({RankedSymbol ranked, int score})>[];
  for (final DocumentSymbol symbol in symbols) {
    final FuzzyMatch? match = FuzzyMatcher.match(pattern, symbol.name);
    if (match == null) {
      continue;
    }
    scored.add((
      ranked: RankedSymbol(symbol: symbol, indices: match.indices),
      score: match.score,
    ));
  }
  scored.sort((({RankedSymbol ranked, int score}) a,
      ({RankedSymbol ranked, int score}) b) {
    final int byScore = b.score.compareTo(a.score);
    return byScore != 0
        ? byScore
        : a.ranked.symbol.line.compareTo(b.ranked.symbol.line);
  });
  return scored.map((({RankedSymbol ranked, int score}) e) => e.ranked).toList();
}

/// Shows the outline. Returns the symbol picked, or null.
Future<DocumentSymbol?> showOutline(
  BuildContext context, {
  required List<DocumentSymbol> symbols,
  required bool languageSupported,
  required String languageLabel,
}) {
  return showPaletteSheet<DocumentSymbol>(
    context: context,
    builder: (BuildContext context, ScrollController scrollController) =>
        _OutlineSheet(
      symbols: symbols,
      languageSupported: languageSupported,
      languageLabel: languageLabel,
      scrollController: scrollController,
    ),
  );
}

class _OutlineSheet extends StatefulWidget {
  const _OutlineSheet({
    required this.symbols,
    required this.languageSupported,
    required this.languageLabel,
    required this.scrollController,
  });

  final List<DocumentSymbol> symbols;
  final bool languageSupported;
  final String languageLabel;
  final ScrollController scrollController;

  @override
  State<_OutlineSheet> createState() => _OutlineSheetState();
}

class _OutlineSheetState extends State<_OutlineSheet> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<RankedSymbol> results =
        widget.languageSupported ? rankSymbols(widget.symbols, _query.text) : const <RankedSymbol>[];

    return PaletteScaffold(
      controller: _query,
      hintText: 'Search symbols',
      semanticsLabel: SymbolExtractor.outlineLabel,
      onChanged: (_) => setState(() {}),
      onSubmitted: () {
        if (results.isNotEmpty) {
          Navigator.of(context).pop(results.first.symbol);
        }
      },
      resultCount: results.length,
      emptyMessage: _emptyMessage(),
      // The label is required by the brief: this is a regex heuristic, and the
      // UI must not imply it is a parser.
      footer: widget.languageSupported
          ? Text('${SymbolExtractor.outlineLabel} · ${widget.languageLabel}')
          : null,
      child: ListView.builder(
        controller: widget.scrollController,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: results.length,
        itemBuilder: (BuildContext context, int i) => _SymbolRow(
          ranked: results[i],
          onTap: () => Navigator.of(context).pop(results[i].symbol),
        ),
      ),
    );
  }

  String _emptyMessage() {
    if (!widget.languageSupported) {
      return '${SymbolExtractor.unavailableMessage} (${widget.languageLabel}).';
    }
    if (widget.symbols.isEmpty) {
      return 'No classes or functions found in this file';
    }
    return 'No symbol matches "${_query.text.trim()}"';
  }
}

class _SymbolRow extends StatelessWidget {
  const _SymbolRow({required this.ranked, required this.onTap});

  final RankedSymbol ranked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppColorTokens tokens = theme.extension<AppColorTokens>()!;
    final DocumentSymbol symbol = ranked.symbol;

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: symbol.name,
      hint: '${symbol.kind.label}, line ${symbol.line}',
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppSizes.primaryTouchTarget,
          ),
          padding: EdgeInsets.fromLTRB(
            // Nesting is the structure, so it has to be visible. Capped so a
            // deeply nested symbol still leaves room for its name.
            16 + (symbol.level.clamp(0, 4) * 14).toDouble(),
            6,
            16,
            6,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                _iconFor(symbol.kind),
                size: 16,
                color: _colourFor(symbol.kind, tokens),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    HighlightedText(
                      text: symbol.name,
                      indices: ranked.indices,
                      highlightColour: tokens.accent,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: tokens.textPrimary),
                    ),
                    if (symbol.detail != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        symbol.detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: tokens.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${symbol.line}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(SymbolKind kind) => switch (kind) {
        SymbolKind.classType => Icons.class_outlined,
        SymbolKind.interfaceType => Icons.interests_outlined,
        SymbolKind.enumType => Icons.list_alt_outlined,
        SymbolKind.constructor => Icons.build_outlined,
        SymbolKind.method => Icons.functions,
        SymbolKind.function => Icons.functions,
        SymbolKind.property => Icons.label_outline,
        SymbolKind.module => Icons.folder_outlined,
        SymbolKind.heading => Icons.title,
      };

  static Color _colourFor(SymbolKind kind, AppColorTokens tokens) =>
      switch (kind) {
        SymbolKind.classType ||
        SymbolKind.interfaceType ||
        SymbolKind.enumType =>
          tokens.accent,
        SymbolKind.constructor ||
        SymbolKind.method ||
        SymbolKind.function =>
          tokens.success,
        SymbolKind.property || SymbolKind.module => tokens.warning,
        SymbolKind.heading => tokens.textSecondary,
      };
}
