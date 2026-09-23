/// Shared test helpers.
///
/// The point of this file is that a widget test never constructs the whole app
/// to test one screen. It pumps the widget under test inside the same theme and
/// provider scope the real app uses, with fakes injected by overriding a single
/// provider.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/theme/app_theme.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/workspace.dart';
import 'package:pocket_code/data/repositories/settings_repository.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_file_system.dart';

/// Common phone and tablet sizes, so layout tests state their intent by name
/// rather than by a bare number.
abstract final class TestSizes {
  /// A small phone in portrait — the tightest layout the app must survive.
  static const Size phone = Size(390, 844);

  /// Phone in landscape.
  static const Size phoneLandscape = Size(844, 390);

  /// Just past the 840dp breakpoint, where the sidebar docks.
  static const Size tablet = Size(900, 1200);
}

/// Builds a [SettingsRepository] backed by in-memory preferences.
Future<SettingsRepository> fakeSettingsRepository([
  AppSettings? initial,
]) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final SettingsRepository repository = SettingsRepository(prefs);
  if (initial != null) {
    await repository.save(initial);
  }
  return repository;
}

/// Pumps [child] inside the app's real theme and a provider scope.
Future<void> pumpInApp(
  WidgetTester tester,
  Widget child, {
  AppSettings settings = const AppSettings(),
  SettingsRepository? repository,
  Size size = TestSizes.phone,
  Brightness brightness = Brightness.dark,
  double textScale = 1.0,
  List<Override> overrides = const <Override>[],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final SettingsRepository repo = repository ?? await fakeSettingsRepository();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
        initialSettingsProvider.overrideWithValue(settings),
        ...overrides,
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: brightness == Brightness.dark
            ? AppTheme.dark()
            : AppTheme.light(),
        // Applied as a builder so the scale reaches the whole subtree,
        // including anything pushed onto a route above `home`.
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: child,
      ),
    ),
  );
}

/// Builds an [OpenWorkspace] rooted at [rootPath] in [provider], for tests that
/// need the explorer or editor to have something to show.
OpenWorkspace workspaceFor(
  FakeFileSystemProvider provider, {
  String rootPath = '/workspace',
  String name = 'workspace',
}) {
  final WorkspaceRoot root = WorkspaceRoot(
    providerScheme: provider.schemeId,
    rootId: rootPath,
    name: name,
    displayPath: rootPath,
  );
  return OpenWorkspace(
    workspace: Workspace.singleRoot(root),
    roots: <LiveRoot>[LiveRoot(root: root, provider: provider)],
  );
}

/// A [WorkspaceController] pinned to a fixed workspace, so tests do not have to
/// drive a real folder picker.
class FixedWorkspaceController extends WorkspaceController {
  FixedWorkspaceController(this.initial);

  final OpenWorkspace? initial;

  @override
  OpenWorkspace? build() => initial;
}
