/// Finding the bracket that closes — or opens — the one under the cursor.
///
/// Pure, and deliberately so: `re_editor` runs its own search and fold analysis
/// on spawned isolates that never resolve under `flutter_test`, so anything
/// that has to be trusted is kept out of the editor and tested directly.
///
/// Only `()`, `[]` and `{}` are matched. Angle brackets are excluded on
/// purpose: in every language with a comparison operator, `a < b` would pair
/// with the next unrelated `>` and send the cursor somewhere meaningless.
library;

import 'package:pocket_code/core/constants/limits.dart';

/// Where a match was found.
typedef BracketMatch = ({int line, int offset});

const Map<String, String> _opens = <String, String>{
  '(': ')',
  '[': ']',
  '{': '}',
};
const Map<String, String> _closes = <String, String>{
  ')': '(',
  ']': '[',
  '}': '{',
};

/// The bracket at, or immediately before, [offset] on [line].
///
/// Checking the character *before* the cursor as a fallback is what makes this
/// usable on a phone: tapping just past a `)` is far easier than landing exactly
/// on it, and every desktop editor behaves this way too.
///
/// Returns the position of the bracket to search from, or null when neither
/// side of the cursor is a bracket.
({int offset, String char})? bracketAtCursor(String lineText, int offset) {
  if (offset >= 0 && offset < lineText.length) {
    final String at = lineText[offset];
    if (_opens.containsKey(at) || _closes.containsKey(at)) {
      return (offset: offset, char: at);
    }
  }
  if (offset > 0 && offset - 1 < lineText.length) {
    final String before = lineText[offset - 1];
    if (_opens.containsKey(before) || _closes.containsKey(before)) {
      return (offset: offset - 1, char: before);
    }
  }
  return null;
}

/// Positions on [lineText] that are inside a string literal or a line comment,
/// and whose brackets must therefore be ignored.
///
/// Line-local by design. A bracket inside a block comment spanning several
/// lines is **not** detected — tracking that needs per-language state across
/// the whole file, which is the job of a grammar, not of a cursor jump. The
/// failure mode is a jump that lands on a commented-out bracket, which is
/// visible and harmless.
List<bool> maskedPositions(String lineText, {String? lineComment}) {
  final List<bool> masked = List<bool>.filled(lineText.length, false);
  String? quote;
  for (int i = 0; i < lineText.length; i++) {
    final String ch = lineText[i];
    if (quote != null) {
      masked[i] = true;
      if (ch == r'\') {
        if (i + 1 < lineText.length) {
          masked[i + 1] = true;
          i++;
        }
        continue;
      }
      if (ch == quote) {
        quote = null;
      }
      continue;
    }
    if (ch == "'" || ch == '"' || ch == '`') {
      quote = ch;
      masked[i] = true;
      continue;
    }
    if (lineComment != null &&
        lineComment.isNotEmpty &&
        lineText.startsWith(lineComment, i)) {
      for (int k = i; k < lineText.length; k++) {
        masked[k] = true;
      }
      return masked;
    }
  }
  return masked;
}

/// The partner of the bracket at the cursor, or null if there is none.
///
/// [lineAt] rather than a list of lines so nothing has to materialise the
/// buffer — `CodeLineEditingController.codeLines` is already indexable.
///
/// The scan is bounded by [maxLines] in each direction so a minified bundle on
/// one enormous line cannot stall a frame; past the budget it gives up and
/// returns null rather than reporting a wrong answer.
BracketMatch? matchingBracket({
  required int lineCount,
  required String Function(int) lineAt,
  required int line,
  required int offset,
  String? lineComment,
  int maxLines = AppLimits.bracketScanMaxLines,
}) {
  if (line < 0 || line >= lineCount) {
    return null;
  }
  final String cursorLine = lineAt(line);
  final ({int offset, String char})? start = bracketAtCursor(cursorLine, offset);
  if (start == null) {
    return null;
  }
  // A bracket that is itself inside a string or comment has no partner worth
  // finding — the text around it is prose, not code.
  if (maskedPositions(cursorLine, lineComment: lineComment)[start.offset]) {
    return null;
  }

  final bool forward = _opens.containsKey(start.char);
  final String partner =
      forward ? _opens[start.char]! : _closes[start.char]!;

  int depth = 0;
  final int limit = forward
      ? (line + maxLines).clamp(0, lineCount - 1)
      : (line - maxLines).clamp(0, lineCount - 1);

  for (int i = line; forward ? i <= limit : i >= limit; forward ? i++ : i--) {
    final String text = lineAt(i);
    final List<bool> masked =
        maskedPositions(text, lineComment: lineComment);
    final int from = i == line
        ? start.offset
        : (forward ? 0 : text.length - 1);

    for (int c = from; forward ? c < text.length : c >= 0; forward ? c++ : c--) {
      if (c >= masked.length || masked[c]) {
        continue;
      }
      final String ch = text[c];
      if (ch == start.char) {
        depth++;
      } else if (ch == partner) {
        depth--;
        if (depth == 0) {
          return (line: i, offset: c);
        }
      }
    }
  }
  return null;
}
