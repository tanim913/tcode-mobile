/// Rename, inline in the tree row.
///
/// A dialog would be easier, but it hides the thing being renamed behind a
/// scrim and loses the file's place in the tree. The row itself becomes the
/// field instead.
///
/// The validation message floats in an [OverlayPortal] rather than being laid
/// out under the field: the list uses a fixed `itemExtent`, so a row cannot grow
/// without breaking the virtualisation that keeps 10,000 entries smooth.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/features/explorer/presentation/name_dialog.dart';

class InlineRenameField extends StatefulWidget {
  const InlineRenameField({
    required this.initialName,
    required this.existingNames,
    required this.icon,
    required this.indent,
    required this.onCommit,
    required this.onCancel,
    super.key,
  });

  final String initialName;

  /// Sibling names, so a duplicate is caught before the file system is asked.
  final Set<String> existingNames;

  final Widget icon;

  /// Left inset matching the row's nesting depth, so the field does not jump.
  final double indent;

  final void Function(String newName) onCommit;
  final VoidCallback onCancel;

  @override
  State<InlineRenameField> createState() => _InlineRenameFieldState();
}

class _InlineRenameFieldState extends State<InlineRenameField> {
  late final TextEditingController _field =
      TextEditingController(text: widget.initialName);
  final FocusNode _focus = FocusNode();
  final LayerLink _link = LayerLink();
  final OverlayPortalController _errorOverlay = OverlayPortalController();

  String? _error;

  /// Set once the row is on its way out, so the focus-loss handler that fires
  /// during teardown does not also fire a cancel.
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    // Preselect the part before the extension: renaming main.dart is almost
    // always about "main", and re-typing ".dart" every time is friction.
    final int dot = widget.initialName.lastIndexOf('.');
    final int end = dot > 0 ? dot : widget.initialName.length;
    _field.selection = TextSelection(baseOffset: 0, extentOffset: end);
    _focus.addListener(_onFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        _focus.requestFocus();
      }
    });
  }

  void _onFocusChange() {
    // Tapping anywhere outside abandons the rename, which is what every file
    // manager does and what the brief asks for.
    if (!_focus.hasFocus && !_finished) {
      _cancel();
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _field.dispose();
    super.dispose();
  }

  void _cancel() {
    if (_finished) {
      return;
    }
    _finished = true;
    _errorOverlay.hide();
    widget.onCancel();
  }

  void _commit() {
    final String value = _field.text.trim();
    final String? problem = validateName(value, widget.existingNames);
    if (problem != null) {
      _showError(problem);
      return;
    }
    if (_finished) {
      return;
    }
    _finished = true;
    _errorOverlay.hide();
    if (value == widget.initialName) {
      // Nothing changed, so nothing needs writing to disk.
      widget.onCancel();
      return;
    }
    widget.onCommit(value);
  }

  void _showError(String? problem) {
    if (problem == _error) {
      return;
    }
    setState(() => _error = problem);
    if (problem == null) {
      _errorOverlay.hide();
    } else {
      _errorOverlay.show();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    return SizedBox(
      height: AppSizes.treeRowHeight,
      child: Row(
        children: <Widget>[
          SizedBox(width: widget.indent),
          widget.icon,
          const SizedBox(width: 8),
          Expanded(
            child: CompositedTransformTarget(
              link: _link,
              child: OverlayPortal(
                controller: _errorOverlay,
                overlayChildBuilder: (BuildContext context) =>
                    _ErrorBubble(link: _link, message: _error ?? '', tokens: tokens),
                child: Focus(
                  onKeyEvent: _onKey,
                  child: TextField(
                    controller: _field,
                    focusNode: _focus,
                    style: Theme.of(context).textTheme.bodyMedium,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: _error == null ? tokens.accent : tokens.danger,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: _error == null ? tokens.accent : tokens.danger,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: _error == null ? tokens.accent : tokens.danger,
                        ),
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (String _) => _commit(),
                    onChanged: (String value) =>
                        _showError(validateName(value.trim(), widget.existingNames)),
                    inputFormatters: <TextInputFormatter>[
                      // A name is never a path.
                      FilteringTextInputFormatter.deny(RegExp(r'[/\\]')),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _ErrorBubble extends StatelessWidget {
  const _ErrorBubble({
    required this.link,
    required this.message,
    required this.tokens,
  });

  final LayerLink link;
  final String message;
  final AppColorTokens tokens;

  @override
  Widget build(BuildContext context) {
    return CompositedTransformFollower(
      link: link,
      targetAnchor: Alignment.bottomLeft,
      offset: const Offset(0, 2),
      child: Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: tokens.danger,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.error_outline, size: 12, color: tokens.onAccent),
                const SizedBox(width: 4),
                Text(
                  message,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: tokens.onAccent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
