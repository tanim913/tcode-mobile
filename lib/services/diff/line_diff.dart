/// Line-based diff.
///
/// Written rather than taken from a package: `diff_match_patch` is
/// character-level, is not in the tree even transitively, and the whole of what
/// is needed here is a few hundred lines of Myers. Keeping it pure also keeps
/// it testable, which matters more than usual in this app — several of
/// `re_editor`'s own features run on isolates that never resolve under
/// `flutter_test`.
///
/// Buffers are normalised to `\n` internally (`text_codec.dart`) with the real
/// line ending held in `TextFormat`, so nothing here has to think about CRLF.
library;

import 'package:flutter/foundation.dart';
import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/core/utils/stable_hash.dart';

enum DiffOp { keep, insert, delete }

@immutable
class DiffLine {
  const DiffLine({
    required this.op,
    required this.text,
    this.oldLine,
    this.newLine,
  });

  final DiffOp op;
  final String text;

  /// 1-based line number in the old text, or null for an inserted line.
  final int? oldLine;

  /// 1-based line number in the new text, or null for a deleted line.
  final int? newLine;

  @override
  bool operator ==(Object other) =>
      other is DiffLine &&
      other.op == op &&
      other.text == text &&
      other.oldLine == oldLine &&
      other.newLine == newLine;

  @override
  int get hashCode => Object.hash(op, text, oldLine, newLine);

  @override
  String toString() => '${switch (op) {
        DiffOp.keep => ' ',
        DiffOp.insert => '+',
        DiffOp.delete => '-',
      }}$text';
}

@immutable
class DiffStats {
  const DiffStats({required this.added, required this.removed});

  final int added;
  final int removed;

  bool get isEmpty => added == 0 && removed == 0;

  @override
  bool operator ==(Object other) =>
      other is DiffStats && other.added == added && other.removed == removed;

  @override
  int get hashCode => Object.hash(added, removed);

  @override
  String toString() => '+$added -$removed';
}

@immutable
class DiffResult {
  const DiffResult({required this.lines, required this.truncated});

  final List<DiffLine> lines;

  /// True when the inputs were too large to diff properly and the result is a
  /// whole-file replacement rather than a real edit script.
  ///
  /// Reported rather than hidden: a diff that quietly gave up and claimed every
  /// line changed would be worse than one that says it did.
  final bool truncated;

  DiffStats get stats {
    int added = 0;
    int removed = 0;
    for (final DiffLine line in lines) {
      switch (line.op) {
        case DiffOp.insert:
          added++;
        case DiffOp.delete:
          removed++;
        case DiffOp.keep:
          break;
      }
    }
    return DiffStats(added: added, removed: removed);
  }

  bool get hasChanges => !stats.isEmpty;
}

/// Splits [text] into lines, without a trailing empty line for a final newline.
List<String> splitLines(String text) {
  if (text.isEmpty) {
    return const <String>[];
  }
  final List<String> lines = text.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines;
}

