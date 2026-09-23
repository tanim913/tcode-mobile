/// The coding accessory bar, shown directly above the soft keyboard.
///
/// This is the single most important widget for making the app usable on a
/// phone: a soft keyboard hides `{ } ( ) [ ] ;` behind two taps, and code is
/// mostly those characters.
///
/// **Resolving a conflict in the brief.** It asks for the bar to be
/// horizontally scrollable *and* for a horizontal drag along it to scrub the
/// cursor. Those are the same gesture, so one has to win. Here the bar scrolls,
/// and cursor scrubbing is a drag that *starts on an arrow key* — which is both
/// discoverable (the arrows are what you already reach for to move) and
/// unambiguous (the arena decides by where the drag began, not by guessing).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/data/models/accessory_key.dart';

/// How far the finger travels per character while scrubbing. Small enough to
/// feel direct, large enough that a shaky thumb does not overshoot.
const double _scrubStepPixels = 10;

/// Delay before a held arrow starts repeating, then the repeat interval. Mirrors
/// platform key-repeat so holding an arrow feels native rather than laggy.
const Duration _repeatDelay = Duration(milliseconds: 320);
const Duration _repeatInterval = Duration(milliseconds: 55);

class AccessoryBar extends StatefulWidget {
  const AccessoryBar({
    required this.keys,
    required this.onKey,
    required this.onScrub,
    super.key,
  });

  final List<AccessoryKey> keys;

  /// Invoked with the key and the sticky Shift state at the moment of press.
  final void Function(AccessoryKey key, {required bool shiftHeld}) onKey;

  /// Invoked while scrubbing, with a signed character delta.
  final void Function(int steps, {required bool shiftHeld}) onScrub;

  @override
  State<AccessoryBar> createState() => _AccessoryBarState();
}

class _AccessoryBarState extends State<AccessoryBar> {
  /// Sticky Shift: it stays on until pressed again or a non-arrow key is used,
  /// because a phone has no way to physically hold a modifier.
  bool _shift = false;

  Timer? _repeat;

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  void _press(AccessoryKey key) {
    if (key.kind == AccessoryKeyKind.shift) {
      HapticFeedback.selectionClick();
      setState(() => _shift = !_shift);
      return;
    }
    widget.onKey(key, shiftHeld: _shift);

    // Shift survives repeated arrow presses so a selection can be extended
    // several characters, but any other key consumes it — otherwise it would
    // silently modify a later, unrelated press.
    if (_shift && !_isArrow(key) && key.kind != AccessoryKeyKind.tab) {
      setState(() => _shift = false);
    }
  }

  static bool _isArrow(AccessoryKey key) => switch (key.kind) {
        AccessoryKeyKind.arrowLeft ||
        AccessoryKeyKind.arrowRight ||
        AccessoryKeyKind.arrowUp ||
        AccessoryKeyKind.arrowDown =>
          true,
        _ => false,
      };

  void _startRepeat(AccessoryKey key) {
    _repeat?.cancel();
    _repeat = Timer(_repeatDelay, () {
      _repeat = Timer.periodic(_repeatInterval, (_) => _press(key));
    });
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;

    return Container(
      height: AppSizes.accessoryBarHeight,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: widget.keys.length,
        itemBuilder: (BuildContext context, int index) {
          final AccessoryKey key = widget.keys[index];
          return _KeyButton(
            accessoryKey: key,
            tokens: tokens,
            isActive: key.kind == AccessoryKeyKind.shift && _shift,
            scrubbable: _isArrow(key),
            onPress: () => _press(key),
            onHoldStart: () => _startRepeat(key),
            onHoldEnd: _stopRepeat,
            onScrub: (int steps) => widget.onScrub(steps, shiftHeld: _shift),
          );
        },
      ),
    );
  }
}

class _KeyButton extends StatefulWidget {
  const _KeyButton({
    required this.accessoryKey,
    required this.tokens,
    required this.isActive,
    required this.scrubbable,
    required this.onPress,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onScrub,
  });

  final AccessoryKey accessoryKey;
  final AppColorTokens tokens;

  /// True for the Shift key while the modifier is latched.
  final bool isActive;

  /// Arrow keys additionally support drag-to-scrub.
  final bool scrubbable;

  final VoidCallback onPress;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final void Function(int steps) onScrub;

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton> {
  /// Distance dragged since the last emitted character step.
  double _dragAccumulator = 0;

  void _onDragUpdate(DragUpdateDetails details) {
    _dragAccumulator += details.delta.dx;
    // Emit whole steps only, so a slow drag produces a steady one-character
    // cadence instead of a burst at the end.
    final int steps = _dragAccumulator ~/ _scrubStepPixels;
    if (steps != 0) {
      _dragAccumulator -= steps * _scrubStepPixels;
      widget.onScrub(steps);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AccessoryKey key = widget.accessoryKey;
    final IconData? icon = _iconFor(key.kind);

    final Widget content = Center(
      child: icon != null
          ? Icon(icon, size: 18, color: widget.tokens.textSecondary)
          : Text(
              key.displayLabel,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: widget.isActive
                        ? widget.tokens.onAccent
                        : widget.tokens.textPrimary,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w500,
                  ),
            ),
    );

    final Widget button = Semantics(
      button: true,
      // container + excludeSemantics collapses the key into one node. Without
      // it the inner Text contributes its own node labelled with the raw glyph,
      // and a screen reader reads "{" instead of "Left brace".
      container: true,
      excludeSemantics: true,
      label: key.semanticsLabel ?? key.displayLabel,
      // The latched state must be announced, not only drawn.
      toggled: key.kind == AccessoryKeyKind.shift ? widget.isActive : null,
      child: GestureDetector(
        onTap: widget.onPress,
        onLongPressStart: (_) => widget.onHoldStart(),
        onLongPressEnd: (_) => widget.onHoldEnd(),
        onLongPressCancel: widget.onHoldEnd,
        // Scrubbing lives on the arrows only; elsewhere a horizontal drag must
        // reach the ListView so the bar can still scroll.
        onHorizontalDragStart: widget.scrubbable
            ? (_) => _dragAccumulator = 0
            : null,
        onHorizontalDragUpdate: widget.scrubbable ? _onDragUpdate : null,
        child: Container(
          width: _widthFor(key),
          // Full bar height keeps the target at least 44dp tall, above the
          // 40dp accessibility floor.
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          decoration: BoxDecoration(
            color: widget.isActive
                ? widget.tokens.accent
                : widget.tokens.surfaceRaised,
            borderRadius: const BorderRadius.all(Radius.circular(5)),
            border: Border.all(color: widget.tokens.border),
          ),
          child: content,
        ),
      ),
    );

    return button;
  }

  /// Wider keys for word labels; square-ish for single characters.
  static double _widthFor(AccessoryKey key) => switch (key.kind) {
        AccessoryKeyKind.tab || AccessoryKeyKind.shift => 52,
        _ => 40,
      };

  static IconData? _iconFor(AccessoryKeyKind kind) => switch (kind) {
        AccessoryKeyKind.arrowLeft => Icons.keyboard_arrow_left,
        AccessoryKeyKind.arrowRight => Icons.keyboard_arrow_right,
        AccessoryKeyKind.arrowUp => Icons.keyboard_arrow_up,
        AccessoryKeyKind.arrowDown => Icons.keyboard_arrow_down,
        _ => null,
      };
}
