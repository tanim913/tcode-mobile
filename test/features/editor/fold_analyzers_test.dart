/// Which lines fold, for languages with no closing bracket.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/features/editor/application/fold_analyzers.dart';
import 'package:pocket_code/services/language/language_registry.dart';
import 'package:re_editor/re_editor.dart';

List<(int, int)> ranges(List<String> lines, {int tabSize = 4}) =>
    indentFoldRanges(
      lineCount: lines.length,
      lineAt: (int i) => lines[i],
      tabSize: tabSize,
    );

void main() {
  group('indentWidthOf', () {
    test('counts spaces', () {
      expect(indentWidthOf('    x', 4), 4);
      expect(indentWidthOf('x', 4), 0);
    });

    test('a tab advances to the next stop, it does not add a fixed width', () {
      expect(indentWidthOf('\tx', 4), 4);
      expect(indentWidthOf('  \tx', 4), 4, reason: '2 spaces then a tab is one stop');
      expect(indentWidthOf('\t\tx', 4), 8);
    });
  });

  group('indentFoldRanges', () {
    test('a python function folds its whole body', () {
      final List<(int, int)> found = ranges(<String>[
        'def f():', //     0
        '    a = 1', //    1
        '    b = 2', //    2
        'print(f())', //   3
      ]);
      expect(found, contains((0, 3)),
          reason: 'end is one past the body, because collapseChunk hides '
              'start+1 to end-1');
    });

    test('nested blocks each get a range', () {
      final List<(int, int)> found = ranges(<String>[
        'def f():', //         0
        '    if x:', //        1
        '        return 1', // 2
        '    return 0', //     3
      ]);
      expect(found, contains((0, 4)));
      expect(found, contains((1, 3)));
    });

    test('trailing blank lines are not swallowed', () {
      final List<(int, int)> found = ranges(<String>[
        'def f():', //  0
        '    a = 1', // 1
        '', //          2
        '', //          3
        'def g():', //  4
        '    b = 2', // 5
      ]);
      expect(found, contains((0, 2)),
          reason: 'the blank lines separate the functions and belong to '
              'neither');
      expect(found, contains((4, 6)));
    });

    test('a blank line inside a block does not end it', () {
      final List<(int, int)> found = ranges(<String>[
        'def f():', //  0
        '    a = 1', // 1
        '', //          2
        '    b = 2', // 3
      ]);
      expect(found, contains((0, 4)));
    });

    test('a flat file has nothing to fold', () {
      expect(ranges(<String>['a = 1', 'b = 2', 'c = 3']), isEmpty);
    });

    test('degenerate inputs are handled rather than thrown on', () {
      expect(ranges(<String>[]), isEmpty);
      expect(ranges(<String>['only']), isEmpty);
      expect(ranges(<String>['', '', '']), isEmpty);
    });

    test('a yaml mapping folds under its key', () {
      final List<(int, int)> found = ranges(<String>[
        'server:', //        0
        '  host: local', //  1
        '  port: 8080', //   2
        'debug: true', //    3
      ]);
      expect(found, contains((0, 3)));
    });
  });

  group('IndentCodeChunkAnalyzer', () {
    test('drops ranges too small to collapse', () {
      // `CodeChunk.canCollapse` needs `end - index - 1 > 0`, so a one-line
      // body that produced (0, 1) would render an arrow that does nothing.
      const IndentCodeChunkAnalyzer analyzer = IndentCodeChunkAnalyzer();
      final List<CodeChunk> chunks =
          analyzer.run(CodeLines.fromText('def f():\n    a = 1\n'));
      for (final CodeChunk chunk in chunks) {
        expect(chunk.canCollapse, isTrue, reason: '$chunk');
      }
    });
  });

  group('analyzerFor', () {
    const EditorSettings on = EditorSettings();
    const EditorSettings off = EditorSettings(codeFolding: false);

    test('returns the same instance every call', () {
      // Not a style preference. `CodeEditor.didUpdateWidget` rebuilds its
      // chunk controller when the analyser's identity changes, so a fresh
      // instance per build would re-run the isolate analysis every frame and
      // drop every collapsed region.
      final dart = LanguageRegistry.byId('dart')!;
      final python = LanguageRegistry.byId('python')!;
      expect(identical(analyzerFor(dart, on), analyzerFor(dart, on)), isTrue);
      expect(
          identical(analyzerFor(python, on), analyzerFor(python, on)), isTrue);
      expect(identical(analyzerFor(dart, off), analyzerFor(python, off)), isTrue);
    });

    test('folding off means the analyser that finds nothing', () {
      expect(analyzerFor(LanguageRegistry.byId('dart')!, off),
          isA<NonCodeChunkAnalyzer>());
    });

    test('bracket languages use the bracket analyser', () {
      for (final String id in <String>['dart', 'javascript', 'java', 'css']) {
        expect(analyzerFor(LanguageRegistry.byId(id)!, on),
            isA<DefaultCodeChunkAnalyzer>(),
            reason: id);
      }
    });

    test('python and yaml use indentation, because they have no brackets', () {
      for (final String id in kIndentFoldedLanguages) {
        expect(analyzerFor(LanguageRegistry.byId(id)!, on),
            isA<IndentCodeChunkAnalyzer>(),
            reason: id);
      }
    });

    test('every indent-folded id is a real registered language', () {
      for (final String id in kIndentFoldedLanguages) {
        expect(LanguageRegistry.byId(id), isNotNull, reason: id);
      }
    });
  });
}
