/// Which tabs are showing a rendered preview instead of their source.
///
/// Held per tab key rather than on [OpenTab], for two reasons: it is view
/// state, not document state, so it has no business in the session file; and
/// `OpenTab.restriction` is fixed at load time and deliberately not in
/// `copyWith`, so it cannot be toggled.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/features/tabs/application/tabs_controller.dart';
import 'package:pocket_code/features/tabs/application/tabs_state.dart';
import 'package:pocket_code/services/language/language_definition.dart';

class PreviewMode extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    // Prune on every tab change rather than hooking each close path — tabs
    // close through close, closeOthers, closeToTheRight, closeSaved, closeAll
    // and a workspace switch, and missing one would leave a reopened file
    // mysteriously in preview.
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

  bool isPreviewing(String tabKey) => state.contains(tabKey);

  void toggle(String tabKey) {
    state = state.contains(tabKey)
        ? (<String>{...state}..remove(tabKey))
        : <String>{...state, tabKey};
  }
}

final NotifierProvider<PreviewMode, Set<String>> previewModeProvider =
    NotifierProvider<PreviewMode, Set<String>>(PreviewMode.new);

/// Whether a document can be previewed at all.
///
/// Markdown only today. Everything else has no renderer, so the action is
/// disabled rather than offered and then doing nothing.
bool canPreview(LanguageDefinition language) => language.id == 'markdown';

/// Whether [tab] is a Markdown document that can be previewed.
bool tabCanPreview(OpenTab tab) =>
    canPreview(tab.language) && tab.restriction != DocumentRestriction.binary;
