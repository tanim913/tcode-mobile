/// Pinch-to-zoom: the maths, and the promise that one finger is left alone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/core/theme/app_theme.dart';
import 'package:pocket_code/features/editor/presentation/pinch_zoom.dart';

Widget harness({
  required double fontSize,
  required ValueChanged<double> onCommit,
}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(
      body: PinchZoom(
        fontSize: fontSize,
        onCommit: onCommit,
        enabled: true,
        child: const SizedBox.expand(child: ColoredBox(color: Colors.black)),
      ),
    ),
  );
}

void main() {
  group('zoomedFontSize', () {
    test('scales and rounds to whole points', () {
      expect(zoomedFontSize(14, 2.0), 28);
      expect(zoomedFontSize(14, 0.5), 7 > AppLimits.minFontSize ? 7 : AppLimits.minFontSize);
      expect(zoomedFontSize(14, 1.07), 15, reason: '14.98 rounds to 15');
    });

    test('clamps to the range the settings screen enforces', () {
      expect(zoomedFontSize(14, 100), AppLimits.maxFontSize);
      expect(zoomedFontSize(14, 0.001), AppLimits.minFontSize);
    });

    test('a scale of 1 changes nothing', () {
      expect(zoomedFontSize(14, 1.0), 14);
    });
  });

  group('gesture', () {
    testWidgets('a one-finger drag does not zoom', (WidgetTester tester) async {
      double? committed;
      await tester.pumpWidget(
        harness(fontSize: 14, onCommit: (double v) => committed = v),
      );

      // This is the scroll gesture. If zoom claimed it, the editor could never
      // be scrolled again.
      await tester.drag(find.byType(PinchZoom), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(committed, isNull,
          reason: 'one pointer is scrolling, selecting or tapping — never zoom');
    });

    testWidgets('a two-finger pinch commits once, on release', (
      WidgetTester tester,
    ) async {
      final List<double> commits = <double>[];
      await tester.pumpWidget(
        harness(fontSize: 14, onCommit: commits.add),
      );

      final Offset centre = tester.getCenter(find.byType(PinchZoom));
      final TestGesture a =
          await tester.startGesture(centre - const Offset(20, 0));
      final TestGesture b =
          await tester.startGesture(centre + const Offset(20, 0));
      await tester.pump();

      // Spread the fingers to roughly double the span.
      await a.moveTo(centre - const Offset(40, 0));
      await b.moveTo(centre + const Offset(40, 0));
      await tester.pump();

      expect(commits, isEmpty,
          reason: 'reflowing a large buffer every frame would drop frames');

      await a.up();
      await b.up();
      await tester.pumpAndSettle();

      expect(commits, hasLength(1), reason: 'one reflow, on release');
      expect(commits.single, greaterThan(14));
    });

    testWidgets('pinching inward makes the font smaller', (
      WidgetTester tester,
    ) async {
      final List<double> commits = <double>[];
      await tester.pumpWidget(harness(fontSize: 24, onCommit: commits.add));

      final Offset centre = tester.getCenter(find.byType(PinchZoom));
      // Start wide, squeeze together — the zoom-out direction.
      final TestGesture a =
          await tester.startGesture(centre - const Offset(120, 0));
      final TestGesture b =
          await tester.startGesture(centre + const Offset(120, 0));
      await tester.pump();

      await a.moveTo(centre - const Offset(30, 0));
      await b.moveTo(centre + const Offset(30, 0));
      await tester.pump();

      await a.up();
      await b.up();
      await tester.pumpAndSettle();

      expect(commits, hasLength(1), reason: 'one reflow, on release');
      expect(commits.single, lessThan(24),
          reason: 'squeezing must shrink the text, not only grow it');
    });

    testWidgets('shows a live badge while pinching, and hides it after', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(harness(fontSize: 14, onCommit: (_) {}));

      final Offset centre = tester.getCenter(find.byType(PinchZoom));
      final TestGesture a =
          await tester.startGesture(centre - const Offset(20, 0));
      final TestGesture b =
          await tester.startGesture(centre + const Offset(20, 0));
      await tester.pump();
      await a.moveTo(centre - const Offset(40, 0));
      await b.moveTo(centre + const Offset(40, 0));
      await tester.pump();

      expect(find.textContaining('pt'), findsOneWidget);

      await a.up();
      await b.up();
      await tester.pumpAndSettle();

      expect(find.textContaining('pt'), findsNothing,
          reason: 'the badge belongs to the gesture, not the screen');
    });

    testWidgets('a pinch back to the same size commits nothing', (
      WidgetTester tester,
    ) async {
      final List<double> commits = <double>[];
      await tester.pumpWidget(harness(fontSize: 14, onCommit: commits.add));

      final Offset centre = tester.getCenter(find.byType(PinchZoom));
      final TestGesture a =
          await tester.startGesture(centre - const Offset(20, 0));
      final TestGesture b =
          await tester.startGesture(centre + const Offset(20, 0));
      await tester.pump();
      await a.moveTo(centre - const Offset(40, 0));
      await b.moveTo(centre + const Offset(40, 0));
      await tester.pump();
      await a.moveTo(centre - const Offset(20, 0));
      await b.moveTo(centre + const Offset(20, 0));
      await tester.pump();
      await a.up();
      await b.up();
      await tester.pumpAndSettle();

      expect(commits, isEmpty,
          reason: 'no change means no settings write and no reflow');
    });

    testWidgets('a second finger cancels the drag underneath', (
      WidgetTester tester,
    ) async {
      // The bug this guards: a passive listener let `re_editor`'s own pan
      // recogniser keep dragging a text selection while the pinch ran, so
      // zooming also smeared a selection across the file. The second finger
      // must take the gesture away from whatever is underneath.
      final List<String> drag = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: PinchZoom(
              fontSize: 14,
              enabled: true,
              onCommit: _noop,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (DragStartDetails _) => drag.add('start'),
                onPanUpdate: (DragUpdateDetails _) => drag.add('update'),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );

      final Offset centre = tester.getCenter(find.byType(PinchZoom));
      final TestGesture a =
          await tester.startGesture(centre - const Offset(30, 0));
      final TestGesture b =
          await tester.startGesture(centre + const Offset(30, 0));
      await tester.pump();

      await a.moveTo(centre - const Offset(120, 0));
      await b.moveTo(centre + const Offset(120, 0));
      await tester.pump();
      await a.up();
      await b.up();
      await tester.pumpAndSettle();

      expect(drag, isEmpty,
          reason: 'the pinch owns both pointers, so nothing underneath drags');
    });

    testWidgets('one finger still reaches the widget underneath', (
      WidgetTester tester,
    ) async {
      // The other half of the promise: claiming two fingers must not cost the
      // editor its scrolling, tapping or selection with one.
      final List<String> drag = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: PinchZoom(
              fontSize: 14,
              enabled: true,
              onCommit: _noop,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (DragStartDetails _) => drag.add('start'),
                onPanUpdate: (DragUpdateDetails _) => drag.add('update'),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );

      await tester.drag(find.byType(PinchZoom), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(drag, contains('start'),
          reason: 'a one-finger drag belongs to the editor, not to zoom');
    });

    testWidgets('disabled passes the child straight through', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: PinchZoom(
              fontSize: 14,
              enabled: false,
              onCommit: _noop,
              child: Text('editor'),
            ),
          ),
        ),
      );

      expect(find.text('editor'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PinchZoom),
          matching: find.byType(RawGestureDetector),
        ),
        findsNothing,
        reason: 'disabled must not compete for pointers at all',
      );
    });
  });
}

void _noop(double _) {}
