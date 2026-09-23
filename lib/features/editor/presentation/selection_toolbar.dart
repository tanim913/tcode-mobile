/// Cut / Copy / Paste / Select all, shown over a selection in the editor.
///
/// `re_editor` draws the selection handles but ships **no** toolbar: it exposes
/// a `toolbarController` hook and does nothing unless one is supplied. Without
/// this, selecting text in the editor offered no way to copy it, which is the
/// single most-used editing action on a phone.
///
/// Built on Flutter's [AdaptiveTextSelectionToolbar] so the buttons look and
/// position themselves like every other text field on the device, rather than
/// being a bespoke bar that only resembles one.
library;

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

/// Builds the controller `CodeEditor.toolbarController` expects.
///
/// [isReadOnly] is a callback rather than a value, and that is load-bearing.
/// The controller owns the single `OverlayEntry` holding the toolbar and hides
/// it before showing another — but only its *own*. Rebuilding the controller
/// on every widget build gave each new one an empty `_entry`, so it had nothing
/// to hide and the previous toolbar stayed on screen: selecting a few times in
/// a row stacked up several "Cut Copy Paste" pills. One controller must live
/// for the life of the tab, which means it cannot capture a `readOnly` value
/// that changes when the edit lock is toggled.
SelectionToolbarController buildSelectionToolbar({
  required bool Function() isReadOnly,
}) {
  return MobileSelectionToolbarController(
    builder: selectionToolbarBuilder(isReadOnly: isReadOnly),
  );
}

/// The builder half, separated so it can be mounted in a test.
///
/// `MobileSelectionToolbarController` keeps its builder private, so a test
/// that went through the controller could never see the buttons it offers.
ToolbarMenuBuilder selectionToolbarBuilder({
  required bool Function() isReadOnly,
}) {
  return ({
    required BuildContext context,
    required TextSelectionToolbarAnchors anchors,
    required CodeLineEditingController controller,
    required VoidCallback onDismiss,
    required VoidCallback onRefresh,
  }) {
    return _SelectionToolbar(
      anchors: anchors,
      controller: controller,
      readOnly: isReadOnly(),
      onDismiss: onDismiss,
    );
  };
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.anchors,
    required this.controller,
    required this.readOnly,
    required this.onDismiss,
  });

  final TextSelectionToolbarAnchors anchors;
  final CodeLineEditingController controller;
  final bool readOnly;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final MaterialLocalizations l10n = MaterialLocalizations.of(context);
    // A collapsed caret still allows Paste and Select all — that is what makes
    // "tap, then paste" work — but Cut and Copy would act on the whole line,
    // which is not what a user tapping with no selection is asking for.
    final bool hasSelection = !controller.selection.isCollapsed;

    final List<ContextMenuButtonItem> items = <ContextMenuButtonItem>[
      if (hasSelection && !readOnly)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.cut,
          label: l10n.cutButtonLabel,
          onPressed: () {
            controller.cut();
            onDismiss();
          },
        ),
      if (hasSelection)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          label: l10n.copyButtonLabel,
          onPressed: () async {
            await controller.copy();
            onDismiss();
          },
        ),
      if (!readOnly)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          label: l10n.pasteButtonLabel,
          onPressed: () {
            controller.paste();
            onDismiss();
          },
        ),
      ContextMenuButtonItem(
        type: ContextMenuButtonType.selectAll,
        label: l10n.selectAllButtonLabel,
        onPressed: () {
          controller.selectAll();
          onDismiss();
        },
      ),
      // No Share entry here. Share is F3 and is not built yet; a button that
      // said "Share" and only copied to the clipboard would be a lie about
      // what it did.
    ];

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: anchors,
      buttonItems: items,
    );
  }
}
