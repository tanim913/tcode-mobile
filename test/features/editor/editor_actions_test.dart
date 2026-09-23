/// Tests for the shared editing action layer.
///
/// Run against a real `CodeLineEditingController`, so they verify the behaviour
/// the toolbar, accessory bar and future keyboard shortcuts all depend on,
/// rather than a mock of it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/data/models/accessory_key.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/data/models/snippet.dart';
import 'package:pocket_code/data/models/text_format.dart';
import 'package:pocket_code/features/editor/application/editor_actions.dart';
import 'package:pocket_code/services/language/language_registry.dart';
import 'package:pocket_code/services/language/language_service.dart';
import 'package:re_editor/re_editor.dart';

OpenTab tabFor(String fileName, String text) => OpenTab(
      node: FileNode(id: '/w/$fileName', name: fileName, displayPath: '/w/$fileName'),
      rootIndex: 0,
      text: text,
      savedText: text,
      format: const TextFormat(),
      language: const LexicalLanguageService().detectByName(fileName),
      indent: const IndentStyle(useSpaces: true, size: 2),
    );

CodeLineEditingController controllerFor(String text) {
  final CodeLineEditingController c =
      CodeLineEditingController.fromText(text);
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('insertion', () {
    test('inserts at the cursor', () {
      final CodeLineEditingController c = controllerFor('ab');
      c.selection = const CodeLineSelection.collapsed(index: 0, offset: 1);

      EditorActions(c).insert('X');

      expect(c.text, 'aXb');
    });

    test('replaces the selection', () {
      final CodeLineEditingController c = controllerFor('hello');
      c.selectAll();

      EditorActions(c).insert('{');

      expect(c.text, '{');
    });

    test('indent and outdent round-trip', () {
      final CodeLineEditingController c = controllerFor('line');
      c.selectAll();
      final EditorActions actions = EditorActions(c);

      actions.indent();
      expect(c.text.startsWith(' '), isTrue);
      actions.outdent();
      expect(c.text, 'line');
    });
  });

  group('accessory key dispatch', () {
    test('a character key inserts its text', () {
      final CodeLineEditingController c = controllerFor('');

      EditorActions(c).applyKey(const AccessoryKey.char('{'), shiftHeld: false);

      expect(c.text, '{');
    });

    test('Tab indents, Shift+Tab outdents', () {
      final CodeLineEditingController c = controllerFor('x');
      c.selectAll();
      final EditorActions actions = EditorActions(c);
      const AccessoryKey tab = AccessoryKey(AccessoryKeyKind.tab);

      actions.applyKey(tab, shiftHeld: false);
      expect(c.text.startsWith(' '), isTrue);

      c.selectAll();
      actions.applyKey(tab, shiftHeld: true);
      expect(c.text, 'x');
    });

    test('an arrow moves the cursor when Shift is off', () {
      final CodeLineEditingController c = controllerFor('abc');
      c.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);

      EditorActions(c).applyKey(
        const AccessoryKey(AccessoryKeyKind.arrowRight),
        shiftHeld: false,
      );

      expect(c.selection.extentOffset, 1);
      expect(c.selection.isCollapsed, isTrue,
          reason: 'without Shift an arrow must not start a selection');
    });

    test('an arrow extends the selection when Shift is on', () {
      final CodeLineEditingController c = controllerFor('abc');
      c.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);

      EditorActions(c).applyKey(
        const AccessoryKey(AccessoryKeyKind.arrowRight),
        shiftHeld: true,
      );

      expect(c.selection.isCollapsed, isFalse);
      expect(c.selectedText, 'a');
    });

    test('the Shift key itself changes nothing in the buffer', () {
      // The bar owns the modifier state; the action layer must not react.
      final CodeLineEditingController c = controllerFor('abc');

      EditorActions(c).applyKey(
        const AccessoryKey(AccessoryKeyKind.shift),
        shiftHeld: false,
      );

      expect(c.text, 'abc');
    });
  });

  group('cursor scrubbing', () {
    test('a positive nudge walks the cursor forward', () {
      final CodeLineEditingController c = controllerFor('abcdef');
      c.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);

      EditorActions(c).nudge(3, extend: false);

      expect(c.selection.extentOffset, 3);
    });

    test('a negative nudge walks it back', () {
      final CodeLineEditingController c = controllerFor('abcdef');
      c.selection = const CodeLineSelection.collapsed(index: 0, offset: 4);

      EditorActions(c).nudge(-2, extend: false);

      expect(c.selection.extentOffset, 2);
    });

    test('scrubbing with Shift held selects instead of moving', () {
      final CodeLineEditingController c = controllerFor('abcdef');
      c.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);

      EditorActions(c).nudge(3, extend: true);

      expect(c.selectedText, 'abc');
    });
  });

  group('toggle comment', () {
    test('availability follows the language, not the file', () {
      // JSON genuinely has no comment syntax, so the action must report that
      // rather than inserting something invalid.
      expect(EditorActions.canComment(LanguageRegistry.byId('json')!), isFalse);
      expect(EditorActions.canComment(LanguageRegistry.byId('dart')!), isTrue);
      expect(EditorActions.canComment(LanguageRegistry.plainText), isFalse);
    });

    test('adds and removes // for Dart', () {
      const String source = 'var x = 1;';
      final CodeLineEditingController c = controllerFor(source);
      c.selectAll();
      final EditorActions actions = EditorActions(c);
      final OpenTab tab = tabFor('main.dart', source);

      expect(actions.toggleComment(tab), isTrue);
      expect(c.text.contains('//'), isTrue);

      c.selectAll();
      expect(actions.toggleComment(tab), isTrue);
      expect(c.text, source, reason: 'toggling twice must restore the line');
    });

    test('uses # for Python, never //', () {
      const String source = 'x = 1';
      final CodeLineEditingController c = controllerFor(source);
      c.selectAll();

      EditorActions(c).toggleComment(tabFor('script.py', source));

      expect(c.text.contains('#'), isTrue);
      expect(c.text.contains('//'), isFalse);
    });

    test('returns false and changes nothing for JSON', () {
      const String source = '{"a": 1}';
      final CodeLineEditingController c = controllerFor(source);
      c.selectAll();

      expect(EditorActions(c).toggleComment(tabFor('data.json', source)), isFalse);
      expect(c.text, source);
    });

    test('a block-comment-only language uses its block markers', () {
      // HTML has no line comment, so a single-line request must still use
      // <!-- --> rather than silently doing nothing.
      const String source = '<p>hi</p>';
      final CodeLineEditingController c = controllerFor(source);
      c.selectAll();

      EditorActions(c).toggleComment(tabFor('page.html', source));

      expect(c.text.contains('<!--'), isTrue);
    });
  });

  group('insert snippet', () {
    Snippet snippetOf(String body) => Snippet(id: '1', prefix: 'x', body: body);

    test('inserts at the cursor', () {
      final CodeLineEditingController c = controllerFor('');
      EditorActions(c).insertSnippet(snippetOf('print();'));
      expect(c.text, 'print();');
    });

    test('re-indents later lines to match the current line', () {
      final CodeLineEditingController c = controllerFor('    ');
      c.selection = const CodeLineSelection.collapsed(index: 0, offset: 4);

      EditorActions(c).insertSnippet(snippetOf('if (x) {\n  y();\n}'));

      expect(c.text, '    if (x) {\n      y();\n    }',
          reason: 'a snippet dropped at column zero is unusable');
    });

    test(r'the caret lands on the $0 marker', () {
      final CodeLineEditingController c = controllerFor('');
      EditorActions(c).insertSnippet(snippetOf('if (\$0) {}'));

      expect(c.text, 'if () {}');
      expect(c.selection.extentIndex, 0);
      expect(c.selection.extentOffset, 4);
    });

    test('an insert is one undo away, like typing', () {
      final CodeLineEditingController c = controllerFor('start');
      c.selection = const CodeLineSelection.collapsed(index: 0, offset: 5);
      final EditorActions actions = EditorActions(c);

      actions.insertSnippet(snippetOf('!'));
      expect(c.text, 'start!');
      actions.undo();
      expect(c.text, 'start');
    });
  });

  group('jump to matching bracket', () {
    void place(CodeLineEditingController c, int line, int offset) {
      c.selection = CodeLineSelection.collapsed(index: line, offset: offset);
    }

    test('moves the cursor to the closing brace across lines', () {
      final CodeLineEditingController c =
          controllerFor('void f() {\n  g();\n}\n');
      place(c, 0, 9);

      expect(EditorActions(c).jumpToMatchingBracket(lineComment: '//'), isTrue);
      expect(c.selection.extentIndex, 2);
      expect(c.selection.extentOffset, 0);
    });

    test('moves back from the closing brace to the opening one', () {
      final CodeLineEditingController c =
          controllerFor('void f() {\n  g();\n}\n');
      place(c, 2, 0);

      expect(EditorActions(c).jumpToMatchingBracket(lineComment: '//'), isTrue);
      expect(c.selection.extentIndex, 0);
      expect(c.selection.extentOffset, 9);
    });

    test('leaves the cursor alone when there is no match', () {
      final CodeLineEditingController c = controllerFor('plain text\n');
      place(c, 0, 3);

      expect(EditorActions(c).jumpToMatchingBracket(), isFalse);
      expect(c.selection.extentIndex, 0);
      expect(c.selection.extentOffset, 3,
          reason: 'a failed jump must not move the cursor somewhere arbitrary');
    });

    test('an unclosed bracket reports failure', () {
      final CodeLineEditingController c = controllerFor('f(a\n');
      place(c, 0, 1);
      expect(EditorActions(c).jumpToMatchingBracket(), isFalse);
    });

    test('the cursor just past a bracket still matches it', () {
      final CodeLineEditingController c = controllerFor('f(a)\n');
      place(c, 0, 2);
      expect(EditorActions(c).jumpToMatchingBracket(), isTrue);
      expect(c.selection.extentOffset, 3);
    });

    test('works on a read-only document, because it is navigation', () {
      // Nothing here consults the edit lock: the action only moves the cursor,
      // and Go to line behaves the same way.
      final CodeLineEditingController c = controllerFor('a[b]\n');
      place(c, 0, 1);
      expect(EditorActions(c).jumpToMatchingBracket(), isTrue);
      expect(c.text, 'a[b]\n', reason: 'the buffer is untouched');
    });
  });

  group('history', () {
    test('canUndo reflects real history', () {
      final CodeLineEditingController c = controllerFor('a');
      final EditorActions actions = EditorActions(c);

      expect(actions.canUndo, isFalse);

      c.selectAll();
      actions.insert('b');
      expect(actions.canUndo, isTrue);

      actions.undo();
      expect(c.text, 'a');
    });
  });
}
