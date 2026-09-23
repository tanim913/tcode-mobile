/// Go to line: the input parser, and the jump itself.
///
/// The parser is a pure function precisely so the awkward inputs can be covered
/// here rather than through a dialog.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/features/editor/application/editor_actions.dart';
import 'package:pocket_code/features/editor/presentation/go_to_line_dialog.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  group('parseLineInput', () {
    test('accepts a plain line number in range', () {
      expect(parseLineInput('12', lineCount: 20), 12);
      expect(parseLineInput('1', lineCount: 20), 1);
      expect(parseLineInput('20', lineCount: 20), 20,
          reason: 'the last line is a valid destination');
    });

    test('trims surrounding whitespace', () {
      expect(parseLineInput('  7  ', lineCount: 20), 7);
    });

    test('accepts a trailing colon and a column suffix', () {
      // Both come from pasting a fragment like `main.dart:42:9`.
      expect(parseLineInput('42:', lineCount: 100), 42);
      expect(parseLineInput('42:9', lineCount: 100), 42,
          reason: 'the column is dropped, because this only places the line');
    });

    test('rejects out-of-range, zero, negative and non-numeric input', () {
      expect(parseLineInput('0', lineCount: 20), isNull,
          reason: 'line numbers shown to the user are 1-based');
      expect(parseLineInput('21', lineCount: 20), isNull);
      expect(parseLineInput('-3', lineCount: 20), isNull);
      expect(parseLineInput('abc', lineCount: 20), isNull);
      expect(parseLineInput('', lineCount: 20), isNull);
      expect(parseLineInput('   ', lineCount: 20), isNull);
      expect(parseLineInput(':', lineCount: 20), isNull);
    });
  });

  group('EditorActions.goToLine', () {
    late CodeLineEditingController controller;

    setUp(() {
      controller = CodeLineEditingController.fromText('one\ntwo\nthree\nfour');
    });

    tearDown(() => controller.dispose());

    test('reports the line count', () {
      expect(EditorActions(controller).lineCount, 4);
    });

    test('moves the cursor to the start of the requested line', () {
      final bool moved = EditorActions(controller).goToLine(3);

      expect(moved, isTrue);
      expect(controller.selection.extentIndex, 2,
          reason: 'line 3 is index 2; the API is 1-based, the buffer is not');
      expect(controller.selection.extentOffset, 0);
      expect(controller.selection.isCollapsed, isTrue,
          reason: 'jumping to a line must not select it');
    });

    test('refuses a line outside the buffer and leaves the cursor alone', () {
      EditorActions(controller).goToLine(2);
      final int before = controller.selection.extentIndex;

      expect(EditorActions(controller).goToLine(99), isFalse);
      expect(EditorActions(controller).goToLine(0), isFalse);
      expect(controller.selection.extentIndex, before,
          reason: 'a rejected jump must not move the cursor anyway');
    });

    test('does not change the text', () {
      EditorActions(controller).goToLine(4);
      expect(controller.text, 'one\ntwo\nthree\nfour');
    });
  });
}
