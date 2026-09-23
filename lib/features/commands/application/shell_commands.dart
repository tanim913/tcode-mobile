/// Every action the shell can perform, as [Command]s.
///
/// The shell registers these once. The handlers deliberately read their state
/// through `ref` at call time rather than closing over it, so a command
/// registered at startup still acts on whatever tab is active now — no
/// re-registration on every rebuild, and no stale captured tab.
///
/// Kept out of `editor_shell.dart` because that file is already at the size
/// limit, and because a list of actions is exactly the thing the palette, the
/// toolbar and (later) the shortcut map should share.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/features/accounts/application/accounts_controller.dart';
import 'package:pocket_code/features/editor/application/edit_lock.dart';
import 'package:pocket_code/features/editor/application/editor_actions.dart';
import 'package:pocket_code/features/editor/presentation/pinch_zoom.dart';
import 'package:pocket_code/features/tabs/application/tabs_controller.dart';
import 'package:pocket_code/features/viewers/application/preview_mode.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';
import 'package:pocket_code/services/commands/command.dart';

/// The callbacks the shell owns because they need a [BuildContext] that
/// outlives a panel — dialogs, routes and the explorer animation.
class ShellCommandHooks {
  const ShellCommandHooks({
    required this.openSettings,
    required this.toggleExplorer,
    required this.goToLine,
    required this.closeWorkspace,
    required this.closeActiveTab,
    required this.quickOpen,
    required this.showOutline,
    required this.searchWorkspace,
    required this.formatDocument,
    required this.runDocument,
    required this.jumpToMatchingBracket,
    required this.insertSnippet,
    required this.compareWithSaved,
    required this.showFileHistory,
    required this.proposeChanges,
  });

  final Future<void> Function() openSettings;
  final Future<void> Function() toggleExplorer;
  final Future<void> Function() goToLine;
  final Future<void> Function() closeWorkspace;
  final Future<void> Function() closeActiveTab;
  final Future<void> Function() quickOpen;
  final Future<void> Function() showOutline;
  final Future<void> Function() searchWorkspace;
  final Future<void> Function() formatDocument;
  final Future<void> Function() runDocument;

  /// Reports when there is no matching bracket, which needs a context that
  /// outlives any panel the command was invoked from.
  final Future<void> Function() jumpToMatchingBracket;

  /// Opens the snippet picker, which needs a context that outlives the panel
  /// the command was invoked from.
  final Future<void> Function() insertSnippet;

  /// Opens the comparison screen, which is a route rather than a panel.
  final Future<void> Function() compareWithSaved;

  /// Opens the version list for the active file.
  final Future<void> Function() showFileHistory;

  /// Opens the pull request screen for the active workspace root.
  final Future<void> Function() proposeChanges;
}

