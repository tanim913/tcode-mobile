/// The chrome shared by the command palette and Quick Open.
///
/// One place for the sheet, the search field, the result count and the empty
/// state, so the two palettes cannot drift apart in behaviour or in wording.
///
/// A bottom sheet rather than a centred dialog: on a phone the search field has
/// to sit near the keyboard, not behind it. The field is not autofocused —
/// raising the keyboard on open hides most of the list before it can be read.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';

/// Shows [builder] in a palette-shaped modal sheet.
///
/// The sheet is draggable and starts tall, because the first thing a palette
/// must show is a useful number of results.
Future<T?> showPaletteSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext, ScrollController) builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => Padding(
      // Lifts the sheet clear of the keyboard once the field is tapped.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: builder,
      ),
    ),
  );
}

/// Search field, result count, and either the results or an empty state.
class PaletteScaffold extends StatelessWidget {
  const PaletteScaffold({
    required this.controller,
    required this.hintText,
    required this.semanticsLabel,
    required this.onChanged,
    required this.onSubmitted,
    required this.resultCount,
    required this.emptyMessage,
    required this.child,
    this.footer,
    this.loading = false,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;
  final String semanticsLabel;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final int resultCount;

  /// Shown instead of [child] when there is nothing to list.
  final String emptyMessage;

  final Widget child;

  /// Optional line under the list — used to say an index was truncated.
  final Widget? footer;

  /// True while the results are still being gathered. Shown as a spinner rather
  /// than an empty list, which would read as "no matches" when nothing has been
  /// searched yet.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppColorTokens tokens = theme.extension<AppColorTokens>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: <Widget>[
          // Grab handle: the sheet is draggable, and nothing else says so.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: tokens.borderStrong,
                borderRadius: const BorderRadius.all(Radius.circular(2)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Semantics(
              textField: true,
              label: semanticsLabel,
              child: TextField(
                controller: controller,
                // Deliberately not autofocused. Raising the keyboard on open
                // covers most of the list before it has been read, and the
                // list is useful on its own — the whole catalogue is there to
                // browse. The keyboard appears when the field is tapped.
                // (`autofocus` defaults to false; the comment is the point.)
                textInputAction: TextInputAction.go,
                onChanged: onChanged,
                onSubmitted: (_) => onSubmitted(),
                decoration: InputDecoration(
                  hintText: hintText,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (BuildContext context, TextEditingValue value, _) {
                      if (value.text.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: switch ((loading, resultCount)) {
              (true, _) => const Center(child: CircularProgressIndicator()),
              (false, 0) => _Empty(message: emptyMessage, tokens: tokens),
              _ => child,
            },
          ),
          if (footer != null) ...<Widget>[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: DefaultTextStyle.merge(
                style: theme.textTheme.bodySmall
                        ?.copyWith(color: tokens.textMuted) ??
                    const TextStyle(),
                child: footer!,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message, required this.tokens});

  final String message;
  final AppColorTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.search_off, size: 28, color: tokens.textMuted),
            const SizedBox(height: 10),
            Text(
              message,
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

/// Draws [text] with the fuzzy-matched characters emphasised.
///
/// The highlight is what makes a fuzzy ranking legible: without it, a list
/// ordered by an invisible score looks arbitrary.
class HighlightedText extends StatelessWidget {
  const HighlightedText({
    required this.text,
    required this.indices,
    required this.highlightColour,
    this.style,
    super.key,
  });

  final String text;

  /// Ascending indices into [text], as produced by `FuzzyMatcher`.
  final List<int> indices;

  final Color highlightColour;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (indices.isEmpty) {
      return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }

    final Set<int> hit = indices.toSet();
    final List<TextSpan> spans = <TextSpan>[];
    final StringBuffer run = StringBuffer();
    bool? runIsHit;

    void flush() {
      if (run.isEmpty) {
        return;
      }
      spans.add(
        TextSpan(
          text: run.toString(),
          style: runIsHit ?? false
              ? TextStyle(color: highlightColour, fontWeight: FontWeight.w700)
              : null,
        ),
      );
      run.clear();
    }

    for (int i = 0; i < text.length; i++) {
      final bool isHit = hit.contains(i);
      if (runIsHit != isHit) {
        flush();
        runIsHit = isHit;
      }
      run.write(text[i]);
    }
    flush();

    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Row height shared by both palettes, so the two lists scroll identically.
const double kPaletteRowHeight = AppSizes.primaryTouchTarget;
