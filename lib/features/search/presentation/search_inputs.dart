/// The input half of the workspace search screen: the query and replacement
/// fields, the match-case / whole-word / regex toggles, the folder scope chip,
/// and the replace-all button.
///
/// Split out of `search_panel.dart`, which had grown past the size convention.
/// All stateless: the panel owns every value and passes it down.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/services/search/search_scope.dart';

class SearchInputs extends StatelessWidget {
  const SearchInputs({
    required this.pattern,
    required this.replacement,
    required this.showReplace,
    required this.badRegex,
    required this.caseSensitive,
    required this.wholeWord,
    required this.regex,
    required this.onToggleCase,
    required this.onToggleWord,
    required this.onToggleRegex,
    required this.onSubmit,
    required this.onChanged,
    super.key,
  });

  final TextEditingController pattern;
  final TextEditingController replacement;
  final bool showReplace;
  final bool badRegex;
  final bool caseSensitive;
  final bool wholeWord;
  final bool regex;
  final VoidCallback onToggleCase;
  final VoidCallback onToggleWord;
  final VoidCallback onToggleRegex;
  final VoidCallback onSubmit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        children: <Widget>[
          TextField(
            controller: pattern,
            textInputAction: TextInputAction.search,
            onChanged: (_) => onChanged(),
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              hintText: 'Search',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              errorText: badRegex ? 'Not a valid regular expression' : null,
              suffixIcon: IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.arrow_forward, size: 18),
                onPressed: onSubmit,
              ),
            ),
          ),
          if (showReplace) ...<Widget>[
            const SizedBox(height: 8),
            TextField(
              controller: replacement,
              decoration: const InputDecoration(
                hintText: 'Replace with',
                isDense: true,
                prefixIcon: Icon(Icons.edit_outlined, size: 18),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              SearchToggle(
                label: 'Aa',
                tooltip: 'Match case',
                active: caseSensitive,
                onTap: onToggleCase,
              ),
              SearchToggle(
                label: 'W',
                tooltip: 'Whole word',
                active: wholeWord,
                onTap: onToggleWord,
              ),
              SearchToggle(
                label: '.*',
                tooltip: 'Regular expression',
                active: regex,
                onTap: onToggleRegex,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SearchToggle extends StatelessWidget {
  const SearchToggle({
    required this.label,
    required this.tooltip,
    required this.active,
    required this.onTap,
    super.key,
  });

  final String label;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          container: true,
          excludeSemantics: true,
          toggled: active,
          label: tooltip,
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(
                minWidth: AppSizes.minTouchTarget,
                minHeight: AppSizes.minTouchTarget,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active
                    ? tokens.accent.withValues(alpha: 0.16)
                    : Colors.transparent,
                border: Border.all(
                  color: active ? tokens.accent : tokens.border,
                ),
                borderRadius: const BorderRadius.all(Radius.circular(6)),
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: active ? tokens.accent : tokens.textSecondary,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SearchReplaceBar extends StatelessWidget {
  const SearchReplaceBar({
    required this.enabled,
    required this.onReplaceAll,
    super.key,
  });

  final bool enabled;
  final VoidCallback onReplaceAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: enabled ? onReplaceAll : null,
          icon: const Icon(Icons.find_replace, size: 18),
          label: const Text('Replace all'),
        ),
      ),
    );
  }
}

/// "Searching in `DMND/`", with a button to widen to the whole workspace.
///
/// Always visible while a scope is set, because a search that silently looks in
/// fewer places than the user expects is the kind of thing that makes someone
/// conclude a name is unused when it is not.
class SearchScopeChip extends StatelessWidget {
  const SearchScopeChip({
    required this.scope,
    required this.onClear,
    super.key,
  });

  final SearchScope scope;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InputChip(
          avatar: Icon(Icons.folder_outlined, size: 16, color: tokens.accent),
          label: Text(
            'Searching in ${scope.label}',
            overflow: TextOverflow.ellipsis,
          ),
          deleteIcon: const Icon(Icons.close, size: 16),
          deleteButtonTooltipMessage: 'Search the whole workspace',
          onDeleted: onClear,
        ),
      ),
    );
  }
}
