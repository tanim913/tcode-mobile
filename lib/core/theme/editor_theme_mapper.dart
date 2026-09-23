/// Translates our [EditorColorTheme] and [EditorSettings] into the style
/// objects `re_editor` expects.
///
/// This is the only file that knows `re_editor`'s type names for theming. If
/// the editor engine is ever swapped, this file and the editor widget change;
/// the themes themselves do not.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/core/theme/editor_color_theme.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/services/language/language_definition.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/re_highlight.dart';

abstract final class EditorThemeMapper {
  /// Colours, font and cursor for the editor surface.
  ///
  /// [showCaret] is false for a read-only document. `re_editor` keeps a live,
  /// movable caret when `readOnly` is set — which is what makes Copy work — but
  /// a blinking caret in a locked file reads as "you can type here". Hiding the
  /// caret alone says "locked" without taking selection and copy away.
  static CodeEditorStyle styleFor({
    required EditorColorTheme theme,
    required EditorSettings settings,
    required LanguageDefinition language,
    bool showCaret = true,
  }) {
    return CodeEditorStyle(
      fontSize: settings.fontSize,
      fontFamily: settings.fontFamily.family,
      // Always fall back to a real monospace face. A proportional fallback
      // would silently break column alignment, which is worse than ugly.
      fontFamilyFallback: const <String>['JetBrains Mono', 'monospace'],
      fontHeight: settings.lineHeight,
      textColor: theme.foreground,
      backgroundColor: theme.background,
      selectionColor: theme.selection,
      cursorColor: showCaret ? theme.cursor : Colors.transparent,
      cursorLineColor:
          settings.highlightCurrentLine ? theme.currentLine : Colors.transparent,
      chunkIndicatorColor: theme.gutterText,
      codeTheme: highlightFor(theme: theme, language: language),
    );
  }

  /// Syntax rules plus colours for one language.
  ///
  /// Only the file's own language is registered. Registering all 27 would make
  /// `re_editor` consider every grammar on each highlight pass.
  static CodeHighlightTheme? highlightFor({
    required EditorColorTheme theme,
    required LanguageDefinition language,
  }) {
    final Mode? mode = language.mode;
    if (mode == null) {
      // Plain text: no highlighting, which renders faster and is honest.
      return null;
    }
    return CodeHighlightTheme(
      languages: <String, CodeHighlightThemeMode>{
        language.id: CodeHighlightThemeMode(
          mode: mode,
          // Above these, re_editor stops highlighting rather than stalling.
          // Aligned with our own large-file and long-line thresholds so the
          // editor and the UI agree about when highlighting is off.
          maxSize: AppLimits.readOnlyFileSizeBytes,
          maxLineLength: AppLimits.longLineCharacters,
        ),
      },
      theme: theme.syntax,
    );
  }

  /// Text style for the line-number gutter.
  static TextStyle gutterStyle(EditorColorTheme theme, EditorSettings settings) {
    return TextStyle(
      fontSize: settings.fontSize,
      height: settings.lineHeight,
      fontFamily: settings.fontFamily.family,
      color: theme.gutterText,
    );
  }

  /// Gutter style for the line the cursor is on.
  static TextStyle gutterActiveStyle(
    EditorColorTheme theme,
    EditorSettings settings,
  ) {
    return gutterStyle(theme, settings).copyWith(color: theme.gutterActiveText);
  }

  /// Disables programming ligatures through the OpenType `calt` feature rather
  /// than by swapping to a different font file, which keeps the metrics — and
  /// therefore the cursor position — identical.
  static List<FontFeature> fontFeatures(EditorSettings settings) {
    return settings.ligatures
        ? const <FontFeature>[]
        : const <FontFeature>[FontFeature.disable('calt')];
  }
}
