/// The live `re_editor` controllers behind the open tabs.
///
/// Split out of `TabsController` because it is a self-contained concern: three
/// maps keyed by tab key, and the rules for creating, muting and disposing
/// them. Keeping it here also keeps those maps genuinely private — a mixin's
/// fields belong to this library, so nothing outside can reach past the small
/// API below and mutate a controller behind the controller's back.
///
/// **One controller per open tab, held here rather than in a widget**, so
/// switching tabs keeps each file's undo history, cursor and scroll intact and
/// switching back is instant. Closing a tab disposes its controller, so memory
/// tracks what is actually open.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/features/tabs/application/tabs_state.dart';
import 'package:re_editor/re_editor.dart';

mixin TabEditorControllers on Notifier<TabsState> {
  /// Editor controllers by tab key. Never exposed as state — they are mutable
  /// and long-lived, which is the opposite of what Riverpod state should be.
  final Map<String, CodeLineEditingController> _controllers =
      <String, CodeLineEditingController>{};

  /// Listeners registered on those controllers, kept so they can be removed
  /// before a programmatic text change and reattached afterwards.
  final Map<String, VoidCallback> _listeners = <String, VoidCallback>{};

  /// One find controller per tab, so each file keeps its own query, match
  /// index and replace text while you switch between them.
  final Map<String, CodeFindController> _findControllers =
      <String, CodeFindController>{};

  /// Called whenever a buffer changes. Implemented by `TabsController`, which
  /// is the only place that knows what an edit means for tab state.
  void onBufferChanged(String key);

  /// The live controller for [tab], created on first use.
  CodeLineEditingController controllerFor(OpenTab tab) {
    final CodeLineEditingController? existing = _controllers[tab.key];
    if (existing != null) {
      return existing;
    }
    final CodeLineEditingController controller =
        CodeLineEditingController.fromText(tab.text);
    void listener() => onBufferChanged(tab.key);
    controller.addListener(listener);
    _controllers[tab.key] = controller;
    _listeners[tab.key] = listener;
    return controller;
  }

  /// The controller for [key] if one has been created, without creating one.
  CodeLineEditingController? controllerForKey(String key) => _controllers[key];

  /// The find controller for [tab], created on first use.
  CodeFindController findControllerFor(OpenTab tab) {
    return _findControllers.putIfAbsent(
      tab.key,
      () => CodeFindController(controllerFor(tab)),
    );
  }

  /// Opens the find panel for the active tab, focusing its input.
  void openFind({bool replace = false}) {
    final OpenTab? tab = state.active;
    if (tab == null) {
      return;
    }
    final CodeFindController find = findControllerFor(tab);
    if (replace) {
      find.replaceMode();
    } else {
      find.findMode();
    }
  }

  /// The cursor and selection of [controller], in the form a tab stores.
  EditorState editorStateOf(CodeLineEditingController controller) {
    final CodeLineSelection selection = controller.selection;
    return EditorState(
      baseLine: selection.baseIndex,
      baseOffset: selection.baseOffset,
      extentLine: selection.extentIndex,
      extentOffset: selection.extentOffset,
    );
  }

  /// Sets a controller's text without the change being reported back as a user
  /// edit, which would mark the tab dirty the moment it was opened.
  void setTextSilently(String key, String text) {
    final CodeLineEditingController? controller = _controllers[key];
    final VoidCallback? listener = _listeners[key];
    if (controller == null || listener == null) {
      return;
    }
    controller.removeListener(listener);
    controller.text = text;
    controller.clearHistory();
    controller.addListener(listener);
  }

  void disposeControllerFor(String key) {
    // The find controller listens to the editing controller, so it must go
    // first or it would be notified during the editing controller's teardown.
    _findControllers.remove(key)?.dispose();
    final CodeLineEditingController? controller = _controllers.remove(key);
    final VoidCallback? listener = _listeners.remove(key);
    if (controller != null && listener != null) {
      controller.removeListener(listener);
    }
    controller?.dispose();
  }

  void disposeAllControllers() {
    for (final String key in _controllers.keys.toList()) {
      disposeControllerFor(key);
    }
  }
}
