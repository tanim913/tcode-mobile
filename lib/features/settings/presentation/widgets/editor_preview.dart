/// A live sample of the editor, rendered with the settings as they stand.
///
/// The point is that font, size, line height and colour theme are choices you
/// cannot judge from a label — the user should see the result here rather than
/// leaving the screen, changing their mind and coming back.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/core/theme/app_theme.dart';
import 'package:pocket_code/core/theme/editor_color_theme.dart';
import 'package:pocket_code/core/theme/editor_theme_mapper.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/services/language/language_registry.dart';
import 'package:re_editor/re_editor.dart';

/// Short enough to fit on a phone, long enough to show a keyword, a type, a
/// string and a comment — the four things a colour theme is judged on.
const String _sample = '''
// A live preview of your editor settings.
class Greeter {
  const Greeter(this.name);
  final String name;
  String greet() => 'Hello, \$name';
}''';

const int _sampleLineCount = 6;

/// Glyph pairs that a programming font draws as ligatures.
const String _ligatureSample = '=>  !=  >=  ==  ->  ...';

class EditorPreview extends ConsumerStatefulWidget {
  const EditorPreview({super.key});

  @override
  ConsumerState<EditorPreview> createState() => _EditorPreviewState();
}

class _EditorPreviewState extends ConsumerState<EditorPreview> {
  final CodeLineEditingController _code =
      CodeLineEditingController.fromText(_sample);

  /// Deliberately unfocusable. `re_editor` 0.10.0 starts a cursor-blink timer
  /// on focus that `stopBlink()` does not cancel, and disposing inside that
  /// 100 ms window writes to a disposed notifier. A preview that can never take
  /// focus can never start the timer — which is also the honest behaviour, since
  /// this sample is not editable.
  final FocusNode _focus = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
  );

  @override
  void dispose() {
    _focus.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppColorTokens tokens = theme.extension<AppColorTokens>()!;
    final AppSettings settings = ref.watch(settingsProvider);
    final EditorSettings editor = settings.editor;
    final EditorColorTheme colors = editorThemeFor(settings, theme.brightness);

    // The editor has its own zoom, so the preview is sized from the chosen font
    // metrics rather than the system text scale — otherwise it would report a
    // size the real editor will not use. Bounded so an extreme font size cannot
    // push the rest of the screen off the bottom.
    final double lineExtent = editor.fontSize * editor.lineHeight;
    final double height =
        math.min(math.max(lineExtent * _sampleLineCount + 16, 110), 240);

    return Semantics(
      container: true,
      label: 'Editor preview',
      hint: 'A code sample drawn with your current editor settings.',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: tokens.border),
              borderRadius:
                  const BorderRadius.all(Radius.circular(AppTheme.radius)),
            ),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.all(Radius.circular(AppTheme.radius)),
              child: ColoredBox(
                color: colors.background,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      height: height,
                      // Taps must not reach the editor: the list underneath
                      // should scroll, and the preview must stay unfocused.
                      child: IgnorePointer(
                        child: CodeEditor(
                          controller: _code,
                          focusNode: _focus,
                          autofocus: false,
                          readOnly: true,
                          showCursorWhenReadOnly: false,
                          wordWrap: editor.wordWrap,
                          autocompleteSymbols: false,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          style: EditorThemeMapper.styleFor(
                            theme: colors,
                            settings: editor,
                            language: LanguageRegistry.byId('dart') ??
                                LanguageRegistry.plainText,
                          ),
                          indicatorBuilder: editor.showLineNumbers
                              ? (
                                  BuildContext context,
                                  CodeLineEditingController controller,
                                  CodeChunkController chunkController,
                                  CodeIndicatorValueNotifier notifier,
                                ) =>
                                  DefaultCodeLineNumber(
                                    controller: controller,
                                    notifier: notifier,
                                    textStyle: EditorThemeMapper.gutterStyle(
                                      colors,
                                      editor,
                                    ),
                                    focusedTextStyle:
                                        EditorThemeMapper.gutterActiveStyle(
                                      colors,
                                      editor,
                                    ),
                                  )
                              : null,
                        ),
                      ),
                    ),
                    _LigatureStrip(settings: editor, colors: colors),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ligatures get their own strip because `re_editor` 0.10.0's
/// `CodeEditorStyle` has no `fontFeatures`, so the OpenType `calt` feature
/// cannot be switched off inside the editor surface. Drawing the sample with a
/// plain [Text] makes the toggle visible immediately, which is the point of a
/// preview, and is honest about where the setting does and does not apply yet.
class _LigatureStrip extends StatelessWidget {
  const _LigatureStrip({required this.settings, required this.colors});

  final EditorSettings settings;
  final EditorColorTheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.gutterText)),
      ),
      child: Row(
        children: <Widget>[
          Text(
            settings.ligatures ? 'Ligatures on' : 'Ligatures off',
            style: TextStyle(fontSize: 11, color: colors.gutterText),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _ligatureSample,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: settings.fontFamily.family,
                fontFamilyFallback: const <String>[
                  'JetBrains Mono',
                  'monospace',
                ],
                fontSize: math.min(settings.fontSize, 20),
                color: colors.foreground,
                fontFeatures: EditorThemeMapper.fontFeatures(settings),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
