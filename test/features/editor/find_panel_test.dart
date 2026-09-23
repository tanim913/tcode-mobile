/// Tests for the find and replace panel.
///
/// **Scope note.** `re_editor` runs match finding on a spawned isolate via
/// `isolate_manager`, and those results never arrive under `flutter_test` —
/// not a timing problem, the callback simply does not fire. So this file tests
/// what it genuinely can: the match-count label (extracted as a pure
/// function), panel rendering, the option toggles' wiring, read-only
/// behaviour, and closing. Live searching is verified on a device.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/features/editor/presentation/find_panel.dart';
import 'package:re_editor/re_editor.dart';

import '../../support/harness.dart';

class FindHarness {
  FindHarness(String text) : editing = CodeLineEditingController.fromText(text) {
    find = CodeFindController(editing);
  }

  final CodeLineEditingController editing;
  late final CodeFindController find;

  void dispose() {
    find.dispose();
    editing.dispose();
  }
}

Future<FindHarness> pumpPanel(
  WidgetTester tester,
  String text, {
  bool readOnly = false,
  bool replaceMode = false,
}) async {
  final FindHarness h = FindHarness(text);
  addTearDown(h.dispose);
  if (replaceMode) {
    h.find.replaceMode();
  } else {
    h.find.findMode();
  }

  await pumpInApp(
    tester,
    Scaffold(body: FindPanel(controller: h.find, readOnly: readOnly)),
  );
  await tester.pump();
  return h;
}

