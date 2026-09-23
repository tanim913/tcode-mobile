/// Find and replace, shown above the editor.
///
/// `re_editor` supplies the search engine through [CodeFindController] — match
/// finding, next/previous, replace and replace-all all live there, off the UI
/// isolate. This file is the panel around it.
///
/// **Whole word needs explaining.** `CodeFindOption` offers only `pattern`,
/// `caseSensitive` and `regex` — there is no whole-word flag. So the panel owns
/// the visible text field and *mirrors* a transformed pattern into the
/// controller's own field: with whole word on, the query is regex-escaped and
/// wrapped in `\b…\b`. The user never sees the transformation, and the engine
/// needs no patching. Whole word and regex are mutually exclusive in the UI,
/// because "whole word" applied to a hand-written regex means nothing coherent.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:re_editor/re_editor.dart';

/// Height of the find row, and of the replace row when shown.
const double _rowHeight = 46;

/// Builds the "3 of 17" / "No results" label.
///
/// Pure and public because the search itself runs on a spawned isolate that
/// does not deliver results under `flutter_test` — so this is unit tested
/// directly, and the live search is verified on a device instead.
String matchCountLabel({
  required String query,
  required int matchCount,
  required int currentIndex,
  required bool searching,
}) {
  if (searching) {
    return 'Searching…';
  }
  if (query.isEmpty) {
    return '';
  }
  if (matchCount == 0) {
    return 'No results';
  }
  return '${currentIndex + 1} of $matchCount';
}

class FindPanel extends StatefulWidget implements PreferredSizeWidget {
  const FindPanel({
    required this.controller,
    required this.readOnly,
    super.key,
  });

  final CodeFindController controller;

  /// Replace is hidden for a read-only document — offering it would be a lie.
  final bool readOnly;

  @override
  Size get preferredSize => Size.fromHeight(
        (controller.value?.replaceMode ?? false) && !readOnly
            ? _rowHeight * 2
            : _rowHeight,
      );

  @override
  State<FindPanel> createState() => _FindPanelState();
}

class _FindPanelState extends State<FindPanel> {
  /// The query as typed. Kept separate from the controller's own field so the
  /// whole-word transform stays invisible.
  final TextEditingController _query = TextEditingController();

  bool _wholeWord = false;

  @override
  void initState() {
    super.initState();
    // Adopt whatever the controller already had, so reopening the panel does
    // not wipe the previous search.
    _query.text = widget.controller.findInputController.text;
    _query.addListener(_pushQuery);
  }

  @override
  void dispose() {
    _query.removeListener(_pushQuery);
    _query.dispose();
    super.dispose();
  }

  /// Mirrors the visible query into the engine, applying the whole-word
  /// transform when it is on.
  void _pushQuery() {
    final String raw = _query.text;
    final String pattern = _wholeWord && raw.isNotEmpty
        ? r'\b' + RegExp.escape(raw) + r'\b'
        : raw;
    final TextEditingController target = widget.controller.findInputController;
    if (target.text != pattern) {
      target.text = pattern;
    }
  }

  void _toggleWholeWord() {
    final bool turningOn = !_wholeWord;
    final bool engineRegex = widget.controller.value?.option.regex ?? false;

    // Refuse to *engage* over a regex the user wrote themselves — but never
    // refuse to disengage, or the option would latch on permanently (whole word
    // turns the engine's regex flag on, which would then look like a user
    // regex on the way back out).
    if (turningOn && engineRegex) {
      return;
    }

    setState(() => _wholeWord = turningOn);

    // Whole word is implemented *as* a regex, so keep the engine's flag in step
    // in both directions.
    if (engineRegex != turningOn) {
      widget.controller.toggleRegex();
    }
    _pushQuery();
  }

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;

    return ValueListenableBuilder<CodeFindValue?>(
      valueListenable: widget.controller,
      builder: (BuildContext context, CodeFindValue? value, _) {
        if (value == null) {
          return const SizedBox.shrink();
        }
        final bool showReplace = value.replaceMode && !widget.readOnly;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border(bottom: BorderSide(color: tokens.border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _FindRow(
                controller: widget.controller,
                query: _query,
                value: value,
                tokens: tokens,
                wholeWord: _wholeWord,
                canReplace: !widget.readOnly,
                onToggleWholeWord: _toggleWholeWord,
              ),
              if (showReplace)
                _ReplaceRow(controller: widget.controller, tokens: tokens),
            ],
          ),
        );
      },
    );
  }
}

class _FindRow extends StatelessWidget {
  const _FindRow({
    required this.controller,
    required this.query,
    required this.value,
    required this.tokens,
    required this.wholeWord,
    required this.canReplace,
    required this.onToggleWholeWord,
  });

  final CodeFindController controller;
  final TextEditingController query;
  final CodeFindValue value;
  final AppColorTokens tokens;
  final bool wholeWord;
  final bool canReplace;
  final VoidCallback onToggleWholeWord;

