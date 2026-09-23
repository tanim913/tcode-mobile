/// Named colour tokens for the application chrome.
///
/// Widgets never write a `Color(0xFF...)` literal. They read a named token from
/// here via `Theme.of(context).extension<AppColorTokens>()`, which means adding
/// a theme is adding one file, and an accessibility audit has one place to look.
///
/// Editor *content* colours live separately in [EditorColorTheme] — the brief
/// requires the two to be independently swappable, so a user can run a light app
/// chrome with a dark editor if they want.
library;

import 'package:flutter/material.dart';

@immutable
class AppColorTokens extends ThemeExtension<AppColorTokens> {
  const AppColorTokens({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.sidebar,
    required this.sidebarActive,
    required this.border,
    required this.borderStrong,
    required this.accent,
    required this.onAccent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.selection,
    required this.hover,
    required this.scrim,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.unsavedIndicator,
    required this.indentGuide,
  });

  /// Deepest layer — behind everything.
  final Color background;

  /// Panels, dialogs, sheets.
  final Color surface;

  /// Menus and anything that floats above [surface].
  final Color surfaceRaised;

  final Color sidebar;

  /// Highlight behind the active file's row in the tree.
  final Color sidebarActive;

  final Color border;
  final Color borderStrong;

  /// Primary brand / action colour.
  final Color accent;
  final Color onAccent;

  final Color textPrimary;
  final Color textSecondary;

  /// Disabled labels, placeholder text, gutter line numbers.
  final Color textMuted;

  final Color selection;
  final Color hover;

  /// Overlay drawn over the editor while the explorer panel is open.
  final Color scrim;

  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  /// The dot shown on a tab with unsaved changes. Paired with a semantics
  /// label so the state never relies on colour alone.
  final Color unsavedIndicator;

  /// Faint vertical rules showing nesting depth in the explorer tree.
  final Color indentGuide;

  @override
  AppColorTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? sidebar,
    Color? sidebarActive,
    Color? border,
    Color? borderStrong,
    Color? accent,
    Color? onAccent,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? selection,
    Color? hover,
    Color? scrim,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? unsavedIndicator,
    Color? indentGuide,
  }) {
    return AppColorTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      sidebar: sidebar ?? this.sidebar,
      sidebarActive: sidebarActive ?? this.sidebarActive,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      selection: selection ?? this.selection,
      hover: hover ?? this.hover,
      scrim: scrim ?? this.scrim,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      unsavedIndicator: unsavedIndicator ?? this.unsavedIndicator,
      indentGuide: indentGuide ?? this.indentGuide,
    );
  }

  @override
  AppColorTokens lerp(covariant AppColorTokens? other, double t) {
    if (other == null) {
      return this;
    }
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColorTokens(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      sidebar: mix(sidebar, other.sidebar),
      sidebarActive: mix(sidebarActive, other.sidebarActive),
      border: mix(border, other.border),
      borderStrong: mix(borderStrong, other.borderStrong),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textMuted: mix(textMuted, other.textMuted),
      selection: mix(selection, other.selection),
      hover: mix(hover, other.hover),
      scrim: mix(scrim, other.scrim),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
      info: mix(info, other.info),
      unsavedIndicator: mix(unsavedIndicator, other.unsavedIndicator),
      indentGuide: mix(indentGuide, other.indentGuide),
    );
  }
}
