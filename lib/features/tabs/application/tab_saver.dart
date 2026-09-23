/// Writing a tab's buffer back to disk, and deciding when that happens.
///
/// Split out of `TabsController` because every save route in the app funnels
/// through [save] — the toolbar, the command, the auto-save timer and the
/// focus-lost hook — which makes this the one place a feature that must observe
/// saves can hook in.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/features/history/application/history_controller.dart';
import 'package:pocket_code/features/tabs/application/tabs_state.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';

mixin TabSaver on Notifier<TabsState> {
  Timer? _autoSaveTimer;

  /// Swaps one tab in place. Implemented by `TabsController`, which owns how
  /// state is assembled.
  void replaceTab(int index, OpenTab tab);

  /// Writes a tab to disk.
  ///
  /// [auto] marks a save the user did not ask for — the debounce timer or the
  /// focus-lost hook. File history uses it to coalesce: an explicit save is
  /// always recorded, an automatic one only when enough has changed or enough
  /// time has passed.
  Future<bool> save([int? index]) => saveTab(index: index);

  /// The single write point. Every save route funnels through it, which is
  /// what makes it the one place a feature that must observe saves can hook
  /// into.
  Future<bool> saveTab({int? index, bool auto = false}) async {
    final int target = index ?? state.activeIndex;
    if (target < 0 || target >= state.tabs.length) {
      return true;
    }
    final OpenTab tab = state.tabs[target];
    if (!tab.isDirty) {
      return true;
    }
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(tab.rootIndex);
    if (root == null) {
      return false;
    }
    // Before the write, of the content that is about to be lost. See
    // `history_controller.dart` for why that direction is the useful one.
    await ref.read(fileHistoryProvider).recordSave(
          provider: root.provider,
          rootId: root.root.rootId,
          fileId: tab.node.id,
          name: tab.node.name,
          displayPath: tab.node.displayPath,
          previousText: tab.savedText,
          nextText: tab.text,
          explicit: !auto,
        );

    try {
      await root.provider.writeText(tab.node.id, tab.text, tab.format);
      replaceTab(
        target,
        tab.copyWith(savedText: tab.text, externallyChanged: false),
      );
      state = state.copyWith(clearError: true);
      return true;
    } on AppFailure catch (failure) {
      state = state.copyWith(error: failure);
      return false;
    }
  }

  Future<bool> saveAll({bool auto = false}) async {
    bool allOk = true;
    for (int i = 0; i < state.tabs.length; i++) {
      if (state.tabs[i].isDirty && !await saveTab(index: i, auto: auto)) {
        allOk = false;
      }
    }
    return allOk;
  }

  void scheduleAutoSave() {
    final AppSettings settings = ref.read(settingsProvider);
    if (settings.editor.autoSaveMode != AutoSaveMode.afterDelay) {
      return;
    }
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(
      Duration(milliseconds: settings.editor.autoSaveDelayMs),
      () => unawaited(saveAll(auto: true)),
    );
  }

  void cancelAutoSave() => _autoSaveTimer?.cancel();

  /// Called when the app loses focus, for the "save on focus lost" mode.
  Future<void> onFocusLost() async {
    if (ref.read(settingsProvider).editor.autoSaveMode ==
        AutoSaveMode.onFocusLost) {
      await saveAll(auto: true);
    }
  }
}
