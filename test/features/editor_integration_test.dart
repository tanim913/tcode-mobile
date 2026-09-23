/// Verifies that our theming and language layers actually drive `re_editor`,
/// and that a large file renders without blowing the frame budget.
///
/// This is the durable half of the M0 editor spike: the timing numbers are
/// measured on a device, but "it renders at all, with our colours, at 5,000
/// lines" is something a test can hold onto permanently.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/core/theme/editor_theme_mapper.dart';
import 'package:pocket_code/core/theme/editor_themes/pocket_dark.dart';
import 'package:pocket_code/core/theme/editor_themes/pocket_light.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/services/language/language_definition.dart';
import 'package:pocket_code/services/language/language_registry.dart';
import 'package:pocket_code/services/language/language_service.dart';
import 'package:re_editor/re_editor.dart';

String generateDart(int approximateLines) {
  final StringBuffer buffer = StringBuffer();
  int written = 0;
  int index = 0;
  while (written < approximateLines) {
    buffer.writeln('/// Generated class $index.');
    buffer.writeln('class Generated$index {');
    buffer.writeln('  const Generated$index(this.value);');
    buffer.writeln('  final int value; // $index');
    buffer.writeln('  int doubled() => value * 2;');
    buffer.writeln('}');
    buffer.writeln();
    written += 7;
    index++;
  }
  return buffer.toString();
}

