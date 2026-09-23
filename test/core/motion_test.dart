/// Reduce-motion support.
///
/// Driven through `MediaQuery.disableAnimations`, which is what the platform
/// sets from the OS accessibility switch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/core/constants/durations.dart';

Widget probe({
  required bool disableAnimations,
  required void Function(BuildContext) onBuild,
}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Builder(
      builder: (BuildContext context) {
        onBuild(context);
        return const SizedBox.shrink();
      },
    ),
  );
}

void main() {
  testWidgets('normally, durations and curves pass through unchanged', (
    WidgetTester tester,
  ) async {
    late Duration duration;
    late Curve curve;
    late bool reduced;

    await tester.pumpWidget(
      probe(
        disableAnimations: false,
        onBuild: (BuildContext context) {
          reduced = AppMotion.reduced(context);
          duration = AppMotion.scale(context, AppDurations.explorerOpen);
          curve = AppMotion.curve(context, AppCurves.standard);
        },
      ),
    );

    expect(reduced, isFalse);
    expect(duration, AppDurations.explorerOpen);
    expect(curve, AppCurves.standard);
  });

  testWidgets('reduce motion collapses durations to zero', (
    WidgetTester tester,
  ) async {
    late Duration duration;
    late Curve curve;
    late bool reduced;

    await tester.pumpWidget(
      probe(
        disableAnimations: true,
        onBuild: (BuildContext context) {
          reduced = AppMotion.reduced(context);
          duration = AppMotion.scale(context, AppDurations.explorerOpen);
          curve = AppMotion.curve(context, AppCurves.standard);
        },
      ),
    );

    expect(reduced, isTrue);
    expect(duration, Duration.zero,
        reason: 'a shortened animation is still motion');
    expect(curve, Curves.linear,
        reason: 'a manually driven controller must not overshoot');
  });

  testWidgets('no MediaQuery at all is treated as motion allowed', (
    WidgetTester tester,
  ) async {
    late bool reduced;
    await tester.pumpWidget(
      Builder(
        builder: (BuildContext context) {
          reduced = AppMotion.reduced(context);
          return const SizedBox.shrink();
        },
      ),
    );

    expect(reduced, isFalse,
        reason: 'a missing MediaQuery must not crash or silently disable motion');
  });
}
