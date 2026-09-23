/// Editing actions shown when the soft keyboard is hidden.
///
/// Everything here is contextual: Save is disabled on a clean buffer, Undo and
/// Redo reflect the real history, and Toggle comment greys out for a language
/// with no comment syntax. A disabled button is better than a hidden one — the
/// row must not reflow as you move between files.
///
/// Primary actions sit at the bottom of the screen, within thumb reach, which
/// is the one-handed-use requirement in the brief.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';

/// Actions the toolbar can raise. The shell decides what each one does, so the
/// same set can later be driven by the command palette.
enum EditorToolbarAction {
  undo('Undo', Icons.undo),
  redo('Redo', Icons.redo),
  find('Find', Icons.search),
  save('Save', Icons.save_outlined),
  indent('Indent', Icons.format_indent_increase),
  outdent('Outdent', Icons.format_indent_decrease),
  toggleComment('Toggle comment', Icons.comment_outlined),
  saveAll('Save all', Icons.save_alt_outlined),
  wordWrap('Toggle word wrap', Icons.wrap_text),
  goToLine('Go to line', Icons.numbers),
  run('Run', Icons.play_arrow);

  const EditorToolbarAction(this.label, this.icon);

  final String label;
  final IconData icon;
}

class EditorBottomToolbar extends StatelessWidget {
  const EditorBottomToolbar({
    required this.onAction,
    required this.enabled,
    super.key,
  });

  /// Invoked when an action is chosen, from the row or the overflow menu.
  final void Function(EditorToolbarAction action) onAction;

  /// Which actions are currently available. An action absent from this set is
  /// rendered disabled.
  final Set<EditorToolbarAction> enabled;

  /// Kept in the visible row: the actions reached constantly while editing.
  static const List<EditorToolbarAction> _primary = <EditorToolbarAction>[
    EditorToolbarAction.undo,
    EditorToolbarAction.redo,
    EditorToolbarAction.find,
    EditorToolbarAction.save,
    EditorToolbarAction.indent,
    EditorToolbarAction.outdent,
    EditorToolbarAction.toggleComment,
  ];

  /// Everything else, so the row never crowds on a small phone.
  static const List<EditorToolbarAction> _overflow = <EditorToolbarAction>[
    EditorToolbarAction.saveAll,
    EditorToolbarAction.wordWrap,
    EditorToolbarAction.goToLine,
    EditorToolbarAction.run,
  ];

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;

    return Container(
      height: AppSizes.toolbarHeight,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: <Widget>[
                for (final EditorToolbarAction action in _primary)
                  _ToolbarButton(
                    action: action,
                    tokens: tokens,
                    onPressed: enabled.contains(action)
                        ? () => onAction(action)
                        : null,
                  ),
              ],
            ),
          ),
          PopupMenuButton<EditorToolbarAction>(
            tooltip: 'More actions',
            icon: Icon(Icons.more_horiz, color: tokens.textSecondary),
            onSelected: onAction,
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<EditorToolbarAction>>[
              for (final EditorToolbarAction action in _overflow)
                PopupMenuItem<EditorToolbarAction>(
                  value: action,
                  enabled: enabled.contains(action),
                  height: AppSizes.minTouchTarget,
                  child: Row(
                    children: <Widget>[
                      Icon(action.icon, size: 16, color: tokens.textSecondary),
                      const SizedBox(width: 10),
                      Text(action.label),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.action,
    required this.tokens,
    required this.onPressed,
  });

  final EditorToolbarAction action;
  final AppColorTokens tokens;

  /// Null renders the button disabled.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: action.label,
      child: IconButton(
        // Semantics label rather than relying on the icon glyph alone.
        icon: Icon(action.icon, size: 20, semanticLabel: action.label),
        color: tokens.textSecondary,
        disabledColor: tokens.textMuted.withValues(alpha: 0.4),
        // 48dp: these are primary actions, so they get the larger target.
        constraints: const BoxConstraints(
          minWidth: AppSizes.primaryTouchTarget,
          minHeight: AppSizes.minTouchTarget,
        ),
        onPressed: onPressed,
      ),
    );
  }
}
