/// The command palette: type a few letters, run any action in the app.
///
/// Ranking is [FuzzyMatcher], and the matched characters are highlighted —
/// a fuzzy list that does not show *why* a row matched is guesswork.
///
/// Disabled commands are listed and greyed rather than hidden, so "Save" not
/// being available reads as "nothing to save" rather than "this app has no
/// save command".
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/core/utils/fuzzy_matcher.dart';
import 'package:pocket_code/features/commands/presentation/palette_scaffold.dart';
import 'package:pocket_code/services/commands/command.dart';
import 'package:pocket_code/services/commands/command_registry.dart';

/// One command plus the match that put it in the list.
@immutable
class RankedCommand {
  const RankedCommand({required this.command, required this.match});

  final Command command;
  final FuzzyMatch match;
}

/// Filters and ranks [commands] against [query].
///
/// An empty query keeps registration order, which groups the catalogue by
/// category; anything else sorts by score. Ties break on title so the list
/// cannot reshuffle between identical queries.
List<RankedCommand> rankCommands(List<Command> commands, String query) {
  final String pattern = query.trim();
  final List<RankedCommand> ranked = <RankedCommand>[];
  for (final Command command in commands) {
    // Matching the category too lets "edit" find every editing command, which
    // is how people search when they know the area but not the verb.
    final FuzzyMatch? title = FuzzyMatcher.match(pattern, command.title);
    final FuzzyMatch? category =
        FuzzyMatcher.match(pattern, command.category.label);
    if (title == null && category == null) {
      continue;
    }
    // The highlight must point at the title, so a category-only match keeps a
    // title match of no characters rather than indices into the wrong string.
    final FuzzyMatch match = title ??
        const FuzzyMatch(score: 0, indices: <int>[]);
    final int score = title?.score ?? (category!.score ~/ 2);
    ranked.add(
      RankedCommand(
        command: command,
        match: FuzzyMatch(score: score, indices: match.indices),
      ),
    );
  }
  if (pattern.isEmpty) {
    return ranked;
  }
  ranked.sort((RankedCommand a, RankedCommand b) {
    final int byScore = b.match.score.compareTo(a.match.score);
    return byScore != 0 ? byScore : a.command.title.compareTo(b.command.title);
  });
  return ranked;
}

/// Shows the palette. Returns the id of the command that ran, or null.
Future<String?> showCommandPalette(
  BuildContext context, {
  required CommandRegistry registry,
}) {
  return showPaletteSheet<String>(
    context: context,
    builder: (BuildContext context, ScrollController scrollController) =>
        _CommandPalette(registry: registry, scrollController: scrollController),
  );
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({
    required this.registry,
    required this.scrollController,
  });

  final CommandRegistry registry;
  final ScrollController scrollController;

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final TextEditingController _query = TextEditingController();
  late List<Command> _commands = widget.registry.forSurface(
    CommandSurface.palette,
  );

  @override
  void initState() {
    super.initState();
    widget.registry.addListener(_onRegistryChanged);
  }

  @override
  void dispose() {
    widget.registry.removeListener(_onRegistryChanged);
    _query.dispose();
    super.dispose();
  }

  void _onRegistryChanged() {
    setState(() {
      _commands = widget.registry.forSurface(CommandSurface.palette);
    });
  }

  Future<void> _run(Command command) async {
    if (!command.enabled) {
      return;
    }
    // Pop first: the handler may push its own dialog, and stacking the palette
    // underneath would leave it on screen behind it.
    Navigator.of(context).pop(command.id);
    await command.handler();
  }

  @override
  Widget build(BuildContext context) {
    final List<RankedCommand> results = rankCommands(_commands, _query.text);

    return PaletteScaffold(
      controller: _query,
      hintText: 'Type a command',
      semanticsLabel: 'Command palette',
      onChanged: (_) => setState(() {}),
      onSubmitted: () {
        if (results.isNotEmpty) {
          _run(results.first.command);
        }
      },
      resultCount: results.length,
      emptyMessage: 'No command matches "${_query.text.trim()}"',
      child: ListView.builder(
        controller: widget.scrollController,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: results.length,
        itemBuilder: (BuildContext context, int index) => _CommandRow(
          ranked: results[index],
          onTap: () => _run(results[index].command),
        ),
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({required this.ranked, required this.onTap});

  final RankedCommand ranked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppColorTokens tokens = theme.extension<AppColorTokens>()!;
    final Command command = ranked.command;
    final bool enabled = command.enabled;
    final Color labelColour =
        enabled ? tokens.textPrimary : tokens.textMuted;

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      enabled: enabled,
      label: command.title,
      hint: <String>[
        command.category.label,
        if (!enabled) 'Unavailable right now',
        if (command.shortcutLabel != null) command.shortcutLabel!,
      ].join('. '),
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppSizes.primaryTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: <Widget>[
              Icon(
                command.icon ?? Icons.chevron_right,
                size: 18,
                color: enabled ? tokens.textSecondary : tokens.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    HighlightedText(
                      text: command.title,
                      indices: ranked.match.indices,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: labelColour),
                      highlightColour: tokens.accent,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      command.description ?? command.category.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: tokens.textMuted),
                    ),
                  ],
                ),
              ),
              if (command.shortcutLabel != null) ...<Widget>[
                const SizedBox(width: 8),
                _ShortcutChip(
                  label: command.shortcutLabel!,
                  tokens: tokens,
                  enabled: enabled,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip({
    required this.label,
    required this.tokens,
    required this.enabled,
  });

  final String label;
  final AppColorTokens tokens;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: enabled ? tokens.textSecondary : tokens.textMuted,
            ),
      ),
    );
  }
}
