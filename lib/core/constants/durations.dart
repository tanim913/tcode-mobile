/// Every animation duration and curve in the app.
///
/// Centralised for two reasons: the design stays coherent, and "respect the
/// system reduce-motion setting" becomes one function instead of an audit.
library;

import 'package:flutter/widgets.dart';

abstract final class AppDurations {
  /// Explorer panel slide-in. Slightly slower than the close, which reads as
  /// deliberate rather than sluggish.
  static const Duration explorerOpen = Duration(milliseconds: 260);
  static const Duration explorerClose = Duration(milliseconds: 220);

  /// Folder chevron rotation on expand/collapse.
  static const Duration chevronRotate = Duration(milliseconds: 150);

  /// Newly revealed tree rows fading in. Only applied to small folders.
  static const Duration treeRowReveal = Duration(milliseconds: 120);

  /// Context menu scale-and-fade from the press point.
  static const Duration contextMenu = Duration(milliseconds: 140);

  /// Tab selection indicator sliding between tabs.
  static const Duration tabIndicator = Duration(milliseconds: 180);

  /// Cross-fade when the editor swaps to a different file.
  static const Duration fileSwap = Duration(milliseconds: 100);

  /// Zoom percentage badge fade in, hold, then fade out.
  static const Duration zoomBadgeFade = Duration(milliseconds: 120);
  static const Duration zoomBadgeHold = Duration(milliseconds: 700);

  /// How long an undo snackbar stays on screen before the delete is committed.
  static const Duration undoWindow = Duration(seconds: 5);

  /// A folder listing shorter than this shows no spinner; flashing a spinner
  /// for 40ms looks like a glitch.
  static const Duration listingSpinnerThreshold = Duration(milliseconds: 150);

  /// A file watcher settles before the folder is re-read. One save can emit
  /// several events, and listing once per event would thrash the tree.
  static const Duration watchDebounce = Duration(milliseconds: 250);

  /// Search input settles before a query is dispatched.
  static const Duration searchDebounce = Duration(milliseconds: 220);

  /// Default delay for the "auto save after delay" mode.
  static const Duration autoSaveDelay = Duration(milliseconds: 1000);
}

abstract final class AppCurves {
  /// Decelerating: the panel arrives and settles.
  static const Curve explorerOpen = Curves.easeOutCubic;

  /// Accelerating: the panel gets out of the way quickly.
  static const Curve explorerClose = Curves.easeInCubic;

  static const Curve standard = Curves.easeInOutCubic;
  static const Curve emphasised = Curves.easeOutBack;
}

/// Reduce-motion support, in the one place the durations already live.
///
/// Reads `MediaQuery.disableAnimations`, which Flutter populates from the
/// platform accessibility setting — "Remove animations" on Android, "Reduce
/// Motion" on iOS. Honouring the system switch rather than adding an app
/// toggle means someone who has already asked their phone to stop animating
/// does not have to ask again here.
///
/// Animations collapse to zero rather than merely getting faster: a shortened
/// animation is still motion, and motion is the thing being objected to.
abstract final class AppMotion {
  /// True when the viewer has asked for less motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], or zero when motion is reduced.
  static Duration scale(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;

  /// A curve that does not overshoot when motion is reduced.
  ///
  /// Matters for anything springy: at zero duration a bouncing curve is
  /// invisible, but a controller driven manually — the explorer panel follows
  /// the finger — still evaluates it, and an overshoot reads as a glitch.
  static Curve curve(BuildContext context, Curve preferred) =>
      reduced(context) ? Curves.linear : preferred;
}
