/// The long-press context menu, anchored at the point the finger went down.
///
/// Flutter's own `showMenu` anchors to a widget's rectangle, not to a touch
/// point, and grows from the wrong corner when it flips. This is a small
/// [PopupRoute] instead: a layout delegate that clamps the menu fully on screen,
/// and a scale-and-fade whose origin follows the same corner the delegate chose.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/durations.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';

/// One row of the menu. [value] is what [showTreeContextMenu] returns.
@immutable
class ContextMenuEntry<T> {
  const ContextMenuEntry({
    required this.value,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.destructive = false,
    this.dividerBefore = false,
  });

  final T value;
  final String label;
  final IconData icon;

  /// Disabled entries stay visible and greyed rather than disappearing, so the
  /// menu does not change shape between invocations and the user can see that
  /// the action exists.
  final bool enabled;

  final bool destructive;
  final bool dividerBefore;
}

/// Margin kept between the menu and the edge of the screen.
const double _screenMargin = 8;

/// Shows the menu at [globalPosition] and resolves to the chosen value, or null
/// if the user dismissed it.
Future<T?> showTreeContextMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<ContextMenuEntry<T>> entries,
  String semanticsLabel = 'Context menu',
}) {
  return Navigator.of(context).push(
    _ContextMenuRoute<T>(
      position: globalPosition,
      entries: entries,
      semanticsLabel: semanticsLabel,
      barrierLabel:
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

class _ContextMenuRoute<T> extends PopupRoute<T> {
  _ContextMenuRoute({
    required this.position,
    required this.entries,
    required this.semanticsLabel,
    required this.barrierLabel,
  });

  final Offset position;
  final List<ContextMenuEntry<T>> entries;
  final String semanticsLabel;

  @override
  final String barrierLabel;

  /// No dim: a menu over a file tree should not hide the row it acts on.
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => AppDurations.contextMenu;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: semanticsLabel,
      explicitChildNodes: true,
      child: CustomSingleChildLayout(
        delegate: _MenuLayout(
          target: position,
          padding: MediaQuery.paddingOf(context),
        ),
        child: _ContextMenuBody<T>(entries: entries),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Size screen = MediaQuery.sizeOf(context);
    // Grow from the corner nearest the finger, which is the corner the layout
    // delegate will have pinned the menu to.
    final Alignment origin = Alignment(
      position.dx > screen.width / 2 ? 1 : -1,
      position.dy > screen.height / 2 ? 1 : -1,
    );
    final Animation<double> curved = CurvedAnimation(
      parent: animation,
      curve: AppCurves.standard,
      reverseCurve: AppCurves.explorerClose,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.9, end: 1).animate(curved),
        alignment: origin,
        child: child,
      ),
    );
  }
}

/// Places the menu at the press point, then pushes it back inside the screen.
class _MenuLayout extends SingleChildLayoutDelegate {
  const _MenuLayout({required this.target, required this.padding});

  final Offset target;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(
      Size(
        constraints.maxWidth - _screenMargin * 2,
        constraints.maxHeight -
            padding.top -
            padding.bottom -
            _screenMargin * 2,
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double maxX = size.width - _screenMargin - childSize.width;
    final double maxY =
        size.height - padding.bottom - _screenMargin - childSize.height;
    return Offset(
      math.max(_screenMargin, math.min(target.dx, maxX)),
      math.max(padding.top + _screenMargin, math.min(target.dy, maxY)),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      oldDelegate.target != target || oldDelegate.padding != padding;
}

class _ContextMenuBody<T> extends StatelessWidget {
  const _ContextMenuBody({required this.entries});

  final List<ContextMenuEntry<T>> entries;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    return Material(
      color: tokens.surfaceRaised,
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final ContextMenuEntry<T> entry in entries) ...<Widget>[
                if (entry.dividerBefore)
                  Divider(height: 1, thickness: 1, color: tokens.border),
                _ContextMenuItem<T>(entry: entry, tokens: tokens),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ContextMenuItem<T> extends StatelessWidget {
  const _ContextMenuItem({required this.entry, required this.tokens});

  final ContextMenuEntry<T> entry;
  final AppColorTokens tokens;

  @override
  Widget build(BuildContext context) {
    final Color color = !entry.enabled
        ? tokens.textMuted
        : entry.destructive
            ? tokens.danger
            : tokens.textPrimary;

    return Semantics(
      button: true,
      enabled: entry.enabled,
      label: entry.label,
      child: InkWell(
        onTap: entry.enabled
            ? () => Navigator.of(context).pop<T>(entry.value)
            : null,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppSizes.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: <Widget>[
              Icon(entry.icon, size: 18, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: color),
                ),
              ),
              // Disabled entries say why they are inert in text as well as in
              // colour, because colour alone is not a signal.
              if (!entry.enabled)
                Text(
                  'Unavailable',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: tokens.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
