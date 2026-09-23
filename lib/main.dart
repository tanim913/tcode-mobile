/// Entry point.
///
/// Intentionally almost empty. Startup logic lives in `app/bootstrap.dart` and
/// all UI in `app/app.dart`, so this file should never need to change.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/app.dart';
import 'package:pocket_code/app/bootstrap.dart';
import 'package:pocket_code/app/providers.dart';

Future<void> main() async {
  final AppBootstrap startup = await bootstrap();
  runApp(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(startup.settingsRepository),
        initialSettingsProvider.overrideWithValue(startup.settings),
        sessionRepositoryProvider.overrideWithValue(startup.sessionRepository),
        supportStorageProvider.overrideWithValue(startup.supportStorage),
        initialSnippetsProvider.overrideWithValue(startup.snippets),
        initialRecentsProvider.overrideWithValue(startup.recents),
      ],
      child: const TcodeApp(),
    ),
  );
}
