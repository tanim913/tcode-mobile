/// Pinch to change the editor's font size.
///
/// Three rules shape this, and they come from the brief and from a bug found
/// on a device:
///
/// * **One finger must be untouched.** Scrolling, tapping and dragging a
///   selection handle all use a single pointer, so this recogniser stays out of
///   the way until a second finger is down.
/// * **The second finger must stop the editor's drag.** `re_editor` installs
///   its own pan recognisers, and a purely passive listener let them keep
///   selecting text underneath the pinch — so a zoom also smeared a selection
///   across the file. The recogniser below therefore *claims* the gesture the
///   moment a second finger lands, which rejects the editor's recognisers for
///   those pointers and ends the selection drag.
/// * **Commit on release, not per frame.** Re-laying out a 5,000 line buffer on
///   every pointer move drops frames. The pinch shows a live badge while the
///   fingers are down and writes the setting once, when they lift.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';

/// Clamps a font size to the range the settings screen also enforces.
double clampFontSize(double value) =>
    value.clamp(AppLimits.minFontSize, AppLimits.maxFontSize);

/// The font size a pinch of [scale] should produce from [start].
///
/// Rounded to whole points: the editor's metrics are integral, and a fractional
/// size makes the badge flicker between two numbers while a finger rests.
double zoomedFontSize(double start, double scale) =>
    clampFontSize((start * scale).roundToDouble());

/// Recognises a two-finger pinch, and nothing else.
///
/// Written by hand rather than reusing `ScaleGestureRecognizer` for one
/// reason: a scale recogniser reports a *single* pointer as a scale of 1.0 and
/// competes for it, which would put it in the arena against the editor's own
/// tap and drag handling on every touch. This one only enters the fight when
/// there are two fingers, so single-finger scrolling, tapping and selection
/// behave exactly as they did before.
class TwoFingerZoomRecognizer extends OneSequenceGestureRecognizer {
  TwoFingerZoomRecognizer({super.debugOwner});

  /// Fired when the second finger lands and the gesture has been claimed.
  VoidCallback? onStart;

  /// Fired with the span relative to the span at [onStart].
  ValueChanged<double>? onUpdate;

  /// Fired when a finger lifts, leaving fewer than two.
  VoidCallback? onEnd;

  final Map<int, Offset> _pointers = <int, Offset>{};
  double _startSpan = 0;
  bool _zooming = false;

  @override
  String get debugDescription => 'two-finger zoom';

  /// Distance between the two oldest live pointers.
  double get _span {
    if (_pointers.length < 2) {
      return 0;
    }
    final List<Offset> points = _pointers.values.toList(growable: false);
    return (points[0] - points[1]).distance;
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    _pointers[event.pointer] = event.position;
    if (_zooming) {
      // A third finger during a pinch: claim it too, or its arena would be
      // swept to whichever recogniser happens to be first.
      resolve(GestureDisposition.accepted);
      return;
    }
    if (_pointers.length < 2) {
      // Deliberately undecided. The editor's recognisers entered the arena
      // first (they are deeper in the hit-test path), so a tap or a one-finger
      // drag resolves to them and this recogniser simply loses.
      return;
    }
    final double span = _span;
    if (span <= 0) {
      return;
    }
    _startSpan = span;
    _zooming = true;
    // The claim. Every arena this recogniser is still in resolves in its
    // favour, so the editor's pan recognisers are rejected and stop dragging
    // a selection under the pinch.
    resolve(GestureDisposition.accepted);
    onStart?.call();
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      if (!_pointers.containsKey(event.pointer)) {
        return;
      }
      _pointers[event.pointer] = event.position;
      if (_zooming && _startSpan > 0) {
        onUpdate?.call(_span / _startSpan);
      }
      return;
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
      if (_zooming && _pointers.length < 2) {
        _finish();
      }
      stopTrackingPointer(event.pointer);
    }
  }

  void _finish() {
    _zooming = false;
    _startSpan = 0;
    onEnd?.call();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointers.clear();
    if (_zooming) {
      _finish();
    }
  }

  @override
  void dispose() {
    _pointers.clear();
    super.dispose();
  }
}

/// Wraps the editor with pinch-to-zoom.
class PinchZoom extends StatefulWidget {
  const PinchZoom({
    required this.fontSize,
    required this.onCommit,
    required this.enabled,
    required this.child,
    super.key,
  });

  final double fontSize;

  /// Called once, when the fingers lift, with the size to persist.
  final ValueChanged<double> onCommit;

  /// False while the explorer is open or the document cannot be zoomed, so the
  /// gesture cannot fight a panel animation.
  final bool enabled;

  final Widget child;

  @override
  State<PinchZoom> createState() => _PinchZoomState();
}

class _PinchZoomState extends State<PinchZoom> {
  double _startSize = 0;
  double? _preview;

  void _onStart() {
    _startSize = widget.fontSize;
    setState(() => _preview = widget.fontSize);
  }

  void _onUpdate(double scale) {
    final double next = zoomedFontSize(_startSize, scale);
    if (next != _preview) {
      setState(() => _preview = next);
    }
  }

  void _onEnd() {
    final double? preview = _preview;
    if (preview == null) {
      return;
    }
    setState(() => _preview = null);
    // Committed once, on release: re-laying out a large buffer every frame
    // drops frames, so the badge previews and the setting is written here.
    if (preview != widget.fontSize) {
      widget.onCommit(preview);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    return Stack(
      children: <Widget>[
        RawGestureDetector(
          gestures: <Type, GestureRecognizerFactory<GestureRecognizer>>{
            TwoFingerZoomRecognizer:
                GestureRecognizerFactoryWithHandlers<TwoFingerZoomRecognizer>(
              () => TwoFingerZoomRecognizer(debugOwner: this),
              (TwoFingerZoomRecognizer instance) {
                instance
                  ..onStart = _onStart
                  ..onUpdate = _onUpdate
                  ..onEnd = _onEnd;
              },
            ),
          },
          child: widget.child,
        ),
        if (_preview != null)
          Positioned(
            top: 12,
            right: 12,
            child: _ZoomBadge(size: _preview!),
          ),
      ],
    );
  }
}

/// "14 pt" while pinching, with the limits called out when you hit them.
class _ZoomBadge extends StatelessWidget {
  const _ZoomBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    final bool atLimit =
        size <= AppLimits.minFontSize || size >= AppLimits.maxFontSize;

    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          border: Border.all(color: atLimit ? tokens.warning : tokens.border),
          borderRadius: const BorderRadius.all(Radius.circular(6)),
        ),
        child: Text(
          atLimit ? '${size.round()} pt · limit' : '${size.round()} pt',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: atLimit ? tokens.warning : tokens.textPrimary,
              ),
        ),
      ),
    );
  }
}
