/// Concrete colour values for each app theme.
///
/// This is the only file in the app allowed to contain colour literals.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';

abstract final class AppPalettes {
  /// Default. A deep, slightly blue-black that reads as a tool rather than a
  /// document — pure #000 makes OLED smearing obvious while scrolling code.
  static const AppColorTokens dark = AppColorTokens(
    background: Color(0xFF12141A),
    surface: Color(0xFF181B22),
    surfaceRaised: Color(0xFF212530),
    sidebar: Color(0xFF15171D),
    sidebarActive: Color(0xFF232937),
    border: Color(0xFF262A33),
    borderStrong: Color(0xFF39404D),
    accent: Color(0xFF4D9FFF),
    onAccent: Color(0xFF06121F),
    textPrimary: Color(0xFFE3E6EC),
    textSecondary: Color(0xFF9AA3B2),
    textMuted: Color(0xFF5C6577),
    selection: Color(0xFF2A4A6B),
    hover: Color(0xFF1E2028),
    scrim: Color(0xFF000000),
    success: Color(0xFF5FD08A),
    warning: Color(0xFFE0B054),
    danger: Color(0xFFF4707E),
    info: Color(0xFF56B6C2),
    unsavedIndicator: Color(0xFFE3E6EC),
    indentGuide: Color(0xFF2A2F3A),
  );

  static const AppColorTokens light = AppColorTokens(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF6F7F9),
    surfaceRaised: Color(0xFFFFFFFF),
    sidebar: Color(0xFFF2F3F6),
    sidebarActive: Color(0xFFDDE7F5),
    border: Color(0xFFE1E4EA),
    borderStrong: Color(0xFFC4CAD4),
    accent: Color(0xFF0B62D0),
    onAccent: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1B1F27),
    textSecondary: Color(0xFF57606F),
    textMuted: Color(0xFF8A93A1),
    selection: Color(0xFFBFD9F7),
    hover: Color(0xFFEBEDF1),
    scrim: Color(0xFF0A0D12),
    success: Color(0xFF1A7F45),
    warning: Color(0xFF9A6400),
    danger: Color(0xFFC0293B),
    info: Color(0xFF0B6B78),
    unsavedIndicator: Color(0xFF1B1F27),
    indentGuide: Color(0xFFDDE0E6),
  );

  /// Maximum separation between foreground and background, stronger borders,
  /// and no low-contrast muted text. For users who need it, not a style.
  static const AppColorTokens highContrast = AppColorTokens(
    background: Color(0xFF000000),
    surface: Color(0xFF000000),
    surfaceRaised: Color(0xFF0D0D0D),
    sidebar: Color(0xFF000000),
    sidebarActive: Color(0xFF00397A),
    border: Color(0xFF6E6E6E),
    borderStrong: Color(0xFFFFFFFF),
    accent: Color(0xFF63B9FF),
    onAccent: Color(0xFF000000),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFE0E0E0),
    textMuted: Color(0xFFB8B8B8),
    selection: Color(0xFF005A9E),
    hover: Color(0xFF1F1F1F),
    scrim: Color(0xFF000000),
    success: Color(0xFF4BE08B),
    warning: Color(0xFFFFD264),
    danger: Color(0xFFFF8A94),
    info: Color(0xFF70DCE8),
    unsavedIndicator: Color(0xFFFFFFFF),
    indentGuide: Color(0xFF6E6E6E),
  );
}
