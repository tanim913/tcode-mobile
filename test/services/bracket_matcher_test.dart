/// Finding the partner of the bracket under the cursor.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/services/language/bracket_matcher.dart';

BracketMatch? match(
  List<String> lines,
  int line,
  int offset, {
  String? lineComment = '//',
  int maxLines = 5000,
}) =>
    matchingBracket(
      lineCount: lines.length,
      lineAt: (int i) => lines[i],
      line: line,
      offset: offset,
      lineComment: lineComment,
      maxLines: maxLines,
    );

void main() {
  group('bracketAtCursor', () {
    test('finds a bracket under the cursor', () {
      expect(bracketAtCursor('a(b)', 1)?.char, '(');
    });

    test('falls back to the character before the cursor', () {
      // Tapping just past a bracket is far easier than landing on it, and is
      // what every desktop editor does too.
      expect(bracketAtCursor('a(b)', 2)?.offset, 1);
    });

    test('prefers the character under the cursor when both are brackets', () {
      expect(bracketAtCursor('()', 1)?.char, ')');
    });

    test('null when neither side is a bracket', () {
      expect(bracketAtCursor('abc', 1), isNull);
      expect(bracketAtCursor('', 0), isNull);
    });
  });

  group('same line', () {
    test('open jumps to close', () {
      expect(match(<String>['foo(bar)'], 0, 3), (line: 0, offset: 7));
    });

    test('close jumps back to open', () {
      expect(match(<String>['foo(bar)'], 0, 7), (line: 0, offset: 3));
    });

    test('nested pairs match at the right depth', () {
      //          0123456789
      expect(match(<String>['f(g(x), y)'], 0, 1), (line: 0, offset: 9));
      expect(match(<String>['f(g(x), y)'], 0, 3), (line: 0, offset: 5));
    });

    test('the three pair kinds are all matched', () {
      expect(match(<String>['[1, 2]'], 0, 0), (line: 0, offset: 5));
      expect(match(<String>['{a: 1}'], 0, 0), (line: 0, offset: 5));
      expect(match(<String>['(x)'], 0, 0), (line: 0, offset: 2));
    });

    test('a mismatched kind is not treated as a partner', () {
      expect(match(<String>['(]'], 0, 0), isNull);
    });
  });

  group('across lines', () {
    test('a brace block spanning lines matches', () {
      final List<String> lines = <String>[
        'void f() {',
        '  g();',
        '}',
      ];
      expect(match(lines, 0, 9), (line: 2, offset: 0));
      expect(match(lines, 2, 0), (line: 0, offset: 9));
    });

    test('nesting across lines keeps its depth', () {
      final List<String> lines = <String>[
        'a {',
        '  b {',
        '  }',
        '}',
      ];
      expect(match(lines, 0, 2), (line: 3, offset: 0));
      expect(match(lines, 1, 4), (line: 2, offset: 2));
    });
  });

  group('strings and comments are skipped', () {
    test('a bracket inside a string does not close the real one', () {
      expect(match(<String>['f(")")'], 0, 1), (line: 0, offset: 5));
    });

    test('an escaped quote does not end the string', () {
      expect(match(<String>[r'f("\")")'], 0, 1), (line: 0, offset: 7));
    });

    test('a bracket after a line comment is ignored', () {
      final List<String> lines = <String>['f( // )', '  x)'];
      expect(match(lines, 0, 1), (line: 1, offset: 3));
    });

    test('a bracket that is itself inside a string has no partner', () {
      expect(match(<String>['"(a)"'], 0, 1), isNull,
          reason: 'the text around it is prose, not code');
    });

    test('a language with no line comment still matches', () {
      expect(match(<String>['(a)'], 0, 0, lineComment: null),
          (line: 0, offset: 2));
    });
  });

  group('no match', () {
    test('an unclosed bracket returns null', () {
      expect(match(<String>['f(a'], 0, 1), isNull);
    });

    test('an unopened bracket returns null', () {
      expect(match(<String>['a)'], 0, 1), isNull);
    });

    test('the cursor not on a bracket returns null', () {
      expect(match(<String>['plain text'], 0, 3), isNull);
    });

    test('an out-of-range line returns null rather than throwing', () {
      expect(match(<String>['(a)'], 5, 0), isNull);
      expect(match(<String>['(a)'], -1, 0), isNull);
    });

    test('an empty buffer returns null', () {
      expect(
        matchingBracket(
          lineCount: 0,
          lineAt: (int i) => '',
          line: 0,
          offset: 0,
        ),
        isNull,
      );
    });
  });

  test('the scan budget is honoured rather than running the whole file', () {
    // 2000 lines between the braces, with a budget of 10.
    final List<String> lines = <String>[
      '{',
      for (int i = 0; i < 2000; i++) '  line $i;',
      '}',
    ];
    expect(match(lines, 0, 0, maxLines: 10), isNull);
    expect(match(lines, 0, 0), (line: 2001, offset: 0));
  });

  test('angle brackets are deliberately not matched', () {
    // `a < b` would otherwise pair with an unrelated `>` further on.
    expect(match(<String>['if (a < b) { c > d; }'], 0, 7), isNull);
  });
}
