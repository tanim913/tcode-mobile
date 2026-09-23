/// What the tab bar, the bottom toolbar and the accessory bar do when tapped.
///
/// Split out of `editor_shell.dart` alongside `shell_editor_actions.dart`, for
/// the same reason and in the same shape: these need `context`, `ref` and
/// `mounted` together, so they are a mixin rather than free functions.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/data/models/accessory_key.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/features/editor/application/edit_lock.dart';
import 'package:pocket_code/features/editor/application/editor_actions.dart';
import 'package:pocket_code/features/editor/presentation/toolbars/bottom_toolbar.dart';
import 'package:pocket_code/features/explorer/application/tree_controller.dart';
import 'package:pocket_code/features/shell/presentation/close_prompt.dart';
import 'package:pocket_code/features/shell/presentation/explorer_scaffold.dart';
import 'package:pocket_code/features/shell/presentation/shell_editor_actions.dart';
import 'package:pocket_code/features/tabs/application/tabs_controller.dart';
import 'package:pocket_code/features/tabs/application/tabs_state.dart';
import 'package:pocket_code/features/tabs/presentation/tab_strip.dart';
import 'package:pocket_code/services/format/json_formatter.dart';
import 'package:re_editor/re_editor.dart';

mixin ShellToolbarActions<T extends ConsumerStatefulWidget>
    on ConsumerState<T>, ShellEditorActions<T> {
  /// The explorer panel, owned by the shell.
  ExplorerPanelController get panel;

  /// Runs the active document. Implemented by the shell, which owns bundling.
  Future<void> runDocument();

  /// Closes a tab, prompting first if it has unsaved changes.
  Future<void> closeTabAt(int index) async {
    final TabsController tabs = ref.read(tabsProvider.notifier);
    if (tabs.close(index)) {
      return;
    }
    final TabsState state = ref.read(tabsProvider);
    if (index < 0 || index >= state.tabs.length) {
      return;
    }
    final OpenTab tab = state.tabs[index];
    if (!mounted) {
      return;
    }
    final CloseChoice choice = await promptToClose(context, tab.node.name);
    switch (choice) {
      case CloseChoice.cancel:
        return;
      case CloseChoice.discard:
        tabs.close(index, force: true);
      case CloseChoice.save:
        if (await tabs.save(index)) {
          tabs.close(index, force: true);
        }
    }
  }

  Future<void> handleTabAction(TabAction action, int index) async {
    final TabsController tabs = ref.read(tabsProvider.notifier);
    final TabsState state = ref.read(tabsProvider);
    if (index < 0 || index >= state.tabs.length) {
      return;
    }
    final OpenTab tab = state.tabs[index];

    switch (action) {
      case TabAction.close:
        await closeTabAt(index);
      case TabAction.closeOthers:
        tabs.closeOthers(index);
      case TabAction.closeToRight:
        tabs.closeToTheRight(index);
      case TabAction.closeSaved:
        tabs.closeSaved();
      case TabAction.closeAll:
        tabs.closeAll();
      case TabAction.copyPath:
        await Clipboard.setData(ClipboardData(text: tab.node.displayPath));
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Path copied')));
        }
      case TabAction.revealInExplorer:
        await ref
            .read(treeProvider.notifier)
            .reveal(tab.rootIndex, tab.node.id);
        panel.open();
    }
  }

  Future<void> handleToolbarAction(EditorToolbarAction action) async {
    final TabsController tabs = ref.read(tabsProvider.notifier);
    final OpenTab? tab = ref.read(tabsProvider).active;
    if (tab == null) {
      return;
    }
    final EditorActions actions = EditorActions(tabs.controllerFor(tab));

    switch (action) {
      case EditorToolbarAction.undo:
        actions.undo();
      case EditorToolbarAction.redo:
        actions.redo();
      case EditorToolbarAction.find:
        tabs.openFind();
      case EditorToolbarAction.save:
        await tabs.save();
      case EditorToolbarAction.saveAll:
        await tabs.saveAll();
      case EditorToolbarAction.indent:
        actions.indent();
      case EditorToolbarAction.outdent:
        actions.outdent();
      case EditorToolbarAction.toggleComment:
        actions.toggleComment(tab);
      case EditorToolbarAction.wordWrap:
        await ref
            .read(settingsProvider.notifier)
            .updateEditor(
              (EditorSettings e) => e.copyWith(wordWrap: !e.wordWrap),
            );
      case EditorToolbarAction.goToLine:
        await goToLineWith(actions);
      case EditorToolbarAction.run:
        await runDocument();
    }
  }

  void handleAccessoryKey(AccessoryKey key, {required bool shiftHeld}) {
    final OpenTab? tab = ref.read(tabsProvider).active;
    // The bar inserts through the controller, which does not itself know about
    // the lock — so the guard has to be here or a locked file could still be
    // typed into from the accessory keys.
    if (tab == null || !isTabEditable(tab, ref.read(editLockProvider))) {
      return;
    }
    EditorActions(ref.read(tabsProvider.notifier).controllerFor(tab))
        .applyKey(key, shiftHeld: shiftHeld);
  }

  void handleAccessoryScrub(int steps, {required bool shiftHeld}) {
    final OpenTab? tab = ref.read(tabsProvider).active;
    if (tab == null) {
      return;
    }
    EditorActions(ref.read(tabsProvider.notifier).controllerFor(tab))
        .nudge(steps, extend: shiftHeld);
  }

  /// Pretty-prints the active JSON document.
  ///
  /// Applied through the controller, not by writing the file, so the change is
  /// one undo step and the buffer stays the source of truth.
  Future<void> formatDocument() async {
    final OpenTab? tab = ref.read(tabsProvider).active;
    if (tab == null || !isTabEditable(tab, ref.read(editLockProvider))) {
      return;
    }
    final CodeLineEditingController controller =
        ref.read(tabsProvider.notifier).controllerFor(tab);
    final FormatResult result =
        formatJson(controller.text, indent: tab.indent.unit);

    if (!mounted) {
      return;
    }
    switch (result) {
      case FormatSuccess(:final String text, :final bool changed):
        if (!changed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Already formatted')),
          );
          return;
        }
        controller.text = text;
      case FormatFailure(:final String message, :final int? line):
        // Nothing was changed: a half-reformatted config file is worse than an
        // untouched one, so the error points at the problem instead.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              line == null
                  ? 'Not valid JSON: $message'
                  : 'Not valid JSON on line $line: $message',
            ),
          ),
        );
    }
  }

  /// Locks or unlocks typing in the active document.
  ///
  /// Only ever adds read-only: a document the loader already marked read-only
  /// stays that way, and the button is disabled for it.
  void toggleEditing() {
    final OpenTab? tab = ref.read(tabsProvider).active;
    if (tab == null || tab.isReadOnly) {
      return;
    }
    ref.read(editLockProvider.notifier).toggle(tab.key);
  }
}
