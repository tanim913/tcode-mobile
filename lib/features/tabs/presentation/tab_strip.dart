/// Horizontally scrollable strip of open tabs.
///
/// Rebuild cost matters here: this widget sits above the editor and must not
/// rebuild on every keystroke. It watches only the tab list, and each tab's
/// dirty state is derived from already-immutable data, so typing rebuilds one
/// small strip rather than the editor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/core/constants/durations.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/features/explorer/presentation/file_icons.dart';
import 'package:pocket_code/features/tabs/application/tabs_controller.dart';
import 'package:pocket_code/features/tabs/application/tabs_state.dart';

/// Actions offered when a tab is long-pressed.
enum TabAction {
  close('Close'),
  closeOthers('Close others'),
  closeToRight('Close to the right'),
  closeSaved('Close saved'),
  closeAll('Close all'),
  copyPath('Copy path'),
  revealInExplorer('Reveal in explorer');

  const TabAction(this.label);

  final String label;
}

class TabStrip extends ConsumerWidget {
  const TabStrip({
    required this.onAction,
    required this.onCloseRequested,
    super.key,
  });

  /// Invoked for long-press menu choices the strip cannot handle alone.
  final void Function(TabAction action, int index) onAction;

  /// Invoked when a tab's close button is tapped. The shell decides whether a
  /// save prompt is needed, because only it can show a dialog.
  final void Function(int index) onCloseRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    final TabsState tabs = ref.watch(tabsProvider);

    if (!tabs.hasTabs) {
      return const SizedBox.shrink();
    }

    return Container(
      height: AppSizes.tabStripHeight,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        itemCount: tabs.tabs.length,
        // onReorderItem, not the deprecated onReorder: it hands us an index
        // already adjusted for the removed item, which is what reorder expects.
        onReorderItem: ref.read(tabsProvider.notifier).reorder,
        // The default proxy adds elevation and a material background that looks
        // wrong on a dense strip; keep the tab looking like itself while moving.
        proxyDecorator: (Widget child, int index, Animation<double> animation) =>
            Material(color: tokens.surfaceRaised, child: child),
        itemBuilder: (BuildContext context, int index) {
          final OpenTab tab = tabs.tabs[index];
          return ReorderableDragStartListener(
            key: ValueKey<String>(tab.key),
            index: index,
            child: _Tab(
              tab: tab,
              isActive: index == tabs.activeIndex,
              tokens: tokens,
              onTap: () => ref.read(tabsProvider.notifier).setActive(index),
              onDoubleTap: () =>
                  ref.read(tabsProvider.notifier).open(
                        tab.node,
                        tab.rootIndex,
                        preview: false,
                      ),
              onClose: () => onCloseRequested(index),
              onAction: (TabAction action) => onAction(action, index),
            ),
          );
        },
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.tab,
    required this.isActive,
    required this.tokens,
    required this.onTap,
    required this.onDoubleTap,
    required this.onClose,
    required this.onAction,
  });

  final OpenTab tab;
  final bool isActive;
  final AppColorTokens tokens;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onClose;
  final void Function(TabAction) onAction;

  @override
  Widget build(BuildContext context) {
    final FileIcon icon = FileIcons.forNode(tab.node);

    return Semantics(
      container: true,
      selected: isActive,
      // The dirty state is announced, not just drawn, so it never depends on
      // the user noticing a small dot.
      label: tab.isDirty ? '${tab.node.name}, unsaved' : tab.node.name,
      button: true,
      child: AnimatedContainer(
        duration: AppDurations.tabIndicator,
        curve: AppCurves.standard,
        decoration: BoxDecoration(
          color: isActive ? tokens.background : tokens.surface,
          border: Border(
            right: BorderSide(color: tokens.border),
            // The indicator sits on top, which reads better than an underline
            // when the strip is directly above the code.
            top: BorderSide(
              color: isActive ? tokens.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          onLongPress: () => _showMenu(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon.icon, size: 14, color: icon.color),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    tab.node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isActive
                              ? tokens.textPrimary
                              : tokens.textSecondary,
                          // Italics mark a preview tab, matching VS Code.
                          fontStyle: tab.isPreview
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                  ),
                ),
                const SizedBox(width: 4),
                _CloseOrDirty(
                  isDirty: tab.isDirty,
                  tokens: tokens,
                  onClose: onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final RenderBox box = context.findRenderObject()! as RenderBox;
    final Offset position = box.localToGlobal(Offset.zero);
    final TabAction? choice = await showMenu<TabAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + box.size.height,
        position.dx + box.size.width,
        0,
      ),
      items: <PopupMenuEntry<TabAction>>[
        for (final TabAction action in TabAction.values)
          PopupMenuItem<TabAction>(
            value: action,
            height: AppSizes.minTouchTarget,
            child: Text(action.label),
          ),
      ],
    );
    if (choice != null) {
      onAction(choice);
    }
  }
}

/// A filled dot replaces the close button while a tab is dirty, so the state is
/// unmissable and the close action still works by tapping the same spot.
class _CloseOrDirty extends StatelessWidget {
  const _CloseOrDirty({
    required this.isDirty,
    required this.tokens,
    required this.onClose,
  });

  final bool isDirty;
  final AppColorTokens tokens;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onClose,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: 22,
        height: 22,
        child: Center(
          child: isDirty
              ? Icon(Icons.circle, size: 9, color: tokens.unsavedIndicator)
              : Icon(Icons.close, size: 14, color: tokens.textMuted),
        ),
      ),
    );
  }
}
