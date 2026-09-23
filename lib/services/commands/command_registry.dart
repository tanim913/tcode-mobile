/// The catalogue of every registered [Command].
///
/// Held as a single instance for the app's lifetime. Features register their
/// commands during startup; the palette, toolbars and shortcut handler all read
/// from here, so none of them need to know which feature owns what.
library;

import 'package:flutter/foundation.dart';
import 'package:pocket_code/services/commands/command.dart';

class CommandRegistry extends ChangeNotifier {
  final Map<String, Command> _commands = <String, Command>{};

  /// Registration order, which is the order the palette shows them in before
  /// the user types anything.
  final List<String> _order = <String>[];

  /// Adds or replaces a command.
  ///
  /// Replacing is deliberate: a feature can re-register a command with a
  /// different handler when its context changes (for example, Save binding to
  /// whichever tab is active) without the palette needing to know.
  void register(Command command) {
    if (!_commands.containsKey(command.id)) {
      _order.add(command.id);
    }
    _commands[command.id] = command;
    notifyListeners();
  }

  void registerAll(Iterable<Command> commands) {
    for (final Command command in commands) {
      if (!_commands.containsKey(command.id)) {
        _order.add(command.id);
      }
      _commands[command.id] = command;
    }
    notifyListeners();
  }

  void unregister(String id) {
    if (_commands.remove(id) != null) {
      _order.remove(id);
      notifyListeners();
    }
  }

  Command? operator [](String id) => _commands[id];

  List<Command> get all =>
      _order.map((String id) => _commands[id]!).toList(growable: false);

  List<Command> forSurface(CommandSurface surface) => _order
      .map((String id) => _commands[id]!)
      .where((Command c) => c.surfaces.contains(surface))
      .toList(growable: false);

  /// Every command that has a keyboard shortcut, for the global shortcut map.
  List<Command> get withShortcuts =>
      all.where((Command c) => c.shortcut != null).toList(growable: false);

  /// Runs a command by id if it exists and is enabled.
  ///
  /// Returns false when the command is missing or disabled, so callers can fall
  /// back (for example, letting a keystroke reach the editor instead).
  Future<bool> run(String id) async {
    final Command? command = _commands[id];
    if (command == null || !command.enabled) {
      return false;
    }
    await command.handler();
    return true;
  }
}
