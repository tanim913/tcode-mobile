/// Startup work that must finish before the first frame.
///
/// Loading settings before `runApp` rather than asynchronously inside the
/// widget tree means the app never flashes a default theme and then repaints
/// into the user's chosen one.
library;

import 'package:flutter/widgets.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/snippet.dart';
import 'package:pocket_code/data/repositories/recents_repository.dart';
import 'package:pocket_code/data/repositories/session_repository.dart';
import 'package:pocket_code/data/repositories/settings_repository.dart';
import 'package:pocket_code/data/repositories/snippets_repository.dart';
import 'package:pocket_code/data/repositories/support_storage.dart';
import 'package:pocket_code/services/filesystem/provider_factory.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything resolved during startup, handed to the provider overrides.
class AppBootstrap {
  const AppBootstrap({
    required this.settingsRepository,
    required this.settings,
    this.sessionRepository,
    this.supportStorage,
    this.snippets = const <Snippet>[],
    this.recents = const RecentItems(),
  });

  final SettingsRepository settingsRepository;
  final AppSettings settings;

  /// Null when app-private storage could not be opened. The app still runs;
  /// it just cannot remember the session, which is better than refusing to
  /// start.
  final SessionRepository? sessionRepository;

  /// Null when app-private storage could not be opened, which disables every
  /// feature that keeps its own file: snippets, recent items, file history.
  final SupportStorage? supportStorage;

  /// Loaded before the first frame so the settings screen and the completion
  /// popup both have them synchronously, the same reason settings are.
  final List<Snippet> snippets;

  /// Recent workspaces and files, loaded before the first frame so the welcome
  /// screen can show them without a spinner.
  final RecentItems recents;
}

Future<AppBootstrap> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final SettingsRepository repository = SettingsRepository(prefs);

  SessionRepository? session;
  SupportStorage? storage;
  List<Snippet> snippets = const <Snippet>[];
  RecentItems recents = const RecentItems();
  try {
    final PickedRoot support = await openSupportStorage();
    storage = SupportStorage(
      provider: support.provider,
      rootId: support.rootId,
    );
    session = SessionRepository(
      provider: support.provider,
      supportRootId: support.rootId,
    );
    snippets = await SnippetsRepository(storage).load();
    recents = await RecentsRepository(storage).load();
  } on Object {
    // Storage is unavailable on this platform or this launch. Everything that
    // depends on it is a convenience, never a precondition for starting.
    session = null;
    storage = null;
    snippets = const <Snippet>[];
    recents = const RecentItems();
  }

  return AppBootstrap(
    settingsRepository: repository,
    settings: repository.load(),
    sessionRepository: session,
    supportStorage: storage,
    snippets: snippets,
    recents: recents,
  );
}
