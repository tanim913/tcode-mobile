/// The list of suggestions shown beside the caret.
///
/// Must be a [PreferredSizeWidget]: `re_editor` reads [preferredSize] to decide
/// whether to flip the popup above the caret or to its left, so a dishonest
/// size makes it overlap the text it is completing. `find_panel.dart` is the
/// other widget in this app under the same contract.
///
/// **Accepting a suggestion is a tap.** `re_editor` accepts on a
/// `CodeShortcutNewLineIntent`, which only a hardware Enter produces — the soft
/// keyboard's Enter goes through `performAction(TextInputAction.newline)` and
/// is applied directly to the buffer without that intent ever being
/// dispatched. So the rows are real touch targets and nothing in the UI claims
/// Enter will work.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:re_editor/re_editor.dart';

/// Row height, and the popup's width. Rows are a full touch target tall
/// because tapping one is the only way to accept.
const double kCompletionRowHeight = 44;
const double kCompletionWidth = 260;

/// Rows visible before the list scrolls.
const int kCompletionVisibleRows = 5;

double completionPopupHeight(int promptCount) {
  final int rows = promptCount.clamp(0, kCompletionVisibleRows);
  return rows * kCompletionRowHeight + 8;
}

class CompletionPopup extends StatelessWidget implements PreferredSizeWidget {
  const CompletionPopup({
    required this.notifier,
    required this.onSelected,
    super.key,
  });

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  @override
  Size get preferredSize => Size(
        kCompletionWidth,
        completionPopupHeight(notifier.value.prompts.length),
      );

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    return ValueListenableBuilder<CodeAutocompleteEditingValue>(
      valueListenable: notifier,
      builder: (BuildContext context, CodeAutocompleteEditingValue value, _) {
        if (value.prompts.isEmpty) {
          return const SizedBox.shrink();
        }
        return Container(
          width: kCompletionWidth,
          height: completionPopupHeight(value.prompts.length),
          decoration: BoxDecoration(
            // The popup floats over the editor, so it is app chrome and takes
            // its colours from the app tokens rather than the editor theme.
            color: tokens.surfaceRaised,
            border: Border.all(color: tokens.border),
            borderRadius: const BorderRadius.all(Radius.circular(8)),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemExtent: kCompletionRowHeight,
            itemCount: value.prompts.length,
            itemBuilder: (BuildContext context, int index) => _CompletionRow(
              prompt: value.prompts[index],
              input: value.input,
              selected: index == value.index,
              tokens: tokens,
              onTap: () => onSelected(
                value.copyWith(index: index).autocomplete,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CompletionRow extends StatelessWidget {
  const _CompletionRow({
    required this.prompt,
    required this.input,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  final CodePrompt prompt;
  final String input;
  final bool selected;
  final AppColorTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String word = prompt.word;
    final String type = prompt is CodeFieldPrompt
        ? (prompt as CodeFieldPrompt).type
        : '';
    final TextStyle? base = Theme.of(context).textTheme.bodyMedium;

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: type.isEmpty ? word : '$word, $type',
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: selected ? tokens.accent.withValues(alpha: 0.16) : null,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: Row(
            children: <Widget>[
              Expanded(
                child: RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: base?.copyWith(color: tokens.textPrimary),
                    children: <TextSpan>[
                      // The part already typed is emphasised, so the eye can
                      // see what each row would add.
                      TextSpan(
                        text: word.substring(0, input.length.clamp(0, word.length)),
                        style: TextStyle(
                          color: tokens.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: word.substring(input.length.clamp(0, word.length)),
                      ),
                    ],
                  ),
                ),
              ),
              if (type.isNotEmpty) ...<Widget>[
                const SizedBox(width: 8),
                Text(
                  type,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: tokens.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
