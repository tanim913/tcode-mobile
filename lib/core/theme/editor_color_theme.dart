/// Colour theme for editor *content*, kept separate from the app chrome theme.
///
/// The brief requires editor themes to be addable as single files, so this is a
/// plain data class plus a registry — no switch statements to update.
///
/// [syntax] uses highlight.js scope names ('keyword', 'string', 'comment', …)
/// because that is what re_highlight emits. Any scope not listed falls back to
/// [foreground], so a partial theme still renders sensibly.
library;

import 'package:flutter/material.dart';

@immutable
class EditorColorTheme {
  const EditorColorTheme({
    required this.id,
    required this.name,
    required this.isDark,
    required this.background,
    required this.foreground,
    required this.gutterBackground,
    required this.gutterText,
    required this.gutterActiveText,
    required this.currentLine,
    required this.selection,
    required this.cursor,
    required this.bracketMatch,
    required this.findMatch,
    required this.findMatchActive,
    required this.indentGuide,
    required this.whitespace,
    required this.syntax,
  });

  /// Stable key used when persisting the user's choice.
  final String id;

  /// Shown in settings.
  final String name;

  /// Lets the app pick a sensible default editor theme for the current app
  /// brightness without the user having to choose twice.
  final bool isDark;

  final Color background;
  final Color foreground;
  final Color gutterBackground;
  final Color gutterText;

  /// Line number of the line the cursor is on.
  final Color gutterActiveText;

  final Color currentLine;
  final Color selection;
  final Color cursor;

  /// Outline drawn around a bracket and its partner.
  final Color bracketMatch;

  final Color findMatch;
  final Color findMatchActive;
  final Color indentGuide;

  /// Dots and arrows drawn when "render whitespace" is on.
  final Color whitespace;

  final Map<String, TextStyle> syntax;
}
