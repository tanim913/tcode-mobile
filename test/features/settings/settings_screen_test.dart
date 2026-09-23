/// Smoke and behaviour tests for the settings screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/repositories/settings_repository.dart';
import 'package:pocket_code/features/settings/presentation/settings_screen.dart';

import '../../support/harness.dart';

void main() {
  group('rendering', () {
    testWidgets('opens without overflow on a phone', (
      WidgetTester tester,
    ) async {
      await pumpInApp(tester, const SettingsScreen());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Settings'), findsWidgets);
    });

    testWidgets('renders at tablet width', (WidgetTester tester) async {
      await pumpInApp(tester, const SettingsScreen(), size: TestSizes.tablet);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in the light theme', (WidgetTester tester) async {
      await pumpInApp(
        tester,
        const SettingsScreen(),
        brightness: Brightness.light,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a large system text scale', (
      WidgetTester tester,
    ) async {
      // Accessibility requirement: UI text respects the system scale without
      // breaking the layout.
      await pumpInApp(tester, const SettingsScreen(), textScale: 1.8);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('search', () {
    testWidgets('typing narrows the visible settings', (
      WidgetTester tester,
    ) async {
      await pumpInApp(tester, const SettingsScreen());
      await tester.pumpAndSettle();

      // Asserted by comparing two searches rather than against the unfiltered
      // screen: the list is lazily built, so an unsearched setting may simply
      // be below the fold rather than filtered out.
      await tester.enterText(find.byType(TextField).first, 'word wrap');
      await tester.pumpAndSettle();
      expect(find.text('Word wrap'), findsWidgets);
      expect(find.text('Confirm deletion'), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'confirm deletion');
      await tester.pumpAndSettle();
      expect(find.text('Confirm deletion'), findsWidgets);
      expect(find.text('Word wrap'), findsNothing);
    });

    testWidgets('clearing the query drops the result summary', (
      WidgetTester tester,
    ) async {
      await pumpInApp(tester, const SettingsScreen());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'confirm deletion');
      await tester.pumpAndSettle();
      expect(find.textContaining('confirm deletion'), findsWidgets);

      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();

      // Back to the full screen: the Editor group header is the first row, so
      // it is always built regardless of scroll position.
      expect(find.text('Editor'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a query matching nothing says so', (
      WidgetTester tester,
    ) async {
      await pumpInApp(tester, const SettingsScreen());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'zzzznotasetting');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // An empty state must invite the next action rather than showing a blank.
      expect(find.textContaining('No settings'), findsWidgets);
    });
  });

  group('persistence', () {
    testWidgets('toggling a setting writes it through the repository', (
      WidgetTester tester,
    ) async {
      final SettingsRepository repo = await fakeSettingsRepository();
      await pumpInApp(tester, const SettingsScreen(), repository: repo);
      await tester.pumpAndSettle();

      // "Confirm deletion" defaults to on; searching for it isolates the row.
      await tester.enterText(find.byType(TextField).first, 'confirm deletion');
      await tester.pumpAndSettle();

      final Finder toggle = find.byType(Switch).first;
      await tester.tap(toggle, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      final AppSettings saved = repo.load();
      expect(
        saved.confirmDelete,
        isFalse,
        reason: 'there is no Save button, so the change must already be stored',
      );
    });
  });
}
