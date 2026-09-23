/// The editor actions the command palette and the toolbars invoke.
///
/// Split out of `editor_shell.dart` for size: the shell was past 900 lines and
/// these all share one shape — read the active tab, show something, act on what
/// comes back. Written as a mixin rather than free functions because every one
/// of them needs `context`, `ref` and `mounted` together.
///
/// Generic over the widget so this file does not have to import the shell,
/// which would make the dependency circular.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/document_symbol.dart';
import 'package:pocket_code/data/models/file_version.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/data/models/snippet.dart';
import 'package:pocket_code/data/repositories/history_repository.dart';
import 'package:pocket_code/features/diff/presentation/diff_view.dart';
import 'package:pocket_code/features/editor/application/editor_actions.dart';
import 'package:pocket_code/features/editor/presentation/go_to_line_dialog.dart';
import 'package:pocket_code/features/history/application/history_controller.dart';
import 'package:pocket_code/features/history/presentation/history_sheet.dart';
import 'package:pocket_code/features/outline/presentation/outline_sheet.dart';
import 'package:pocket_code/features/snippets/application/snippets_controller.dart';
import 'package:pocket_code/features/snippets/presentation/snippet_picker.dart';
import 'package:pocket_code/features/tabs/application/tabs_controller.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';
import 'package:pocket_code/services/diff/line_diff.dart';
import 'package:pocket_code/services/language/symbol_extractor.dart';

mixin ShellEditorActions<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// Closes whichever tab is active, prompting about unsaved work.
  /// Shows the file's outline and jumps to whatever is picked.
  ///
  /// Extraction runs against the live buffer, not the saved text, so the
  /// outline reflects what is on screen rather than what is on disk.
  Future<void> openOutline() async {
    final OpenTab? tab = ref.read(tabsProvider).active;
    if (tab == null) {
      return;
    }
    const SymbolExtractor extractor = RegexSymbolExtractor();
    final bool supported = extractor.supports(tab.language.id);
    final List<DocumentSymbol> symbols = supported
        ? extractor.extract(
            languageId: tab.language.id,
            text: ref.read(tabsProvider.notifier).controllerFor(tab).text,
          )
        : const <DocumentSymbol>[];

    final DocumentSymbol? chosen = await showOutline(
      context,
      symbols: symbols,
      languageSupported: supported,
      languageLabel: tab.language.label,
    );
    if (chosen == null || !mounted) {
      return;
    }
    EditorActions(ref.read(tabsProvider.notifier).controllerFor(tab))
        .goToSymbol(chosen);
  }

  /// Go to line, reached from the palette rather than the toolbar.
  Future<void> promptGoToLine() async {
    final OpenTab? tab = ref.read(tabsProvider).active;
    if (tab == null) {
      return;
    }
    await goToLineWith(
      EditorActions(ref.read(tabsProvider.notifier).controllerFor(tab)),
    );
  }

  Future<void> openFileHistory() async {
    final OpenTab? tab = ref.read(tabsProvider).active;
    final LiveRoot? root =
        ref.read(workspaceProvider)?.rootAt(tab?.rootIndex ?? -1);
    if (tab == null || root == null) {
      return;
    }
    final FileHistory history = ref.read(fileHistoryProvider);
    final HistoryFolder? folder = await history.versionsFor(
      provider: root.provider,
      rootId: root.root.rootId,
      fileId: tab.node.id,
      name: tab.node.name,
      displayPath: tab.node.displayPath,
    );
    if (!mounted) {
      return;
    }
    final FileVersion? picked = await showFileHistory(
      context,
      fileName: tab.node.name,
      versions: folder?.meta.versions ?? const <FileVersion>[],
      available: history.isAvailable,
    );
    if (picked == null || folder == null || !mounted) {
      return;
    }
    final String? older = await history.contentOf(folder, picked);
    if (older == null || !mounted) {
      return;
    }

    final String current =
        ref.read(tabsProvider.notifier).controllerFor(tab).text;
    final EditorSettings editor = ref.read(settingsProvider).editor;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DiffScreen(
          title: tab.node.name,
          subtitle: 'Before ${clockTime(picked.savedAt)}, compared with now',
          diff: diffLines(splitLines(older), splitLines(current)),
          editor: editor,
          onRestore: () {
            // Through the buffer, so the restore itself lands in the undo
            // stack and can be undone like any other edit.
            EditorActions(ref.read(tabsProvider.notifier).controllerFor(tab))
                .replaceAll(older);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> openCompareWithSaved() async {
    final OpenTab? tab = ref.read(tabsProvider).active;
    if (tab == null) {
      return;
    }
    final DiffResult diff = diffLines(
      splitLines(tab.savedText),
      splitLines(tab.text),
    );
    final EditorSettings editor = ref.read(settingsProvider).editor;
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DiffScreen(
          title: tab.node.name,
          subtitle: 'Saved, compared with now',
          diff: diff,
          editor: editor,
        ),
      ),
    );
  }

  Future<void> openSnippetPicker() async {
    final OpenTab? tab = ref.read(tabsProvider).active;
    if (tab == null) {
      return;
    }
    final List<Snippet> available =
        snippetsFor(ref.read(snippetsProvider), tab.language.id);
    final Snippet? chosen = await showSnippetPicker(
      context,
      snippets: available,
      languageLabel: tab.language.label,
    );
    if (chosen == null || !mounted) {
      return;
    }
    EditorActions(ref.read(tabsProvider.notifier).controllerFor(tab))
        .insertSnippet(chosen);
  }

  Future<void> jumpToBracket() async {
    final OpenTab? tab = ref.read(tabsProvider).active;
    if (tab == null) {
      return;
    }
    final bool moved = EditorActions(
      ref.read(tabsProvider.notifier).controllerFor(tab),
    ).jumpToMatchingBracket(lineComment: tab.language.lineComment);
    if (moved || !mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No matching bracket at the cursor.')),
    );
  }

  /// Asks for a line number, then jumps to it.
  ///
  /// The dialog validates against the live line count, so the only way to reach
  /// [EditorActions.goToLine] with a bad value is a buffer that changed while
  /// the dialog was open — hence the second check on the result.
  Future<void> goToLineWith(EditorActions actions) async {
    final int? line = await promptForLine(
      context,
      lineCount: actions.lineCount,
      currentLine: actions.controller.selection.extentIndex + 1,
    );
    if (line == null || !mounted) {
      return;
    }
    if (!actions.goToLine(line)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('That file no longer has a line $line.')),
      );
    }
  }
}
