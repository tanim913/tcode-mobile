/// Reads and writes [AppSettings].
///
/// Settings live in `shared_preferences` as a single JSON blob rather than one
/// key per field. That keeps a save atomic — settings can never be half-written
/// — and means adding a setting needs no migration.
///
/// Larger, structured state (workspaces, sessions, recent history) goes to JSON
/// files in the app support directory instead; `shared_preferences` is the wrong
/// tool for anything that grows.
library;

import 'dart:convert';

import 'package:pocket_code/data/models/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  const SettingsRepository(this._prefs);

  static const String _key = 'app_settings_v1';

  final SharedPreferences _prefs;

  AppSettings load() {
    final String? raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return const AppSettings();
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return AppSettings.fromJson(decoded);
      }
    } on FormatException {
      // Corrupt settings must not stop the app from starting. Fall back to
      // defaults; the next save overwrites the bad value.
    }
    return const AppSettings();
  }

  Future<void> save(AppSettings settings) async {
    await _prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}
