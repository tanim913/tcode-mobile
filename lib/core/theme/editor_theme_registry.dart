/// Registry of every available editor colour theme.
///
/// Adding a theme is: create one file under `editor_themes/`, add one line to
/// [all]. Nothing else in the app needs to change.
library;

import 'package:pocket_code/core/theme/editor_color_theme.dart';
import 'package:pocket_code/core/theme/editor_themes/ember_dark.dart';
import 'package:pocket_code/core/theme/editor_themes/pocket_dark.dart';
import 'package:pocket_code/core/theme/editor_themes/pocket_light.dart';

abstract final class EditorThemeRegistry {
  static const List<EditorColorTheme> all = <EditorColorTheme>[
    pocketDarkEditorTheme,
    emberDarkEditorTheme,
    pocketLightEditorTheme,
  ];

  static const String defaultDarkId = 'pocket-dark';
  static const String defaultLightId = 'pocket-light';

  /// Looks up a theme by its persisted id.
  ///
  /// Falls back rather than throwing: a settings file naming a theme that was
  /// removed in a later version must not stop the app from starting.
  static EditorColorTheme byId(String id, {required bool preferDark}) {
    for (final EditorColorTheme theme in all) {
      if (theme.id == id) {
        return theme;
      }
    }
    return preferDark ? pocketDarkEditorTheme : pocketLightEditorTheme;
  }

  static List<EditorColorTheme> matching({required bool isDark}) =>
      all.where((EditorColorTheme t) => t.isDark == isDark).toList();
}