/// Compares [a] with [b], line by line.
///
/// [ignoreWhitespace] compares lines with leading and trailing whitespace
/// removed while still showing the original text, which is what makes a
/// re-indentation readable.
DiffResult diffLines(
  List<String> a,
  List<String> b, {
  bool ignoreWhitespace = false,
  int maxLines = AppLimits.maxDiffLines,
}) {
  if (a.length > maxLines || b.length > maxLines) {
    return DiffResult(lines: _replaceAll(a, b), truncated: true);
  }

  String key(String line) => ignoreWhitespace ? line.trim() : line;

  // Trimming the common ends first is what makes a one-line change in a long
  // file cost almost nothing.
  int head = 0;
  while (head < a.length && head < b.length && key(a[head]) == key(b[head])) {
    head++;
  }
  int tail = 0;
  while (tail < a.length - head &&
      tail < b.length - head &&
      key(a[a.length - 1 - tail]) == key(b[b.length - 1 - tail])) {
    tail++;
  }

  final List<String> midA = a.sublist(head, a.length - tail);
  final List<String> midB = b.sublist(head, b.length - tail);

  // Lines are interned to ints so the inner loop compares numbers, not strings.
  final List<String> intermediate =
      <String>[for (final String line in midA) stableHash(key(line))];
  final List<String> otherKeys =
      <String>[for (final String line in midB) stableHash(key(line))];

  final List<_Step>? script = _myers(intermediate, otherKeys, maxLines);

  final List<DiffLine> out = <DiffLine>[];
  for (int i = 0; i < head; i++) {
    out.add(DiffLine(
      op: DiffOp.keep,
      text: a[i],
      oldLine: i + 1,
      newLine: i + 1,
    ));
  }

  if (script == null) {
    // The budget ran out. Say so rather than producing a misleading script.
    for (int i = 0; i < midA.length; i++) {
      out.add(DiffLine(
        op: DiffOp.delete,
        text: midA[i],
        oldLine: head + i + 1,
      ));
    }
    for (int i = 0; i < midB.length; i++) {
      out.add(DiffLine(
        op: DiffOp.insert,
        text: midB[i],
        newLine: head + i + 1,
      ));
    }
    _appendTail(out, a, b, tail);
    return DiffResult(lines: out, truncated: true);
  }

  int oldIndex = head;
  int newIndex = head;
  for (final _Step step in script) {
    switch (step) {
      case _Step.keep:
        out.add(DiffLine(
          op: DiffOp.keep,
          text: a[oldIndex],
          oldLine: oldIndex + 1,
          newLine: newIndex + 1,
        ));
        oldIndex++;
        newIndex++;
      case _Step.delete:
        out.add(DiffLine(
          op: DiffOp.delete,
          text: a[oldIndex],
          oldLine: oldIndex + 1,
        ));
        oldIndex++;
      case _Step.insert:
        out.add(DiffLine(
          op: DiffOp.insert,
          text: b[newIndex],
          newLine: newIndex + 1,
        ));
        newIndex++;
    }
  }

  _appendTail(out, a, b, tail);
  return DiffResult(lines: out, truncated: false);
}

void _appendTail(List<DiffLine> out, List<String> a, List<String> b, int tail) {
  for (int i = 0; i < tail; i++) {
    final int oldIndex = a.length - tail + i;
    final int newIndex = b.length - tail + i;
    out.add(DiffLine(
      op: DiffOp.keep,
      text: a[oldIndex],
      oldLine: oldIndex + 1,
      newLine: newIndex + 1,
    ));
  }
}

List<DiffLine> _replaceAll(List<String> a, List<String> b) => <DiffLine>[
      for (int i = 0; i < a.length; i++)
        DiffLine(op: DiffOp.delete, text: a[i], oldLine: i + 1),
      for (int i = 0; i < b.length; i++)
        DiffLine(op: DiffOp.insert, text: b[i], newLine: i + 1),
    ];

enum _Step { keep, insert, delete }

/// Greedy Myers, recording each round so the script can be walked back.
///
/// Returns null when the edit distance exceeds the budget, so a pathological
/// input ends as a bounded "replaced" result rather than a dropped frame.
List<_Step>? _myers(List<String> a, List<String> b, int maxLines) {
  final int n = a.length;
  final int m = b.length;
  if (n == 0 && m == 0) {
    return const <_Step>[];
  }
  final int max = (n + m).clamp(0, maxLines * 2);
  final int offset = max;
  final List<int> v = List<int>.filled(2 * max + 1, 0);
  final List<List<int>> trace = <List<int>>[];

  for (int d = 0; d <= max; d++) {
    trace.add(List<int>.of(v));
    for (int k = -d; k <= d; k += 2) {
      int x;
      if (k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset])) {
        x = v[k + 1 + offset];
      } else {
        x = v[k - 1 + offset] + 1;
      }
      int y = x - k;
      while (x < n && y < m && a[x] == b[y]) {
        x++;
        y++;
      }
      v[k + offset] = x;
      if (x >= n && y >= m) {
        return _walkBack(trace, n, m, offset);
      }
    }
  }
  return null;
}

List<_Step> _walkBack(List<List<int>> trace, int n, int m, int offset) {
  final List<_Step> steps = <_Step>[];
  int x = n;
  int y = m;

  for (int d = trace.length - 1; d >= 0; d--) {
    final List<int> v = trace[d];
    final int k = x - y;

    final int previousK;
    if (k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset])) {
      previousK = k + 1;
    } else {
      previousK = k - 1;
    }
    final int previousX = v[previousK + offset];
    final int previousY = previousX - previousK;

    while (x > previousX && y > previousY) {
      steps.add(_Step.keep);
      x--;
      y--;
    }
    if (d == 0) {
      break;
    }
    if (x == previousX) {
      steps.add(_Step.insert);
      y = previousY;
    } else {
      steps.add(_Step.delete);
      x = previousX;
    }
  }
  return steps.reversed.toList();
}
