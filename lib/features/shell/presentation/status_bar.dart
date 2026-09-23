/// Bottom status bar: cursor position, language, indentation, encoding, line
/// ending, and the unsaved marker.
///
/// It listens to the editor controller directly rather than to app state,
/// because the cursor moves on every keystroke and rebuilding anything larger
/// than this strip at that rate would be wasteful.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/data/models/text_format.dart';
import 'package:re_editor/re_editor.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({
    required this.controller,
    required this.languageLabel,
    required this.indent,
    required this.format,
    required this.isDirty,
    super.key,
  });

  final CodeLineEditingController controller;
  final String languageLabel;
  final IndentStyle indent;
  final TextFormat format;
  final bool isDirty;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;

    return Container(
      height: AppSizes.statusBarHeight,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: <Widget>[
            // Only this piece rebuilds as the cursor moves.
            ValueListenableBuilder<CodeLineEditingValue>(
              valueListenable: controller,
              builder: (BuildContext context, CodeLineEditingValue value, _) {
                final CodeLineSelection selection = value.selection;
                final int line = selection.extentIndex + 1;
                final int column = selection.extentOffset + 1;
                final String selected = selection.isCollapsed
                    ? ''
                    : '  (${controller.selectedText.length} selected)';
                return _Item(
                  label: 'Ln $line, Col $column$selected',
                  tokens: tokens,
                );
              },
            ),
            _Item(label: languageLabel, tokens: tokens),
            _Item(label: indent.label, tokens: tokens),
            _Item(label: format.encoding.label, tokens: tokens),
            _Item(label: format.lineEnding.label, tokens: tokens),
            if (isDirty)
              // An icon plus the word, so "unsaved" never depends on colour.
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.circle, size: 7, color: tokens.unsavedIndicator),
                    const SizedBox(width: 5),
                    Text(
                      'Unsaved',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: tokens.textSecondary),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.label, required this.tokens});

  final String label;
  final AppColorTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: tokens.textSecondary),
      ),
    );
  }
}
