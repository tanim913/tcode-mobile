/// Verifies the shell shows the right bar for the keyboard state.
///
/// Driven by `tester.view.viewInsets`, which is what the real platform sets
/// when the soft keyboard opens — the same signal the shell reads.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/theme/app_theme.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/features/editor/presentation/toolbars/accessory_bar.dart';
import 'package:pocket_code/features/editor/presentation/toolbars/bottom_toolbar.dart';
import 'package:pocket_code/features/shell/presentation/editor_shell.dart';
import 'package:pocket_code/features/tabs/application/tabs_controller.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';

import '../../support/fake_file_system.dart';
import '../../support/harness.dart';

FakeFileSystemProvider seeded() => FakeFileSystemProvider()
  ..seed(<String, String>{'/workspace/main.dart': 'void main() {}\n'});

/// Pumps the shell with one file already open, optionally with the keyboard up.
Future<ProviderContainer> pumpShell(
  WidgetTester tester, {
  bool keyboardVisible = false,
  AppSettings settings = const AppSettings(),
}) async {
  final FakeFileSystemProvider provider = seeded();
  final repo = await fakeSettingsRepository();

  tester.view.physicalSize = TestSizes.phone;
  tester.view.devicePixelRatio = 1.0;
  if (keyboardVisible) {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  }
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);

  final ProviderContainer container = ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(repo),
      initialSettingsProvider.overrideWithValue(settings),
      workspaceProvider.overrideWith(
        () => FixedWorkspaceController(workspaceFor(provider)),
      ),
    ],
  );
  addTearDown(container.dispose);

  await container.read(tabsProvider.notifier).open(
        const FileNode(
          id: '/workspace/main.dart',
          name: 'main.dart',
          displayPath: '/workspace/main.dart',
        ),
        0,
      );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        // The shell reads AppColorTokens off the theme, an invariant every app
        // theme upholds (asserted in test/core/theme_test.dart), so the test
        // must supply a real app theme rather than Material's default.
        theme: AppTheme.dark(),
        home: const EditorShell(),
      ),
    ),
  );
  await tester.pump();
  return container;
}

/// Tears the shell down inside the test body.
///
/// Two timers have to be drained first, and the framework fails any test that
/// ends with one pending: re_editor's cursor blink, and the auto-save debounce
/// that any edit starts (1000ms by default). `addTearDown` runs after that
/// check, so the teardown has to be explicit.
Future<void> disposeShell(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1200));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  group('bar swapping', () {
    testWidgets('keyboard hidden shows the bottom toolbar', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      expect(find.byType(EditorBottomToolbar), findsOneWidget);
      expect(find.byType(AccessoryBar), findsNothing);
      await disposeShell(tester);
    });

    testWidgets('keyboard visible swaps in the accessory bar', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester, keyboardVisible: true);

      expect(find.byType(AccessoryBar), findsOneWidget);
      expect(
        find.byType(EditorBottomToolbar),
        findsNothing,
        reason: 'both at once would eat a third of a phone screen',
      );
      await disposeShell(tester);
    });

    testWidgets('the accessory bar honours its setting', (
      WidgetTester tester,
    ) async {
      // This is the toggle that previously controlled nothing.
      await pumpShell(
        tester,
        keyboardVisible: true,
        settings: const AppSettings(showAccessoryBar: false),
      );

      expect(find.byType(AccessoryBar), findsNothing);
      expect(find.byType(EditorBottomToolbar), findsNothing);
      await disposeShell(tester);
    });

    testWidgets('a dialog owning the keyboard hides the accessory bar', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester, keyboardVisible: true);
      expect(find.byType(AccessoryBar), findsOneWidget);

      // Go to line and the close prompts all put a text field in a dialog. The
      // keyboard is then the dialog's, and the editor's bracket keys sitting
      // behind the modal barrier are unreachable and aimed at the wrong buffer.
      final BuildContext context = tester.element(find.byType(EditorShell));
      unawaited(showDialog<void>(
        context: context,
        builder: (BuildContext context) => const AlertDialog(
          content: TextField(autofocus: true),
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.byType(AccessoryBar),
        findsNothing,
        reason: 'the shell is no longer the current route',
      );

      Navigator.of(context, rootNavigator: true).pop();
      await tester.pumpAndSettle();
      expect(find.byType(AccessoryBar), findsOneWidget,
          reason: 'dismissing the dialog gives the keys back to the editor');
      await disposeShell(tester);
    });
  });

  group('contextual toolbar state', () {
    testWidgets('Save is disabled on a clean buffer', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      final IconButton save = tester.widget<IconButton>(
        find.descendant(
          of: find.byType(EditorBottomToolbar),
          matching: find.widgetWithIcon(IconButton, Icons.save_outlined),
        ),
      );
      expect(save.onPressed, isNull);
      await disposeShell(tester);
    });

    testWidgets('Save becomes available once the buffer is dirty', (
      WidgetTester tester,
    ) async {
      final ProviderContainer c = await pumpShell(tester);

      final tabs = c.read(tabsProvider.notifier);
      tabs.controllerFor(c.read(tabsProvider).active!).text = 'edited';
      await tester.pump();

      final IconButton save = tester.widget<IconButton>(
        find.descendant(
          of: find.byType(EditorBottomToolbar),
          matching: find.widgetWithIcon(IconButton, Icons.save_outlined),
        ),
      );
      expect(save.onPressed, isNotNull);
      await disposeShell(tester);
    });

    testWidgets('Undo is disabled with no history', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      final IconButton undo = tester.widget<IconButton>(
        find.descendant(
          of: find.byType(EditorBottomToolbar),
          matching: find.widgetWithIcon(IconButton, Icons.undo),
        ),
      );
      expect(undo.onPressed, isNull);
      await disposeShell(tester);
    });
  });
}