  String get _matchLabel {
    final CodeFindResult? result = value.result;
    return matchCountLabel(
      query: query.text,
      matchCount: result?.matches.length ?? 0,
      currentIndex: result?.index ?? 0,
      searching: value.searching,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasMatches = (value.result?.matches.length ?? 0) > 0;
    final bool regexOn = value.option.regex;

    return SizedBox(
      height: _rowHeight,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: query,
              focusNode: controller.findInputFocusNode,
              autofocus: true,
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: const InputDecoration(
                hintText: 'Find',
                isDense: true,
                border: InputBorder.none,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => controller.nextMatch(),
            ),
          ),
          // Flexible, not fixed: at 390dp the row is tight and a rigid label
          // is what pushed it into overflow.
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _matchLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _matchLabel == 'No results'
                          ? tokens.danger
                          : tokens.textSecondary,
                    ),
              ),
            ),
          ),
          _Toggle(
            label: 'Match case',
            text: 'Aa',
            active: value.option.caseSensitive,
            tokens: tokens,
            onPressed: controller.toggleCaseSensitive,
          ),
          _Toggle(
            label: 'Whole word',
            text: 'ab',
            active: wholeWord,
            tokens: tokens,
            // Disabled while a raw regex is in use: the two cannot coexist
            // coherently, so the UI says so rather than silently ignoring one.
            onPressed: regexOn && !wholeWord ? null : onToggleWholeWord,
          ),
          _Toggle(
            label: 'Regular expression',
            text: '.*',
            // Whole word is implemented by turning the engine's regex flag on,
            // so `regexOn` is true even when the user never asked for regex.
            // Showing it lit would misreport what they chose.
            active: regexOn && !wholeWord,
            tokens: tokens,
            onPressed: wholeWord ? null : controller.toggleRegex,
          ),
          _Action(
            icon: Icons.keyboard_arrow_up,
            label: 'Previous match',
            tokens: tokens,
            onPressed: hasMatches ? controller.previousMatch : null,
          ),
          _Action(
            icon: Icons.keyboard_arrow_down,
            label: 'Next match',
            tokens: tokens,
            onPressed: hasMatches ? controller.nextMatch : null,
          ),
          if (canReplace)
            _Action(
              icon: value.replaceMode
                  ? Icons.unfold_less
                  : Icons.find_replace_outlined,
              label: value.replaceMode ? 'Hide replace' : 'Show replace',
              tokens: tokens,
              onPressed: controller.toggleMode,
            ),
          _Action(
            icon: Icons.close,
            label: 'Close find',
            tokens: tokens,
            onPressed: controller.close,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _ReplaceRow extends StatelessWidget {
  const _ReplaceRow({required this.controller, required this.tokens});

  final CodeFindController controller;
  final AppColorTokens tokens;

  @override
  Widget build(BuildContext context) {
    final bool hasMatches =
        (controller.value?.result?.matches.length ?? 0) > 0;

    return SizedBox(
      height: _rowHeight,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller.replaceInputController,
              focusNode: controller.replaceInputFocusNode,
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: const InputDecoration(
                hintText: 'Replace with',
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          TextButton(
            onPressed: hasMatches ? controller.replaceMatch : null,
            child: const Text('Replace'),
          ),
          TextButton(
            onPressed: hasMatches ? controller.replaceAllMatches : null,
            child: const Text('All'),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// A latching option button. Shows its state with a filled background *and* the
/// semantics toggled flag, never colour alone.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.text,
    required this.active,
    required this.tokens,
    required this.onPressed,
  });

  final String label;
  final String text;
  final bool active;
  final AppColorTokens tokens;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool disabled = onPressed == null;
    return Semantics(
      button: true,
      label: label,
      toggled: active,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onPressed,
          borderRadius: const BorderRadius.all(Radius.circular(4)),
          child: Container(
            width: AppSizes.minTouchTarget - 8,
            height: AppSizes.minTouchTarget - 6,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? tokens.accent : Colors.transparent,
              borderRadius: const BorderRadius.all(Radius.circular(4)),
            ),
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: disabled
                        ? tokens.textMuted.withValues(alpha: 0.4)
                        : active
                            ? tokens.onAccent
                            : tokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.tokens,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final AppColorTokens tokens;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      icon: Icon(icon, size: 18, semanticLabel: label),
      color: tokens.textSecondary,
      disabledColor: tokens.textMuted.withValues(alpha: 0.4),
      visualDensity: VisualDensity.compact,
      // Zero padding with explicit constraints: IconButton's default 8dp inset
      // on four buttons is what overflowed the row on a narrow phone. The
      // 40dp constraint keeps the touch target legal.
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: AppSizes.minTouchTarget,
        minHeight: AppSizes.minTouchTarget - 6,
      ),
      onPressed: onPressed,
    );
  }
}
