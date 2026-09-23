/// A single user action.
///
/// Every action in the app is a command. The bottom toolbar, the context menus,
/// the hardware keyboard shortcuts and the command palette all invoke the same
/// [Command] object, which is what guarantees that "Save" behaves identically
/// however the user reaches it — and that adding a shortcut to an existing
/// action is one line, not a second implementation.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Where a command should appear. A command can belong to several surfaces.
enum CommandSurface {
  /// Listed in the command palette.
  palette,

  /// Offered in the bottom toolbar when the keyboard is hidden.
  toolbar,

  /// Offered in the explorer's file or folder context menu.
  contextMenu,
}

/// Grouping shown as a section header in the palette.
enum CommandCategory {
  file('File'),
  edit('Edit'),
  view('View'),
  navigate('Go'),
  search('Search'),
  workspace('Workspace'),
  settings('Settings');

  const CommandCategory(this.label);

  final String label;
}

@immutable
class Command {
  const Command({
    required this.id,
    required this.title,
    required this.category,
    required this.handler,
    this.icon,
    this.shortcut,
    this.isEnabled,
    this.surfaces = const <CommandSurface>{CommandSurface.palette},
    this.description,
  });

  /// Stable, namespaced identifier, e.g. `editor.save`. Used by shortcut
  /// bindings and persisted toolbar layouts, so it must not change casually.
  final String id;

  /// Shown to the user. Sentence case.
  final String title;

  final CommandCategory category;

  /// What running the command does. Returns a Future so long actions can be
  /// awaited by whoever invoked them.
  final Future<void> Function() handler;

  final IconData? icon;

  /// Hardware keyboard binding. Null means the command has no shortcut.
  final SingleActivator? shortcut;

  /// Evaluated each time the command is displayed. Null means always enabled.
  /// Commands are disabled, not hidden, so the UI does not shift around.
  final bool Function()? isEnabled;

  final Set<CommandSurface> surfaces;

  /// Optional second line in the palette, for commands whose title is terse.
  final String? description;

  bool get enabled => isEnabled?.call() ?? true;

  /// Human-readable shortcut, e.g. `Ctrl S`. Returns null when unbound.
  String? get shortcutLabel {
    final SingleActivator? s = shortcut;
    if (s == null) {
      return null;
    }
    final List<String> parts = <String>[
      if (s.control) 'Ctrl',
      if (s.meta) 'Cmd',
      if (s.alt) 'Alt',
      if (s.shift) 'Shift',
      _keyLabel(s.trigger),
    ];
    return parts.join(' ');
  }

  static String _keyLabel(LogicalKeyboardKey key) {
    final String label = key.keyLabel;
    if (label.isNotEmpty) {
      return label.length == 1 ? label.toUpperCase() : label;
    }
    return key.debugName ?? '?';
  }
}
