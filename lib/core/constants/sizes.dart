/// Layout dimensions and breakpoints.
///
/// The brief forbids fixed pixel sizes for major layout elements; these are the
/// touch-target and density constants that Material and accessibility require,
/// plus the breakpoints that drive [LayoutBuilder] decisions.
library;

abstract final class AppSizes {
  /// At or above this width the sidebar docks beside the editor instead of
  /// overlaying it. Matches Material 3's "medium" window class boundary.
  static const double tabletBreakpoint = 840;

  /// Fraction of screen width the explorer overlay covers on a phone.
  /// Specified exactly by the brief.
  static const double explorerPhoneWidthFraction = 0.5;

  /// Docked sidebar drag limits on large screens.
  static const double sidebarMinWidth = 200;
  static const double sidebarMaxWidthFraction = 0.5;

  /// Opacity the scrim animates to when the explorer is fully open.
  static const double scrimMaxOpacity = 0.4;

  /// A horizontal drag starting inside this strip from the left edge opens the
  /// explorer. Kept narrow so it does not steal editor selection gestures.
  static const double edgeSwipeZone = 20;

  /// Every tree row is exactly this tall, which is what lets the tree use a
  /// fixed itemExtent and stay fast with 10,000 entries.
  static const double treeRowHeight = 40;

  /// Horizontal inset added per nesting level in the tree.
  static const double treeIndentPerLevel = 12;

  /// Accessibility floor. The brief requires 40dp minimum, 48dp for primary.
  static const double minTouchTarget = 40;
  static const double primaryTouchTarget = 48;

  static const double tabStripHeight = 40;
  static const double breadcrumbHeight = 28;
  static const double statusBarHeight = 24;
  static const double toolbarHeight = 48;
  static const double accessoryBarHeight = 44;
}
