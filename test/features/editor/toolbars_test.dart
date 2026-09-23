/// Widget tests for the bottom toolbar and the coding accessory bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/data/models/accessory_key.dart';
import 'package:pocket_code/features/editor/presentation/toolbars/accessory_bar.dart';
import 'package:pocket_code/features/editor/presentation/toolbars/bottom_toolbar.dart';

import '../../support/harness.dart';

void main() {
  group('bottom toolbar', () {
    testWidgets('renders the primary actions', (WidgetTester tester) async {
      await pumpInApp(
        tester,
        EditorBottomToolbar(
          enabled: EditorToolbarAction.values.toSet(),
          onAction: (_) {},
        ),
      );

      expect(find.byTooltip('Undo'), findsOneWidget);
      expect(find.byTooltip('Find'), findsOneWidget);
      expect(find.byTooltip('Save'), findsOneWidget);
      expect(find.byTooltip('Toggle comment'), findsOneWidget);
    });

    testWidgets('an enabled action is tappable and reports itself', (
      WidgetTester tester,
    ) async {
      EditorToolbarAction? fired;
      await pumpInApp(
        tester,
        EditorBottomToolbar(
          enabled: const <EditorToolbarAction>{EditorToolbarAction.save},
          onAction: (EditorToolbarAction a) => fired = a,
        ),
      );

      await tester.tap(find.byTooltip('Save'));
      await tester.pump();

      expect(fired, EditorToolbarAction.save);
    });

    testWidgets('a disabled action does not fire', (WidgetTester tester) async {
      // Save must be inert on a clean buffer, and disabled rather than hidden
      // so the row does not reflow as you type.
      EditorToolbarAction? fired;
      await pumpInApp(
        tester,
        EditorBottomToolbar(
          enabled: const <EditorToolbarAction>{},
          onAction: (EditorToolbarAction a) => fired = a,
        ),
      );

      expect(find.byTooltip('Save'), findsOneWidget);
      await tester.tap(find.byTooltip('Save'), warnIfMissed: false);
      await tester.pump();

      expect(fired, isNull);
    });

    testWidgets('overflow actions live behind the more menu', (
      WidgetTester tester,
    ) async {
      EditorToolbarAction? fired;
      await pumpInApp(
        tester,
        EditorBottomToolbar(
          enabled: EditorToolbarAction.values.toSet(),
          onAction: (EditorToolbarAction a) => fired = a,
        ),
      );

      expect(find.text('Save all'), findsNothing);
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save all'));
      await tester.pumpAndSettle();
      expect(fired, EditorToolbarAction.saveAll);
    });
  });

  group('accessory bar', () {
    Future<void> pumpBar(
      WidgetTester tester, {
      required void Function(AccessoryKey, {required bool shiftHeld}) onKey,
      void Function(int, {required bool shiftHeld})? onScrub,
      List<AccessoryKey>? keys,
    }) {
      return pumpInApp(
        tester,
        AccessoryBar(
          keys: keys ?? AccessoryKeyLayouts.standard,
          onKey: onKey,
          onScrub: onScrub ?? (int _, {required bool shiftHeld}) {},
        ),
      );
    }

    testWidgets('shows the bracket keys a phone keyboard hides', (
      WidgetTester tester,
    ) async {
      await pumpBar(tester, onKey: (_, {required bool shiftHeld}) {});

      expect(find.text('{'), findsOneWidget);
      expect(find.text('}'), findsOneWidget);
      expect(find.text('Tab'), findsOneWidget);
      expect(find.text('Shift'), findsOneWidget);
    });

    testWidgets('tapping a character key reports it with Shift off', (
      WidgetTester tester,
    ) async {
      AccessoryKey? pressed;
      bool? shift;
      await pumpBar(
        tester,
        onKey: (AccessoryKey k, {required bool shiftHeld}) {
          pressed = k;
          shift = shiftHeld;
        },
      );

      await tester.tap(find.text('{'));
      await tester.pump();

      expect(pressed?.text, '{');
      expect(shift, isFalse);
    });

    testWidgets('Shift latches and then applies to the next arrow', (
      WidgetTester tester,
    ) async {
      final List<bool> shiftStates = <bool>[];
      await pumpBar(
        tester,
        onKey: (AccessoryKey _, {required bool shiftHeld}) =>
            shiftStates.add(shiftHeld),
      );

      // Shift itself is not forwarded — the bar owns the modifier.
      await tester.tap(find.text('Shift'));
      await tester.pump();
      expect(shiftStates, isEmpty);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
      await tester.pump();
      expect(shiftStates, <bool>[true]);
    });

    testWidgets('Shift survives repeated arrows but a character consumes it', (
      WidgetTester tester,
    ) async {
      final List<bool> shiftStates = <bool>[];
      await pumpBar(
        tester,
        onKey: (AccessoryKey _, {required bool shiftHeld}) =>
            shiftStates.add(shiftHeld),
      );

      await tester.tap(find.text('Shift'));
      await tester.pump();

      // Extending a selection several characters must not need Shift re-tapped.
      await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
      await tester.pump();
      expect(shiftStates, <bool>[true, true]);

      // A character key consumes it, so it cannot silently modify a later press.
      await tester.tap(find.text('{'));
      await tester.pump();
      await tester.tap(find.text('}'));
      await tester.pump();
      expect(shiftStates, <bool>[true, true, true, false]);
    });

    testWidgets('Shift toggles off when tapped twice', (
      WidgetTester tester,
    ) async {
      final List<bool> shiftStates = <bool>[];
      await pumpBar(
        tester,
        onKey: (AccessoryKey _, {required bool shiftHeld}) =>
            shiftStates.add(shiftHeld),
      );

      await tester.tap(find.text('Shift'));
      await tester.pump();
      await tester.tap(find.text('Shift'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.keyboard_arrow_right));
      await tester.pump();
      expect(shiftStates, <bool>[false]);
    });

    testWidgets('dragging an arrow scrubs the cursor', (
      WidgetTester tester,
    ) async {
      int total = 0;
      await pumpBar(
        tester,
        onKey: (_, {required bool shiftHeld}) {},
        onScrub: (int steps, {required bool shiftHeld}) => total += steps,
      );

      await tester.drag(
        find.byIcon(Icons.keyboard_arrow_right),
        const Offset(60, 0),
      );
      await tester.pump();

      expect(total, greaterThan(0),
          reason: 'a rightward drag should advance the cursor');
    });

    testWidgets('a custom layout is respected', (WidgetTester tester) async {
      await pumpBar(
        tester,
        onKey: (_, {required bool shiftHeld}) {},
        keys: <AccessoryKey>[
          const AccessoryKey.char('@'),
          const AccessoryKey.char('%'),
        ],
      );

      expect(find.text('@'), findsOneWidget);
      expect(find.text('{'), findsNothing);
    });

    testWidgets('keys are announced by name, and Shift by state', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpBar(tester, onKey: (_, {required bool shiftHeld}) {});

      // A screen reader must say "Left brace", not read the glyph.
      expect(find.bySemanticsLabel('Left brace'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Shift, extends selection'),
        findsOneWidget,
      );

      handle.dispose();
    });
  });
}
