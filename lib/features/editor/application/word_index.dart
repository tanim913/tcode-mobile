/// The identifiers in a buffer, for word-based completion.
///
/// Pure, and separate from everything that touches the editor, because this is
/// the part that has to be right: the rest is plumbing.
///
/// Note the word rule includes **digits and `$`**, unlike `re_editor`'s own
/// extractor, which accepts `[A-Za-z_]` only. Its rule stops at the first
/// digit, so `sha256` would be indexed as `sha` and typing the full name would
/// never match anything. Since the completion also supplies its own extractor
/// for the text before the cursor, the two agree.
library;

import 'package:pocket_code/core/constants/limits.dart';

/// Matches an identifier in any of the languages this app highlights.
final RegExp _word = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');

/// Adds every identifier on [line] to [out].
void collectWordsInto(
  String line,
  Set<String> out, {
  required int minLength,
  int maxWords = AppLimits.completionMaxIndexedWords,
}) {
  if (out.length >= maxWords) {
    return;
  }
  for (final RegExpMatch match in _word.allMatches(line)) {
    final String word = match[0]!;
    if (word.length < minLength) {
      continue;
    }
    out.add(word);
    if (out.length >= maxWords) {
      return;
    }
  }
}

/// Every identifier in a buffer of [lineCount] lines.
///
/// [lineAt] rather than a list so nothing has to materialise the buffer, and so
/// the walk can be sliced across event-loop turns by the caller.
///
/// Capped at [maxWords]: a generated data file should not be able to grow the
/// index without bound, and no one scrolls past a few hundred suggestions.
Set<String> extractWords(
  int lineCount,
  String Function(int) lineAt, {
  int minLength = AppLimits.completionMinWordLength,
  int maxWords = AppLimits.completionMaxIndexedWords,
}) {
  final Set<String> words = <String>{};
  for (int i = 0; i < lineCount; i++) {
    collectWordsInto(lineAt(i), words, minLength: minLength, maxWords: maxWords);
    if (words.length >= maxWords) {
      break;
    }
  }
  return words;
}

/// The identifier immediately before [offset] on [lineText].
///
/// Returns null when there is no identifier there, or it is shorter than
/// [minPrefix] — without that floor the popup would flash open on the first
/// letter of every word typed, which on a phone covers the line being edited.
({int start, String input})? identifierBefore(
  String lineText,
  int offset, {
  int minPrefix = AppLimits.completionMinPrefix,
}) {
  final int end = offset.clamp(0, lineText.length);
  int start = end;
  while (start > 0 && _isWordChar(lineText.codeUnitAt(start - 1))) {
    start--;
  }
  final String input = lineText.substring(start, end);
  if (input.length < minPrefix) {
    return null;
  }
  // A run that begins with a digit is a number, not an identifier being typed.
  if (_isDigit(input.codeUnitAt(0))) {
    return null;
  }
  return (start: start, input: input);
}

bool _isWordChar(int unit) =>
    _isDigit(unit) ||
    (unit >= 0x41 && unit <= 0x5A) || // A-Z
    (unit >= 0x61 && unit <= 0x7A) || // a-z
    unit == 0x5F || // _
    unit == 0x24; // $

bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

/// Whether [offset] on [lineText] sits inside a string or a line comment.
///
/// Line-local, and honest about it: a block comment spanning several lines is
/// not detected, because that needs the grammar rather than one line of text.
/// The cost of being wrong is a suggestion offered inside a comment, which is
/// harmless; the cost of running the grammar per keystroke is not.
bool insideStringOrComment(
  String lineText,
  int offset, {
  String? lineComment,
}) {
  final int end = offset.clamp(0, lineText.length);
  if (lineComment != null && lineComment.isNotEmpty) {
    final int comment = lineText.indexOf(lineComment);
    if (comment >= 0 && comment < end) {
      return true;
    }
  }
  String? quote;
  for (int i = 0; i < end; i++) {
    final String ch = lineText[i];
    if (quote != null) {
      if (ch == r'\') {
        i++;
        continue;
      }
      if (ch == quote) {
        quote = null;
      }
      continue;
    }
    if (ch == "'" || ch == '"' || ch == '`') {
      quote = ch;
    }
  }
  return quote != null;
}
