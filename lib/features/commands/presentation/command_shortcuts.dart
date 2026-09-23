/// Turns the [CommandRegistry] into a live hardware-keyboard map.
///
/// Every command already declares its `shortcut`, which is what the palette
/// prints on each row. Without this widget those labels would be a promise the
/// app does not keep, so the binding is generated from the same field rather
/// than written out a second time and left to drift.
///
/// **Precedence is deliberate.** `re_editor` binds Ctrl+Z, Ctrl+Shift+Z,
/// Ctrl+F and Ctrl+S *inside* the editor. Those win while the editor has focus,
/// because the editor's own undo stack is the right one to drive. This map sits
/// outside it and catches everything else, and the same keys anywhere else in
/// the app — the explorer, the settings screen.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/services/commands/command.dart';
import 'package:pocket_code/services/commands/command_registry.dart';
import 'package:re_editor/re_editor.dart';

class CommandShortcuts extends StatefulWidget {
  const CommandShortcuts({
    required this.registry,
    required this.child,
    super.key,
  });

  final CommandRegistry registry;
  final Widget child;

  @override
  State<CommandShortcuts> createState() => _CommandShortcutsState();
}

class _CommandShortcutsState extends State<CommandShortcuts> {
  @override
  void initState() {
    super.initState();
    widget.registry.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.registry.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final Map<ShortcutActivator, VoidCallback> bindings =
        <ShortcutActivator, VoidCallback>{};

    for (final Command command in widget.registry.withShortcuts) {
      final SingleActivator activator = command.shortcut!;
      // A disabled command must not swallow its key: falling through lets the
      // editor, or a lower map, have it instead of nothing happening.
      bindings[activator] = () {
        if (command.enabled) {
          widget.registry.run(command.id);
        }
      };
    }

    return CallbackShortcuts(bindings: bindings, child: widget.child);
  }
}

/// The editor-side half: makes `re_editor`'s own Ctrl+S actually save.
///
/// `CodeEditor` recognises the keystroke and dispatches a
/// [CodeShortcutSaveIntent], but ships no action for it — so without this,
/// Ctrl+S inside the editor is swallowed and does nothing at all.
Map<Type, Action<Intent>> editorShortcutOverrides({
  required VoidCallback onSave,
}) {
  return <Type, Action<Intent>>{
    CodeShortcutSaveIntent: CallbackAction<Intent>(
      onInvoke: (Intent _) {
        onSave();
        return null;
      },
    ),
  };
}
