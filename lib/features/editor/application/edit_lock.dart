/// The per-tab edit lock behind the app bar's edit toggle.
///
/// Held per tab key, like [previewModeProvider], and for the same reasons: it
/// is view state rather than document state, so it has no business in the
/// session file, and `OpenTab.restriction` is fixed at load time and
/// deliberately absent from `copyWith`.
///
/// **The lock can only ever add read-only, never remove it.** A file that is
/// already read-only — too large to edit, binary, an image — stays that way
/// with the toggle on. Those restrictions exist to stop the app corrupting
/// something it cannot safely rewrite, and a toggle that overrode them would
/// be a button promising something the app cannot do.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/features/tabs/application/tabs_controller.dart';
import 'package:pocket_code/features/tabs/application/tabs_state.dart';

class EditLock extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    // Prune on every tab change rather than hooking each close path — tabs
    // close through close, closeOthers, closeToTheRight, closeSaved, closeAll
    // and a workspace switch, and missing one would leave a reopened file
    // mysteriously locked.
    ref.listen(tabsProvider, (TabsState? _, TabsState next) {
      final Set<String> live =
          next.tabs.map((OpenTab tab) => tab.key).toSet();
      final Set<String> kept = state.intersection(live);
      if (kept.length != state.length) {
        state = kept;
      }
    });
    return const <String>{};
  }

  bool isLocked(String tabKey) => state.contains(tabKey);

  void toggle(String tabKey) {
    state = state.contains(tabKey)
        ? (<String>{...state}..remove(tabKey))
        : <String>{...state, tabKey};
  }
}

final NotifierProvider<EditLock, Set<String>> editLockProvider =
    NotifierProvider<EditLock, Set<String>>(EditLock.new);

/// Whether [tab] can be typed into right now.
///
/// The single question every editing surface should ask — the editor, the
/// toolbars, the accessory bar and the command catalogue — so none of them can
/// disagree about whether a document is writable.
bool isTabEditable(OpenTab tab, Set<String> locked) =>
    !tab.isReadOnly && !locked.contains(tab.key);

/// Whether the toggle itself can do anything for [tab].
///
/// False when the document is already read-only for a reason the user cannot
/// override, so the button is disabled and says why rather than appearing to
/// unlock something it cannot.
bool canToggleEditing(OpenTab? tab) => tab != null && !tab.isReadOnly;
