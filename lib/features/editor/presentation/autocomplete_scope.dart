/// Mounts word completion around the editor for one tab.
///
/// `CodeAutocomplete` is a **wrapper widget**, not a `CodeEditor` parameter:
/// the editor finds it with `context.findAncestorStateOfType`, so it only has
/// to be an ancestor.
///
/// **The wrapper is mounted unconditionally**, and switching completion off
/// makes the prompts builder return nothing instead. Returning a different tree
/// shape looked tidier and was wrong: toggling the edit lock changed whether
/// `CodeAutocomplete` was in the tree, which destroyed and recreated the
/// `CodeEditor` beneath it. `_CodeEditorState.initState` notifies the shared
/// editing controller (`_code_line.dart`, `delegate=`), so a remount fires a
/// notification in the middle of a build and marks the status bar's listener
/// dirty — an assertion failure in debug, and a wasted editor rebuild in
/// release. Keeping the structure fixed costs one widget and avoids both.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/features/editor/application/autocomplete_controller.dart';
import 'package:pocket_code/features/editor/application/completion_prompts.dart';
import 'package:pocket_code/features/editor/presentation/completion_popup.dart';
import 'package:re_editor/re_editor.dart';

class AutocompleteScope extends StatefulWidget {
  const AutocompleteScope({
    required this.controller,
    required this.keywords,
    required this.lineComment,
    required this.enabled,
    required this.maxFileBytes,
    required this.child,
    super.key,
  });

  final CodeLineEditingController controller;
  final List<String> keywords;
  final String? lineComment;
  final bool enabled;
  final int maxFileBytes;
  final Widget child;

  @override
  State<AutocompleteScope> createState() => _AutocompleteScopeState();
}

class _AutocompleteScopeState extends State<AutocompleteScope> {
  AutocompleteController? _index;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(AutocompleteScope old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller || old.enabled != widget.enabled) {
      _index?.dispose();
      _index = null;
      _attach();
    }
  }

  /// No index means no suggestions, which is how the feature is switched off
  /// without changing the shape of the tree.
  Set<String> get _words => _index?.words ?? const <String>{};

  void _attach() {
    if (!widget.enabled) {
      return;
    }
    _index = AutocompleteController(
      controller: widget.controller,
      maxFileBytes: widget.maxFileBytes,
    );
  }

  @override
  void dispose() {
    _index?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CodeAutocomplete(
      viewBuilder: (
        BuildContext context,
        ValueNotifier<CodeAutocompleteEditingValue> notifier,
        ValueChanged<CodeAutocompleteResult> onSelected,
      ) =>
          CompletionPopup(notifier: notifier, onSelected: onSelected),
      promptsBuilder: WordPromptsBuilder(
        enabled: () => widget.enabled,
        bufferWords: () => _words,
        keywords: () => widget.keywords,
        lineComment: () => widget.lineComment,
      ),
      child: widget.child,
    );
  }
}