void main() {
  group('match count label', () {
    test('an empty query shows nothing at all', () {
      expect(
        matchCountLabel(
          query: '',
          matchCount: 0,
          currentIndex: 0,
          searching: false,
        ),
        '',
      );
    });

    test('reports position and total, one-based', () {
      // The engine's index is zero-based; users count from one.
      expect(
        matchCountLabel(
          query: 'cat',
          matchCount: 17,
          currentIndex: 2,
          searching: false,
        ),
        '3 of 17',
      );
    });

    test('the first match reads "1 of n", never "0 of n"', () {
      expect(
        matchCountLabel(
          query: 'cat',
          matchCount: 3,
          currentIndex: 0,
          searching: false,
        ),
        '1 of 3',
      );
    });

    test('a query with no matches says so', () {
      expect(
        matchCountLabel(
          query: 'zebra',
          matchCount: 0,
          currentIndex: 0,
          searching: false,
        ),
        'No results',
      );
    });

    test('searching wins over everything else', () {
      // Otherwise a large file would flash "No results" mid-search.
      expect(
        matchCountLabel(
          query: 'cat',
          matchCount: 0,
          currentIndex: 0,
          searching: true,
        ),
        'Searching…',
      );
    });
  });

  group('rendering', () {
    testWidgets('shows the find field and its option toggles', (
      WidgetTester tester,
    ) async {
      await pumpPanel(tester, 'hello world');

      expect(find.text('Find'), findsOneWidget);
      expect(find.byTooltip('Match case'), findsOneWidget);
      expect(find.byTooltip('Whole word'), findsOneWidget);
      expect(find.byTooltip('Regular expression'), findsOneWidget);
      expect(find.byTooltip('Next match'), findsOneWidget);
      expect(find.byTooltip('Previous match'), findsOneWidget);
    });

    testWidgets('fits a phone width without overflowing', (
      WidgetTester tester,
    ) async {
      // The row is tight: text field, count, three toggles and four actions.
      await pumpPanel(tester, 'hello');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a read-only document is offered no replace', (
      WidgetTester tester,
    ) async {
      // Offering replace on a buffer that cannot be edited would be a lie.
      await pumpPanel(tester, 'hello', readOnly: true);

      expect(find.byTooltip('Show replace'), findsNothing);
      expect(find.text('Replace with'), findsNothing);
    });

    testWidgets('replace mode adds the replace row', (
      WidgetTester tester,
    ) async {
      await pumpPanel(tester, 'hello', replaceMode: true);

      expect(find.text('Replace with'), findsOneWidget);
      expect(find.text('Replace'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
    });
  });

  group('options', () {
    testWidgets('match case toggles the engine option', (
      WidgetTester tester,
    ) async {
      final FindHarness h = await pumpPanel(tester, 'Cat cat');
      expect(h.find.value?.option.caseSensitive, isFalse);

      await tester.tap(find.byTooltip('Match case'));
      await tester.pump();

      expect(h.find.value?.option.caseSensitive, isTrue);
    });

    testWidgets('regex toggles the engine option', (
      WidgetTester tester,
    ) async {
      final FindHarness h = await pumpPanel(tester, 'cat');
      expect(h.find.value?.option.regex, isFalse);

      await tester.tap(find.byTooltip('Regular expression'));
      await tester.pump();

      expect(h.find.value?.option.regex, isTrue);
    });

    testWidgets('whole word writes an escaped \\b pattern into the engine', (
      WidgetTester tester,
    ) async {
      // This is the whole mechanism: the visible field keeps the user's text,
      // and the transformed pattern is mirrored into the controller.
      final FindHarness h = await pumpPanel(tester, 'a.c abc');
      await tester.enterText(find.byType(TextField).first, 'a.c');
      await tester.pump();
      expect(h.find.findInputController.text, 'a.c');

      await tester.tap(find.byTooltip('Whole word'));
      await tester.pump();

      expect(h.find.findInputController.text, r'\ba\.c\b',
          reason: 'the dot must be escaped, or it would match "abc" too');
      expect(h.find.value?.option.regex, isTrue,
          reason: 'whole word is implemented as a regex');
    });

    testWidgets('the visible field never shows the transform', (
      WidgetTester tester,
    ) async {
      await pumpPanel(tester, 'cat');
      await tester.enterText(find.byType(TextField).first, 'cat');
      await tester.pump();
      await tester.tap(find.byTooltip('Whole word'));
      await tester.pump();

      expect(find.text('cat'), findsOneWidget);
      expect(find.text(r'\bcat\b'), findsNothing);
    });

    testWidgets('turning whole word off restores the plain pattern', (
      WidgetTester tester,
    ) async {
      final FindHarness h = await pumpPanel(tester, 'cat catalog');
      await tester.enterText(find.byType(TextField).first, 'cat');
      await tester.pump();

      await tester.tap(find.byTooltip('Whole word'));
      await tester.pump();
      expect(h.find.findInputController.text, r'\bcat\b');

      await tester.tap(find.byTooltip('Whole word'));
      await tester.pump();
      expect(h.find.findInputController.text, 'cat');
      expect(h.find.value?.option.regex, isFalse);
    });

    testWidgets('whole word is refused while a raw regex is active', (
      WidgetTester tester,
    ) async {
      // The two cannot coexist coherently, so the UI declines rather than
      // silently mangling the user's regex.
      final FindHarness h = await pumpPanel(tester, 'cat');
      await tester.enterText(find.byType(TextField).first, 'c.t');
      await tester.pump();

      await tester.tap(find.byTooltip('Regular expression'));
      await tester.pump();

      await tester.tap(find.byTooltip('Whole word'));
      await tester.pump();

      expect(h.find.findInputController.text, 'c.t',
          reason: 'the hand-written regex must be left alone');
    });
  });

  group('option indicators', () {
    testWidgets('whole word does not light the regex button', (
      WidgetTester tester,
    ) async {
      // Whole word turns the engine's regex flag on internally. Showing the
      // regex toggle lit would tell the user they chose something they did not.
      final FindHarness h = await pumpPanel(tester, 'cat catalog');
      await tester.enterText(find.byType(TextField).first, 'cat');
      await tester.pump();

      await tester.tap(find.byTooltip('Whole word'));
      await tester.pump();

      expect(h.find.value?.option.regex, isTrue,
          reason: 'the engine really is in regex mode');

      // Locate our own Semantics by its label; the ancestor chain contains
      // several the framework inserts, which carry no toggled flag.
      final Semantics regexButton = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .firstWhere(
            (Semantics s) =>
                s.properties.label == 'Regular expression',
          );
      expect(
        regexButton.properties.toggled,
        isFalse,
        reason: 'but the button must not claim the user enabled it',
      );
    });
  });

  group('closing', () {
    testWidgets('the close button dismisses the panel', (
      WidgetTester tester,
    ) async {
      final FindHarness h = await pumpPanel(tester, 'cat');

      await tester.tap(find.byTooltip('Close find'));
      await tester.pump();

      expect(h.find.value, isNull);
    });
  });
}
