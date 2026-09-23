/// The code editing surface for the active tab.
///
/// Each tab owns its own [CodeLineEditingController], held by [TabsController].
/// This widget only ever renders whichever one is active, which is what makes
/// switching tabs instant and keeps every tab's undo history and cursor intact.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/core/theme/editor_color_theme.dart';
import 'package:pocket_code/core/theme/editor_theme_mapper.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/features/commands/presentation/command_shortcuts.dart';
import 'package:pocket_code/features/editor/application/edit_lock.dart';
import 'package:pocket_code/features/editor/application/fold_analyzers.dart';
import 'package:pocket_code/features/editor/presentation/autocomplete_scope.dart';
import 'package:pocket_code/features/editor/presentation/editor_banners.dart';
import 'package:pocket_code/features/editor/presentation/find_panel.dart';
import 'package:pocket_code/features/editor/presentation/pinch_zoom.dart';
import 'package:pocket_code/features/editor/presentation/selection_toolbar.dart';
import 'package:pocket_code/features/runner/application/run_session.dart';
import 'package:pocket_code/features/runner/presentation/run_pane.dart';
import 'package:pocket_code/features/tabs/application/tabs_controller.dart';
import 'package:pocket_code/features/tabs/application/tabs_state.dart';
import 'package:pocket_code/features/viewers/application/preview_mode.dart';
import 'package:pocket_code/features/viewers/presentation/binary_viewer.dart';
import 'package:pocket_code/features/viewers/presentation/image_viewer.dart';
import 'package:pocket_code/features/viewers/presentation/markdown_preview.dart';
import 'package:pocket_code/services/language/language_keywords.dart';
import 'package:pocket_code/services/language/language_registry.dart';
import 'package:re_editor/re_editor.dart';

class EditorPane extends ConsumerStatefulWidget {
  const EditorPane({required this.onRerun, super.key});

  /// Re-runs the document. Owned by the shell, which knows how to bundle it.
  final VoidCallback onRerun;

