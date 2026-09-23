/// One row in the explorer tree.
///
/// Every row is exactly [AppSizes.treeRowHeight] tall, which is what lets the
/// list use a fixed `itemExtent` and stay smooth with thousands of entries.
/// Keep this widget cheap: it is rebuilt on every scroll frame.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocket_code/core/constants/durations.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/features/explorer/application/tree_state.dart';
import 'package:pocket_code/features/explorer/presentation/file_icons.dart';

class TreeRowTile extends StatelessWidget {
  const TreeRowTile({
    required this.row,
    required this.isActive,
    required this.showExtensions,
    required this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.isChecked = false,
    this.isDropTarget = false,
    this.onCheckChanged,
    super.key,
  });

  final TreeRow row;
  final bool isActive;
  final bool showExtensions;
  final VoidCallback onTap;

  /// Reports the press position so the context menu can open where the
  /// finger actually is, rather than centred on the row.
  final void Function(Offset globalPosition)? onLongPress;

  /// True while the explorer is in multi-select mode, which swaps the chevron
  /// for a checkbox and turns a tap into a selection toggle.
  final bool selectionMode;

  final bool isChecked;

  /// True while a drag is hovering this folder, ready to drop into it.
  final bool isDropTarget;

  final ValueChanged<bool>? onCheckChanged;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    final bool isFolder = row.isFolder;
    final FileIcon icon = FileIcons.forNode(row.node, expanded: row.isExpanded);

    final String label = showExtensions || isFolder
        ? row.node.name
        : row.node.baseName;

    return Semantics(
      // Screen readers get the kind and the open/closed state, not just the
      // name, because the visual chevron carries that meaning sighted users get.
      //
      // container + excludeSemantics collapses the row into a single node.
      // Without it the icon, tooltip and text each contribute their own, and a
      // screen reader reads the row as three separate unlabelled fragments.
      container: true,
      excludeSemantics: true,
      label: label,
      hint: <String>[
        if (isFolder)
          row.isExpanded ? 'Folder, expanded' : 'Folder, collapsed'
        else
          'File',
        if (selectionMode) isChecked ? 'Selected' : 'Not selected',
        if (isDropTarget) 'Drop target',
      ].join('. '),
      selected: selectionMode ? isChecked : isActive,
      button: true,
      child: _Background(
        isActive: isActive,
        isDropTarget: isDropTarget,
        tokens: tokens,
        // GestureDetector wraps InkWell because onLongPressStart reports the
        // press position, which InkWell's onLongPress does not — and the
        // context menu must open where the finger is.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: onLongPress == null
              ? null
              : (LongPressStartDetails details) {
                  HapticFeedback.mediumImpact();
                  onLongPress!(details.globalPosition);
                },
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: AppSizes.treeRowHeight,
              child: Row(
                children: <Widget>[
                  _IndentGuides(depth: row.depth, color: tokens.indentGuide),
                  SizedBox(
                    width: 20,
                    child: selectionMode
                        ? _RowCheckbox(
                            checked: isChecked,
                            onChanged: onCheckChanged,
                          )
                        : _Chevron(
                            visible: isFolder,
                            expanded: row.isExpanded,
                            loading: row.isLoading,
                            color: tokens.textMuted,
                          ),
                  ),
                  Icon(icon.icon, size: 16, color: icon.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      // The full name, for rows the ellipsis truncates.
                      message: row.node.name,
                      waitDuration: const Duration(milliseconds: 600),
                      // Manual, so the tooltip cannot eat the long press.
                      // By default Tooltip claims it, and since the file name
                      // is the obvious place to press, that silently disabled
                      // the context menu exactly where people reach for it.
                      // Hovering with a mouse still shows it.
                      triggerMode: TooltipTriggerMode.manual,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: isActive
                                  ? tokens.textPrimary
                                  : tokens.textSecondary,
                              fontWeight:
                                  isActive ? FontWeight.w600 : FontWeight.w400,
                            ),
                      ),
                    ),
                  ),
                  // An arrow, not just a colour, says where the drop will land.
                  if (isDropTarget)
                    Icon(
                      Icons.subdirectory_arrow_right,
                      size: 14,
                      color: tokens.accent,
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RowCheckbox extends StatelessWidget {
  const _RowCheckbox({required this.checked, required this.onChanged});

  final bool checked;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.square(
        dimension: 20,
        child: Checkbox(
          value: checked,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: onChanged == null
              ? null
              : (bool? value) => onChanged!(value ?? false),
        ),
      ),
    );
  }
}

/// Selection background plus an accent bar on the active row, and the drop
/// highlight while a drag hovers.
///
/// The bar matters for accessibility: it means the active file is not conveyed
/// by background colour alone.
class _Background extends StatelessWidget {
  const _Background({
    required this.isActive,
    required this.isDropTarget,
    required this.tokens,
    required this.child,
  });

  final bool isActive;
  final bool isDropTarget;
  final AppColorTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (isDropTarget) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.accent.withValues(alpha: 0.18),
          border: Border.all(color: tokens.accent),
        ),
        child: child,
      );
    }
    if (!isActive) {
      return child;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.sidebarActive,
        border: Border(left: BorderSide(color: tokens.accent, width: 2)),
      ),
      child: child,
    );
  }
}

/// Faint vertical rules showing nesting depth.
class _IndentGuides extends StatelessWidget {
  const _IndentGuides({required this.depth, required this.color});

  final int depth;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (depth == 0) {
      return const SizedBox(width: 6);
    }
    return SizedBox(
      width: 6 + depth * AppSizes.treeIndentPerLevel,
      child: CustomPaint(
        painter: _IndentGuidePainter(depth: depth, color: color),
      ),
    );
  }
}

class _IndentGuidePainter extends CustomPainter {
  const _IndentGuidePainter({required this.depth, required this.color});

  final int depth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (int i = 0; i < depth; i++) {
      final double x = 6 + i * AppSizes.treeIndentPerLevel + 0.5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_IndentGuidePainter oldDelegate) =>
      oldDelegate.depth != depth || oldDelegate.color != color;
}

/// Expand/collapse arrow, or a spinner while children are loading.
class _Chevron extends StatelessWidget {
  const _Chevron({
    required this.visible,
    required this.expanded,
    required this.loading,
    required this.color,
  });

  final bool visible;
  final bool expanded;
  final bool loading;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(
        child: SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
        ),
      );
    }
    if (!visible) {
      return const SizedBox.shrink();
    }
    return Center(
      child: AnimatedRotation(
        // A quarter turn, so one icon serves both states.
        turns: expanded ? 0.25 : 0,
        duration: AppMotion.scale(context, AppDurations.chevronRotate),
        curve: AppMotion.curve(context, AppCurves.standard),
        child: Icon(Icons.chevron_right, size: 16, color: color),
      ),
    );
  }
}
