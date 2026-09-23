/// Lays out the explorer panel against the editor.
///
/// Two modes, chosen by width:
///
/// * **Phone (< 840dp)** — the panel overlays the editor, covering exactly 50%
///   of the width, with a scrim over the rest. It deliberately does NOT push or
///   resize the editor: reflowing a code view mid-animation is expensive and
///   makes the text visibly reflow while sliding.
/// * **Tablet (>= 840dp)** — the panel docks beside the editor and is resizable
///   by dragging the divider.
///
/// The performance rule that shapes this file: the editor is passed in as a
/// pre-built widget and handed to [AnimatedBuilder] as its `child`, so it is
/// built once and merely re-positioned each frame. Both sides sit in their own
/// [RepaintBoundary] so neither repaints the other while sliding.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/durations.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';

class ExplorerScaffold extends StatefulWidget {
  const ExplorerScaffold({
    required this.panel,
    required this.body,
    required this.controller,
    super.key,
  });

  final Widget panel;
  final Widget body;

  /// Owned by the shell so commands, the back button and the menu button can
  /// all drive the same animation.
  final ExplorerPanelController controller;

  @override
  State<ExplorerScaffold> createState() => _ExplorerScaffoldState();
}

class _ExplorerScaffoldState extends State<ExplorerScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: AppDurations.explorerOpen,
    reverseDuration: AppDurations.explorerClose,
  );

  double _panelWidth = 0;
  double _dockedWidth = 280;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(_animation);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The controller outlives a rebuild, so reduce-motion has to be applied to
    // it here rather than at construction — the setting can change while the
    // app is running.
    _animation
      ..duration = AppMotion.scale(context, AppDurations.explorerOpen)
      ..reverseDuration = AppMotion.scale(context, AppDurations.explorerClose);
  }

  @override
  void dispose() {
    widget.controller._detach();
    _animation.dispose();
    super.dispose();
  }

  /// Converts a horizontal drag into animation progress, so the panel tracks
  /// the finger instead of playing a canned animation.
  void _onDragUpdate(DragUpdateDetails details) {
    if (_panelWidth <= 0) {
      return;
    }
    _animation.value += details.primaryDelta! / _panelWidth;
  }

  /// Decides open or closed on release. A fast flick wins over position, which
  /// is what makes a short, quick swipe feel right.
  void _onDragEnd(DragEndDetails details) {
    const double flingThreshold = 365;
    final double velocity = details.velocity.pixelsPerSecond.dx;
    if (velocity.abs() > flingThreshold) {
      if (velocity > 0) {
        _animation.fling();
      } else {
        _animation.fling(velocity: -1);
      }
      return;
    }
    if (_animation.value > 0.5) {
      _animation.fling();
    } else {
      _animation.fling(velocity: -1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool docked = constraints.maxWidth >= AppSizes.tabletBreakpoint;
        return docked
            ? _buildDocked(context, constraints)
            : _buildOverlay(context, constraints);
      },
    );
  }

  // --- Tablet ---------------------------------------------------------------

  Widget _buildDocked(BuildContext context, BoxConstraints constraints) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    final double maxWidth =
        constraints.maxWidth * AppSizes.sidebarMaxWidthFraction;
    final double width = _dockedWidth.clamp(AppSizes.sidebarMinWidth, maxWidth);

    // On a docked layout the panel is open by default, so the controller's
    // "is open" state still reflects what the user sees.
    return AnimatedBuilder(
      animation: _animation,
      child: RepaintBoundary(child: widget.body),
      builder: (BuildContext context, Widget? body) {
        final bool visible = _animation.value > 0 || !_animation.isDismissed;
        return Row(
          children: <Widget>[
            if (visible)
              SizedBox(
                width: width * _animation.value.clamp(0.0, 1.0),
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    maxWidth: width,
                    child: SizedBox(
                      width: width,
                      child: RepaintBoundary(child: widget.panel),
                    ),
                  ),
                ),
              ),
            if (visible) _DragHandle(
              color: tokens.border,
              onDrag: (double delta) => setState(() {
                _dockedWidth = (_dockedWidth + delta)
                    .clamp(AppSizes.sidebarMinWidth, maxWidth);
              }),
            ),
            Expanded(child: body!),
          ],
        );
      },
    );
  }

  // --- Phone ----------------------------------------------------------------

  Widget _buildOverlay(BuildContext context, BoxConstraints constraints) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    _panelWidth = constraints.maxWidth * AppSizes.explorerPhoneWidthFraction;

    return Stack(
      children: <Widget>[
        // Built once and reused as AnimatedBuilder's `child`, so typing and
        // scrolling in the editor never rebuild because the panel moved.
        RepaintBoundary(child: widget.body),

        AnimatedBuilder(
          animation: _animation,
          builder: (BuildContext context, _) {
            final double t = _animation.value;
            if (t == 0) {
              // Fully closed: contribute nothing to hit testing, so editor
              // gestures are completely unaffected.
              return const SizedBox.shrink();
            }
            return Stack(
              children: <Widget>[
                // Scrim over the uncovered half.
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: t < 0.1,
                    child: GestureDetector(
                      onTap: widget.controller.close,
                      child: ColoredBox(
                        color: tokens.scrim.withValues(
                          alpha: AppSizes.scrimMaxOpacity * t,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _panelWidth,
                  child: FractionalTranslation(
                    translation: Offset(t - 1, 0),
                    child: GestureDetector(
                      onHorizontalDragUpdate: _onDragUpdate,
                      onHorizontalDragEnd: _onDragEnd,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: tokens.scrim.withValues(alpha: 0.3 * t),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: RepaintBoundary(child: widget.panel),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),

        // Edge-swipe zone. Deliberately narrow and only active while closed, so
        // it cannot steal editor scrolling or text selection.
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: AppSizes.edgeSwipeZone,
          child: AnimatedBuilder(
            animation: _animation,
            builder: (BuildContext context, _) {
              if (!_animation.isDismissed) {
                return const SizedBox.shrink();
              }
              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Drag handle between the docked panel and the editor.
class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.color, required this.onDrag});

  final Color color;
  final void Function(double delta) onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (DragUpdateDetails d) => onDrag(d.delta.dx),
        child: SizedBox(
          width: 8,
          child: Center(
            child: ColoredBox(
              color: color,
              child: const SizedBox(width: 1, height: double.infinity),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens and closes the explorer from anywhere: the menu button, a command, a
/// keyboard shortcut, or the Android back button.
class ExplorerPanelController extends ChangeNotifier {
  AnimationController? _animation;

  void _attach(AnimationController controller) {
    _animation = controller;
    controller.addListener(notifyListeners);
  }

  void _detach() {
    _animation?.removeListener(notifyListeners);
    _animation = null;
  }

  bool get isOpen => (_animation?.value ?? 0) > 0.5;

  /// True whenever the panel is not fully closed. Pinch-to-zoom checks this,
  /// because zoom must be ignored the moment the panel starts opening.
  bool get isVisible => (_animation?.value ?? 0) > 0;

  double get progress => _animation?.value ?? 0;

  void open() => _animation?.fling();

  void close() => _animation?.fling(velocity: -1);

  void toggle() => isOpen ? close() : open();

  /// Opens the panel instantly, for the docked tablet layout where there is no
  /// slide-in to play on first build.
  void openImmediately() => _animation?.value = 1;
}