  @override
  ConsumerState<EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends ConsumerState<EditorPane> {
  /// One scroll controller per tab key, so scroll position survives a switch.
  final Map<String, CodeScrollController> _scrollControllers =
      <String, CodeScrollController>{};

  /// One selection toolbar controller per tab key. **Never rebuilt per frame**:
  /// each controller owns the overlay entry holding the toolbar and can only
  /// hide its own, so a fresh one per build left the previous pill on screen.
  final Map<String, SelectionToolbarController> _toolbarControllers =
      <String, SelectionToolbarController>{};

  @override
  void dispose() {
    for (final CodeScrollController controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  CodeScrollController _scrollFor(String key) =>
      _scrollControllers.putIfAbsent(key, CodeScrollController.new);

  /// The toolbar for [key], created once. Read-only is resolved when the
  /// toolbar is shown rather than captured, so toggling the edit lock still
  /// changes which buttons appear without replacing the controller.
  SelectionToolbarController _toolbarFor(String key) {
    return _toolbarControllers.putIfAbsent(
      key,
      () => buildSelectionToolbar(
        isReadOnly: () {
          final TabsState tabs = ref.read(tabsProvider);
          final int index = tabs.indexOfKey(key);
          if (index < 0) {
            return true;
          }
          return !isTabEditable(tabs.tabs[index], ref.read(editLockProvider));
        },
      ),
    );
  }

  /// Links in a preview are shown but not followed: the app has no network
  /// permission, so saying why beats a tap that appears to do nothing.
  void _explainLink(String href) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          href.startsWith('http')
              ? 'Previews do not open links: $href'
              : 'Links inside a preview are not followed: $href',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context)
        .extension<AppColorTokens>()!;
    final TabsState tabs = ref.watch(tabsProvider);
    final AppSettings settings = ref.watch(settingsProvider);
    final EditorColorTheme theme = editorThemeFor(
      settings,
      Theme.of(context).brightness,
    );
    final OpenTab? tab = tabs.active;
    final RunSession? run = ref.watch(runSessionProvider);

    if (tabs.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tabs.error != null) {
      return EditorMessage(
        icon: Icons.error_outline,
        title: tabs.error!.message,
        body: tabs.error!.hint,
        color: tokens.danger,
        tokens: tokens,
      );
    }
    if (tab == null) {
      return EditorMessage(
        icon: Icons.code_off_outlined,
        title: 'No file open',
        body: 'Pick a file in the explorer to start editing.',
        color: tokens.textMuted,
        tokens: tokens,
      );
    }

    return Column(
      children: <Widget>[
        if (tab.externallyChanged)
          ConflictBanner(
            name: tab.node.name,
            tokens: tokens,
            onReload: () =>
                ref.read(tabsProvider.notifier).reload(tabs.activeIndex),
            onKeepMine: () =>
                ref.read(tabsProvider.notifier).keepMyChanges(tabs.activeIndex),
          ),
        if (tab.notice != null)
          EditorNotice(
            message: tab.notice!,
            tokens: tokens,
            onDismiss: () =>
                ref.read(tabsProvider.notifier).dismissNotice(tabs.activeIndex),
          ),
        Expanded(
          child: run != null && run.tabKey == tab.key
              // Replaces the editor rather than splitting it: half a phone
              // screen each makes both useless. The header closes it.
              ? RunPane(
                  key: ValueKey<String>('run:${tab.key}'),
                  html: run.html,
                  title: run.title,
                  notes: run.notes,
                  onClose: () => ref.read(runSessionProvider.notifier).stop(),
                  onRerun: widget.onRerun,
                )
              : _body(tab, theme, settings),
        ),
      ],
    );
  }

  Widget _body(OpenTab tab, EditorColorTheme theme, AppSettings settings) {
    switch (tab.restriction) {
      case DocumentRestriction.image:
        return ImageViewer(node: tab.node, rootIndex: tab.rootIndex);
      case DocumentRestriction.binary:
        return BinaryViewer(node: tab.node);
      case DocumentRestriction.none:
      case DocumentRestriction.tooLargeToEdit:
      case DocumentRestriction.longLines:
        // The preview renders the live buffer, so it follows what is being
        // typed rather than what was last saved.
        if (tabCanPreview(tab) &&
            ref.watch(previewModeProvider).contains(tab.key)) {
          return MarkdownPreview(
            source: ref.read(tabsProvider.notifier).controllerFor(tab).text,
            onLinkTapped: _explainLink,
          );
        }
        return _editor(tab, theme, settings);
    }
  }

  Widget _editor(OpenTab tab, EditorColorTheme theme, AppSettings settings) {
    final TabsController tabs = ref.read(tabsProvider.notifier);
    // One question, asked once: the editor, its selection toolbar, the bottom
    // toolbar, the accessory bar and the command catalogue all read this, so
    // they cannot disagree about whether the document is writable.
    final bool readOnly = !isTabEditable(tab, ref.watch(editLockProvider));
    final CodeLineEditingController controller = tabs.controllerFor(tab);
    final (String, String)? block = tab.language.blockComment;

    return PinchZoom(
      fontSize: settings.editor.fontSize,
      // Always on for a text document — and this is only reached for one.
      // No explicit guard is needed while the explorer is open: its scrim is
      // hit-testable from the moment the panel starts sliding, so a pinch
      // cannot reach the editor and fight the panel animation.
      enabled: true,
      onCommit: (double size) => ref
          .read(settingsProvider.notifier)
          .updateEditor((EditorSettings e) => e.copyWith(fontSize: size)),
      child: ColoredBox(
        color: theme.background,
        // Must be an ancestor of the editor: `CodeAutocomplete` is found by
        // `findAncestorStateOfType`, not passed as a parameter.
        child: AutocompleteScope(
          controller: controller,
          keywords: tab.highlightingEnabled
              ? LanguageKeywords.forLanguage(tab.language)
              : const <String>[],
          lineComment: tab.language.lineComment,
          enabled: settings.editor.wordCompletion && !readOnly,
          maxFileBytes: AppLimits.completionMaxFileBytes,
          child: CodeEditor(
            // Keying by tab means switching files rebuilds the editor against the
            // right controller instead of trying to reuse the previous one's state.
            key: ValueKey<String>(tab.key),
            controller: controller,
            scrollController: _scrollFor(tab.key),
            readOnly: readOnly,
            wordWrap: settings.editor.wordWrap,
            findController: tabs.findControllerFor(tab),
            findBuilder: (
              BuildContext context,
              CodeFindController findController,
              bool readOnly,
            ) => FindPanel(controller: findController, readOnly: readOnly),
            // `autocompleteSymbols` IS auto-closing pairs: type `(` and the closing
            // half appears. It was hardcoded false, which made the settings toggle
            // do nothing.
            autocompleteSymbols: settings.editor.autoClosingPairs,
            // Must be a canonical const instance: changing the analyser's
            // identity makes re_editor rebuild the chunk controller and drop
            // every collapsed region. See `fold_analyzers.dart`.
            chunkAnalyzer: analyzerFor(tab.language, settings.editor),
            // re_editor draws selection handles but ships no toolbar, so without
            // this there is no way to copy selected text. Rebuilt per tab because
            // a read-only document must not offer Cut or Paste.
            toolbarController: _toolbarFor(tab.key),
            // Comment syntax is per-language, so the formatter is rebuilt per file
            // rather than configured once. A language with neither marker (JSON)
            // yields a formatter that no-ops, and the toolbar disables the action.
            commentFormatter: DefaultCodeCommentFormatter(
              singleLinePrefix: tab.language.lineComment,
              multiLinePrefix: block?.$1,
              multiLineSuffix: block?.$2,
            ),
            style: EditorThemeMapper.styleFor(
              showCaret: !readOnly,
              theme: theme,
              settings: settings.editor,
              // Passing plain text is how the large-file and long-line guards turn
              // highlighting off — there is no separate "highlighting" switch.
              language: tab.highlightingEnabled
                  ? tab.language
                  : LanguageRegistry.plainText,
            ),
            indicatorBuilder:
                (
                  BuildContext context,
                  CodeLineEditingController controller,
                  CodeChunkController chunkController,
                  CodeIndicatorValueNotifier notifier,
                ) {
                  return Row(
                    children: <Widget>[
                      if (settings.editor.showLineNumbers)
                        DefaultCodeLineNumber(
                          controller: controller,
                          notifier: notifier,
                          textStyle: EditorThemeMapper.gutterStyle(
                            theme,
                            settings.editor,
                          ),
                          focusedTextStyle: EditorThemeMapper.gutterActiveStyle(
                            theme,
                            settings.editor,
                          ),
                        ),
                      if (settings.editor.codeFolding)
                        DefaultCodeChunkIndicator(
                          width: 18,
                          controller: chunkController,
                          notifier: notifier,
                        ),
                    ],
                  );
                },
            // re_editor recognises Ctrl+S and dispatches an intent it ships no
            // action for, so without this the keystroke is swallowed.
            shortcutOverrideActions: editorShortcutOverrides(
              onSave: () => ref.read(tabsProvider.notifier).save(),
            ),
          ),
        ),
      ),
    );
  }
}