/// Builds the catalogue.
///
/// Every `isEnabled` reads live state, so the palette greys out what cannot run
/// instead of failing after the user picks it.
List<Command> buildShellCommands(WidgetRef ref, ShellCommandHooks hooks) {
  OpenTab? activeTab() => ref.read(tabsProvider).active;

  EditorActions? editor() {
    final OpenTab? tab = activeTab();
    if (tab == null) {
      return null;
    }
    return EditorActions(ref.read(tabsProvider.notifier).controllerFor(tab));
  }

  /// True when there is an active tab whose buffer can be edited — honouring
  /// both the document's own restriction and the app bar's edit lock.
  bool editable() {
    final OpenTab? tab = activeTab();
    return tab != null && isTabEditable(tab, ref.read(editLockProvider));
  }

  Future<void> withEditor(void Function(EditorActions) action) async {
    final EditorActions? actions = editor();
    if (actions != null) {
      action(actions);
    }
  }

  return <Command>[
    // --- File -------------------------------------------------------------
    Command(
      id: 'file.save',
      title: 'Save',
      category: CommandCategory.file,
      icon: Icons.save_outlined,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyS, control: true),
      isEnabled: () => activeTab()?.isDirty ?? false,
      handler: () => ref.read(tabsProvider.notifier).save(),
    ),
    Command(
      id: 'file.saveAll',
      title: 'Save all',
      category: CommandCategory.file,
      icon: Icons.save_alt_outlined,
      shortcut: const SingleActivator(
        LogicalKeyboardKey.keyS,
        control: true,
        shift: true,
      ),
      isEnabled: () => ref.read(tabsProvider).anyDirty,
      handler: () => ref.read(tabsProvider.notifier).saveAll(),
    ),
    Command(
      id: 'file.closeTab',
      title: 'Close file',
      category: CommandCategory.file,
      icon: Icons.close,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyW, control: true),
      isEnabled: () => activeTab() != null,
      handler: hooks.closeActiveTab,
    ),
    Command(
      id: 'file.reopenClosed',
      title: 'Reopen closed file',
      category: CommandCategory.file,
      icon: Icons.restore_page_outlined,
      shortcut: const SingleActivator(
        LogicalKeyboardKey.keyT,
        control: true,
        shift: true,
      ),
      handler: () => ref.read(tabsProvider.notifier).reopenClosed(),
    ),

    // --- Edit -------------------------------------------------------------
    Command(
      id: 'edit.undo',
      title: 'Undo',
      category: CommandCategory.edit,
      icon: Icons.undo,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, control: true),
      isEnabled: () => editor()?.canUndo ?? false,
      handler: () => withEditor((EditorActions a) => a.undo()),
    ),
    Command(
      id: 'edit.redo',
      title: 'Redo',
      category: CommandCategory.edit,
      icon: Icons.redo,
      shortcut: const SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      ),
      isEnabled: () => editor()?.canRedo ?? false,
      handler: () => withEditor((EditorActions a) => a.redo()),
    ),
    Command(
      id: 'edit.indent',
      title: 'Indent',
      category: CommandCategory.edit,
      icon: Icons.format_indent_increase,
      isEnabled: editable,
      handler: () => withEditor((EditorActions a) => a.indent()),
    ),
    Command(
      id: 'edit.outdent',
      title: 'Outdent',
      category: CommandCategory.edit,
      icon: Icons.format_indent_decrease,
      isEnabled: editable,
      handler: () => withEditor((EditorActions a) => a.outdent()),
    ),
    Command(
      id: 'edit.toggleComment',
      title: 'Toggle comment',
      category: CommandCategory.edit,
      icon: Icons.comment_outlined,
      shortcut: const SingleActivator(LogicalKeyboardKey.slash, control: true),
      // A language with no comment syntax (JSON) disables this rather than
      // silently doing nothing when picked.
      isEnabled: () {
        final OpenTab? tab = activeTab();
        return tab != null &&
            isTabEditable(tab, ref.read(editLockProvider)) &&
            EditorActions.canComment(tab.language);
      },
      handler: () async {
        final OpenTab? tab = activeTab();
        final EditorActions? actions = editor();
        if (tab != null && actions != null) {
          actions.toggleComment(tab);
        }
      },
    ),

    Command(
      id: 'edit.formatDocument',
      title: 'Format document',
      description: 'Pretty-print JSON',
      category: CommandCategory.edit,
      icon: Icons.data_object,
      shortcut: const SingleActivator(
        LogicalKeyboardKey.keyF,
        control: true,
        alt: true,
      ),
      // JSON is the only formatter that ships. Anything else is disabled
      // rather than offered and then doing nothing.
      isEnabled: () {
        final OpenTab? tab = activeTab();
        return tab != null &&
            isTabEditable(tab, ref.read(editLockProvider)) &&
            tab.language.id == 'json';
      },
      handler: hooks.formatDocument,
    ),

    Command(
      id: 'run.document',
      title: 'Run',
      description: 'Preview an HTML page, or run a JavaScript file',
      category: CommandCategory.view,
      icon: Icons.play_arrow,
      shortcut: const SingleActivator(
        LogicalKeyboardKey.keyR,
        control: true,
        shift: true,
      ),
      // Deliberately always enabled: picking it on a C file is how the user
      // finds out *why* it cannot run, which is more use than a grey row.
      handler: hooks.runDocument,
    ),

    // --- View: preview ----------------------------------------------------
    Command(
      id: 'view.togglePreview',
      title: 'Toggle preview',
      description: 'Rendered Markdown, or the source',
      category: CommandCategory.view,
      icon: Icons.visibility_outlined,
      shortcut: const SingleActivator(
        LogicalKeyboardKey.keyV,
        control: true,
        shift: true,
      ),
      isEnabled: () {
        final OpenTab? tab = activeTab();
        return tab != null && tabCanPreview(tab);
      },
      handler: () async {
        final OpenTab? tab = activeTab();
        if (tab != null) {
          ref.read(previewModeProvider.notifier).toggle(tab.key);
        }
      },
    ),

    // --- Search -----------------------------------------------------------
    Command(
      id: 'search.find',
      title: 'Find',
      category: CommandCategory.search,
      icon: Icons.search,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyF, control: true),
      isEnabled: () => activeTab() != null,
      handler: () async => ref.read(tabsProvider.notifier).openFind(),
    ),
    Command(
      id: 'search.replace',
      title: 'Replace',
      category: CommandCategory.search,
      icon: Icons.find_replace,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyH, control: true),
      isEnabled: editable,
      handler: () async =>
          ref.read(tabsProvider.notifier).openFind(replace: true),
    ),

    Command(
      id: 'search.workspace',
      title: 'Search in workspace',
      description: 'Find, and replace, across every file',
      category: CommandCategory.search,
      icon: Icons.manage_search,
      shortcut: const SingleActivator(
        LogicalKeyboardKey.keyF,
        control: true,
        shift: true,
      ),
      isEnabled: () => ref.read(workspaceProvider) != null,
      handler: hooks.searchWorkspace,
    ),
    Command(
      id: 'workspace.proposeChanges',
      title: 'Create pull request',
      description: 'Propose the changes in a downloaded repository '
          '(a merge request on GitLab)',
      category: CommandCategory.workspace,
      icon: Icons.call_split,
      // Offered only where the network exists. The screen itself explains a
      // folder that was not downloaded, or a missing token.
      isEnabled: () =>
          ref.read(workspaceProvider) != null &&
          ref.read(httpTransportProvider).isAvailable,
      handler: hooks.proposeChanges,
    ),
    Command(
      id: 'file.localHistory',
      title: 'Local history',
      description: 'Earlier versions of this file, kept on this device',
      category: CommandCategory.file,
      icon: Icons.history,
      // Viewing history is not editing: it must work on a locked file, which
      // is exactly when someone is looking for what changed.
      isEnabled: () => activeTab() != null,
      handler: hooks.showFileHistory,
    ),
    Command(
      id: 'edit.compareWithSaved',
      title: 'Compare with saved',
      description: 'See what changed since this file was last saved',
      category: CommandCategory.edit,
      icon: Icons.difference_outlined,
      // Only useful while there is something unsaved to compare against.
      isEnabled: () => activeTab()?.isDirty ?? false,
      handler: hooks.compareWithSaved,
    ),
    Command(
      id: 'edit.insertSnippet',
      title: 'Insert snippet',
      description: 'Pick one of your saved snippets',
      category: CommandCategory.edit,
      icon: Icons.short_text,
      // No shortcut: Ctrl+Shift+S is Save all, and the palette reaches this
      // fine. Adding one later is a single line.
      isEnabled: editable,
      handler: hooks.insertSnippet,
    ),

    // --- Go ---------------------------------------------------------------
    Command(
      id: 'go.quickOpen',
      title: 'Go to file',
      description: 'Search every file in the workspace by name',
      category: CommandCategory.navigate,
      icon: Icons.description_outlined,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyP, control: true),
      isEnabled: () => ref.read(workspaceProvider) != null,
      handler: hooks.quickOpen,
    ),
    Command(
      id: 'go.symbol',
      title: 'Go to symbol',
      description: 'Outline of the classes and functions in this file',
      category: CommandCategory.navigate,
      icon: Icons.account_tree_outlined,
      shortcut: const SingleActivator(
        LogicalKeyboardKey.keyO,
        control: true,
        shift: true,
      ),
      isEnabled: () => activeTab() != null,
      handler: hooks.showOutline,
    ),
    Command(
      id: 'go.line',
      title: 'Go to line',
      category: CommandCategory.navigate,
      icon: Icons.numbers,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyG, control: true),
      isEnabled: () => activeTab() != null,
      handler: hooks.goToLine,
    ),
    Command(
      id: 'go.matchingBracket',
      title: 'Go to matching bracket',
      description: 'Jump between the brackets of the pair at the cursor',
      category: CommandCategory.navigate,
      icon: Icons.data_array,
      shortcut: const SingleActivator(
        LogicalKeyboardKey.backslash,
        control: true,
        shift: true,
      ),
      // Navigation, not editing: this must work on a locked or read-only
      // document, exactly like Go to line.
      isEnabled: () => activeTab() != null,
      handler: hooks.jumpToMatchingBracket,
    ),

    // --- View -------------------------------------------------------------
    Command(
      id: 'view.toggleExplorer',
      title: 'Toggle explorer',
      category: CommandCategory.view,
      icon: Icons.menu,
      shortcut: const SingleActivator(LogicalKeyboardKey.keyB, control: true),
      handler: hooks.toggleExplorer,
    ),
    Command(
      id: 'view.zoomIn',
      title: 'Zoom in',
      category: CommandCategory.view,
      icon: Icons.zoom_in,
      shortcut: const SingleActivator(LogicalKeyboardKey.equal, control: true),
      isEnabled: () =>
          ref.read(settingsProvider).editor.fontSize < AppLimits.maxFontSize,
      handler: () => _zoom(ref, 1),
    ),
    Command(
      id: 'view.zoomOut',
      title: 'Zoom out',
      category: CommandCategory.view,
      icon: Icons.zoom_out,
      shortcut: const SingleActivator(LogicalKeyboardKey.minus, control: true),
      isEnabled: () =>
          ref.read(settingsProvider).editor.fontSize > AppLimits.minFontSize,
      handler: () => _zoom(ref, -1),
    ),
    Command(
      id: 'view.zoomReset',
      title: 'Reset zoom',
      description: 'Back to ${AppLimits.defaultFontSize.round()} pt',
      category: CommandCategory.view,
      icon: Icons.youtube_searched_for,
      shortcut: const SingleActivator(LogicalKeyboardKey.digit0, control: true),
      isEnabled: () =>
          ref.read(settingsProvider).editor.fontSize !=
          AppLimits.defaultFontSize,
      handler: () => ref.read(settingsProvider.notifier).updateEditor(
            (EditorSettings e) =>
                e.copyWith(fontSize: AppLimits.defaultFontSize),
          ),
    ),
    Command(
      id: 'view.toggleWordWrap',
      title: 'Toggle word wrap',
      category: CommandCategory.view,
      icon: Icons.wrap_text,
      handler: () => ref.read(settingsProvider.notifier).updateEditor(
            (EditorSettings e) => e.copyWith(wordWrap: !e.wordWrap),
          ),
    ),

    // --- Workspace --------------------------------------------------------
    Command(
      id: 'workspace.close',
      title: 'Close folder',
      category: CommandCategory.workspace,
      icon: Icons.folder_off_outlined,
      isEnabled: () => ref.read(workspaceProvider) != null,
      handler: hooks.closeWorkspace,
    ),

    // --- Settings ---------------------------------------------------------
    Command(
      id: 'settings.open',
      title: 'Settings',
      category: CommandCategory.settings,
      icon: Icons.settings_outlined,
      shortcut: const SingleActivator(LogicalKeyboardKey.comma, control: true),
      handler: hooks.openSettings,
    ),
  ];
}

/// One step of keyboard zoom, clamped the same way the pinch gesture is.
Future<void> _zoom(WidgetRef ref, int steps) {
  final double current = ref.read(settingsProvider).editor.fontSize;
  return ref.read(settingsProvider.notifier).updateEditor(
        (EditorSettings e) => e.copyWith(fontSize: clampFontSize(current + steps)),
      );
}
