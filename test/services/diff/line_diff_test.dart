/// The line diff, including the property that matters most: applying the
/// script to the old text must reproduce the new one.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/services/diff/line_diff.dart';

List<String> lines(String text) => splitLines(text);

/// Replays a diff against [a]. If the engine is right, this equals `b`.
List<String> apply(List<String> a, DiffResult diff) => <String>[
      for (final DiffLine line in diff.lines)
        if (line.op != DiffOp.delete) line.text,
    ];

void main() {
  group('splitLines', () {
    test('a trailing newline does not add an empty line', () {
      expect(splitLines('a\nb\n'), <String>['a', 'b']);
      expect(splitLines('a\nb'), <String>['a', 'b']);
    });

    test('empty text has no lines', () {
      expect(splitLines(''), isEmpty);
    });

    test('a blank line in the middle is kept', () {
      expect(splitLines('a\n\nb\n'), <String>['a', '', 'b']);
    });
  });

  group('basics', () {
    test('identical inputs produce no changes', () {
      final DiffResult d = diffLines(lines('a\nb\nc\n'), lines('a\nb\nc\n'));
      expect(d.hasChanges, isFalse);
      expect(d.stats, const DiffStats(added: 0, removed: 0));
      expect(d.lines.every((DiffLine l) => l.op == DiffOp.keep), isTrue);
    });

    test('an inserted line is reported once', () {
      final DiffResult d = diffLines(lines('a\nc\n'), lines('a\nb\nc\n'));
      expect(d.stats, const DiffStats(added: 1, removed: 0));
      expect(
        d.lines.firstWhere((DiffLine l) => l.op == DiffOp.insert).text,
        'b',
      );
    });

    test('a deleted line is reported once', () {
      final DiffResult d = diffLines(lines('a\nb\nc\n'), lines('a\nc\n'));
      expect(d.stats, const DiffStats(added: 0, removed: 1));
    });

    test('a changed line is a delete plus an insert', () {
      final DiffResult d = diffLines(lines('a\nb\nc\n'), lines('a\nB\nc\n'));
      expect(d.stats, const DiffStats(added: 1, removed: 1));
    });

    test('everything added, from empty', () {
      final DiffResult d = diffLines(const <String>[], lines('a\nb\n'));
      expect(d.stats, const DiffStats(added: 2, removed: 0));
    });

    test('everything removed, to empty', () {
      final DiffResult d = diffLines(lines('a\nb\n'), const <String>[]);
      expect(d.stats, const DiffStats(added: 0, removed: 2));
    });

    test('two empty inputs are a no-op', () {
      expect(diffLines(const <String>[], const <String>[]).lines, isEmpty);
    });
  });

  group('line numbers', () {
    test('kept lines carry both sides', () {
      final DiffResult d = diffLines(lines('a\nc\n'), lines('a\nb\nc\n'));
      final DiffLine last = d.lines.last;
      expect(last.op, DiffOp.keep);
      expect(last.oldLine, 2, reason: 'c was the second line before');
      expect(last.newLine, 3, reason: 'and the third after');
    });

    test('an insert has no old line, a delete has no new line', () {
      final DiffResult d = diffLines(lines('a\n'), lines('a\nb\n'));
      final DiffLine inserted =
          d.lines.firstWhere((DiffLine l) => l.op == DiffOp.insert);
      expect(inserted.oldLine, isNull);
      expect(inserted.newLine, 2);
    });
  });

  group('whitespace', () {
    test('re-indentation is a change by default', () {
      expect(
        diffLines(lines('x\n'), lines('    x\n')).hasChanges,
        isTrue,
      );
    });

    test('ignoring whitespace makes it no change', () {
      expect(
        diffLines(lines('x\n'), lines('    x\n'), ignoreWhitespace: true)
            .hasChanges,
        isFalse,
      );
    });
  });

  group('a moved block', () {
    test('is reported as a delete and an insert, not a whole-file rewrite', () {
      final DiffResult d = diffLines(
        lines('a\nb\nc\nd\ne\n'),
        lines('c\nd\na\nb\ne\n'),
      );
      expect(d.stats.added + d.stats.removed, lessThan(8),
          reason: 'an optimal script moves the smaller block');
      expect(apply(lines('a\nb\nc\nd\ne\n'), d), lines('c\nd\na\nb\ne\n'));
    });
  });

  group('scale', () {
    test('one changed line in a long file stays cheap and exact', () {
      final List<String> a = <String>[for (int i = 0; i < 5000; i++) 'line $i'];
      final List<String> b = List<String>.of(a)..[2500] = 'changed';

      final DiffResult d = diffLines(a, b);
      expect(d.truncated, isFalse);
      expect(d.stats, const DiffStats(added: 1, removed: 1));
      expect(apply(a, d), b);
    });

    test('beyond the cap it says it gave up rather than lying', () {
      final List<String> a = <String>[for (int i = 0; i < 30; i++) 'a$i'];
      final List<String> b = <String>[for (int i = 0; i < 30; i++) 'b$i'];

      final DiffResult d = diffLines(a, b, maxLines: 10);
      expect(d.truncated, isTrue);
      expect(d.stats, const DiffStats(added: 30, removed: 30));
      expect(apply(a, d), b, reason: 'even the fallback must be correct');
    });
  });

  group('the script always reproduces the new text', () {
    test('over randomised inputs', () {
      // The property that catches an off-by-one no example test would.
      final Random random = Random(20260913);
      for (int round = 0; round < 200; round++) {
        final List<String> a = <String>[
          for (int i = 0; i < random.nextInt(25); i++)
            String.fromCharCode(97 + random.nextInt(6)),
        ];
        final List<String> b = <String>[
          for (int i = 0; i < random.nextInt(25); i++)
            String.fromCharCode(97 + random.nextInt(6)),
        ];
        final DiffResult d = diffLines(a, b);
        expect(apply(a, d), b, reason: 'round $round: $a -> $b');
      }
    });
  });
}