Future<void> pumpEditor(
  WidgetTester tester,
  CodeLineEditingController controller, {
  EditorSettings settings = const EditorSettings(),
  LanguageDefinition? language,
}) async {
  final LanguageDefinition lang =
      language ?? const LexicalLanguageService().detectByName('main.dart');
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CodeEditor(
          controller: controller,
          style: EditorThemeMapper.styleFor(
            theme: pocketDarkEditorTheme,
            settings: settings,
            language: lang,
          ),
          indicatorBuilder: (
            BuildContext context,
            CodeLineEditingController c,
            CodeChunkController chunk,
            CodeIndicatorValueNotifier notifier,
          ) {
            return DefaultCodeLineNumber(
              controller: c,
              notifier: notifier,
              textStyle: EditorThemeMapper.gutterStyle(
                pocketDarkEditorTheme,
                settings,
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Tears the editor out of the tree before the test ends.
///
/// Two things need care here, both caused by re_editor 0.10.0's cursor blink:
///
///  1. A periodic blink timer runs while the editor is mounted, and the test
///     framework fails any test that ends with a timer pending. Replacing the
///     tree disposes the editor, which cancels it.
///  2. On Android and iOS targets, `_CodeCursorBlinkController.startBlink()`
///     also schedules a one-shot `Future.delayed(100ms)` that `stopBlink()`
///     does NOT cancel. Disposing inside that window makes it write to a
///     disposed ValueNotifier. flutter_test defaults to the Android platform,
///     so we hit it. Pumping past 100ms first lets that callback land while the
///     editor is still alive.
///
/// This is an upstream defect, not ours: closing a tab within 100ms of focusing
/// the editor would hit the same path in a debug build. Worth revisiting when
/// the editor wrapper lands in M3.
Future<void> disposeEditor(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  group('editor rendering', () {
    testWidgets('renders a small file with line numbers', (
      WidgetTester tester,
    ) async {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText('void main() {\n  print(1);\n}\n');
      addTearDown(controller.dispose);

      await pumpEditor(tester, controller);

      expect(find.byType(CodeEditor), findsOneWidget);
      expect(find.byType(DefaultCodeLineNumber), findsOneWidget);
      expect(controller.lineCount, 4);
      await disposeEditor(tester);
    });

    testWidgets('renders 5,000 lines without throwing', (
      WidgetTester tester,
    ) async {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText(generateDart(5000));
      addTearDown(controller.dispose);

      await pumpEditor(tester, controller);

      expect(controller.lineCount, greaterThanOrEqualTo(5000));
      expect(tester.takeException(), isNull);
      await disposeEditor(tester);
    });
  });

  group('theme mapping', () {
    test('a highlighted language produces a highlight theme', () {
      final CodeHighlightTheme? theme = EditorThemeMapper.highlightFor(
        theme: pocketDarkEditorTheme,
        language: LanguageRegistry.byId('dart')!,
      );
      expect(theme, isNotNull);
      expect(theme!.languages.keys, contains('dart'));
      expect(theme.theme['keyword'], isNotNull);
    });

    test('plain text produces no highlight theme rather than an empty one', () {
      // Returning null makes re_editor skip the highlight pass entirely, which
      // is both faster and honest about there being no grammar.
      expect(
        EditorThemeMapper.highlightFor(
          theme: pocketDarkEditorTheme,
          language: LanguageRegistry.plainText,
        ),
        isNull,
      );
    });

    test('editor style follows the font settings', () {
      final CodeEditorStyle style = EditorThemeMapper.styleFor(
        theme: pocketDarkEditorTheme,
        settings: const EditorSettings(
          fontSize: 22,
          fontFamily: EditorFontFamily.firaCode,
        ),
        language: LanguageRegistry.plainText,
      );
      expect(style.fontSize, 22);
      expect(style.fontFamily, 'Fira Code');
      expect(style.backgroundColor, pocketDarkEditorTheme.background);
    });

    test('turning off current-line highlight makes it transparent', () {
      final CodeEditorStyle off = EditorThemeMapper.styleFor(
        theme: pocketDarkEditorTheme,
        settings: const EditorSettings(highlightCurrentLine: false),
        language: LanguageRegistry.plainText,
      );
      expect(off.cursorLineColor, Colors.transparent);

      final CodeEditorStyle on = EditorThemeMapper.styleFor(
        theme: pocketDarkEditorTheme,
        settings: const EditorSettings(),
        language: LanguageRegistry.plainText,
      );
      expect(on.cursorLineColor, pocketDarkEditorTheme.currentLine);
    });

    test('a locked document hides the caret but keeps its colours', () {
      // Locking is about not typing. Selection and Copy must survive it, so
      // only the caret goes — everything else stays exactly as it was.
      final CodeEditorStyle locked = EditorThemeMapper.styleFor(
        theme: pocketDarkEditorTheme,
        settings: const EditorSettings(),
        language: LanguageRegistry.plainText,
        showCaret: false,
      );
      expect(locked.cursorColor, Colors.transparent);
      expect(locked.selectionColor, pocketDarkEditorTheme.selection);
      expect(locked.textColor, pocketDarkEditorTheme.foreground);
    });

    test('an editable document shows the caret', () {
      final CodeEditorStyle editable = EditorThemeMapper.styleFor(
        theme: pocketDarkEditorTheme,
        settings: const EditorSettings(),
        language: LanguageRegistry.plainText,
      );
      expect(editable.cursorColor, pocketDarkEditorTheme.cursor);
    });

    test('light and dark map to different backgrounds', () {
      expect(
        pocketLightEditorTheme.background,
        isNot(pocketDarkEditorTheme.background),
      );
    });

    test('disabling ligatures uses a font feature, not a different font', () {
      // Swapping to a no-ligature font file would change glyph metrics and
      // therefore the cursor position; the calt feature does not.
      final List<FontFeature> off = EditorThemeMapper.fontFeatures(
        const EditorSettings(ligatures: false),
      );
      expect(off, contains(const FontFeature.disable('calt')));
      expect(
        EditorThemeMapper.fontFeatures(const EditorSettings()),
        isEmpty,
      );
    });
  });

  group('editing through the controller', () {
    testWidgets('typed text, undo and redo all work', (
      WidgetTester tester,
    ) async {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText('hello');
      addTearDown(controller.dispose);
      await pumpEditor(tester, controller);

      controller.selectAll();
      controller.replaceSelection('goodbye');
      await tester.pump();
      expect(controller.text, 'goodbye');

      expect(controller.canUndo, isTrue);
      controller.undo();
      await tester.pump();
      expect(controller.text, 'hello');

      controller.redo();
      await tester.pump();
      expect(controller.text, 'goodbye');
      await disposeEditor(tester);
    });

    testWidgets('indent and outdent apply the editor indent', (
      WidgetTester tester,
    ) async {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText('line');
      addTearDown(controller.dispose);
      await pumpEditor(tester, controller);

      controller.selectAll();
      controller.applyIndent();
      await tester.pump();
      expect(controller.text.startsWith(' '), isTrue);

      controller.applyOutdent();
      await tester.pump();
      expect(controller.text, 'line');
      await disposeEditor(tester);
    });
  });
}
