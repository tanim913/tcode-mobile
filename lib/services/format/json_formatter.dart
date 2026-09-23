/// Pretty-printing and validating JSON.
///
/// The only formatter the app ships. `dart_style` was rejected because it drags
/// in `analyzer`; JSON needs neither, and `dart:convert` already parses and
/// re-encodes correctly.
///
/// Formatting is deliberately all-or-nothing: invalid JSON is reported with the
/// offset of the problem rather than partly reformatted, because a half-rewritten
/// config file is worse than an untouched one.
library;

import 'dart:convert';

/// What a format attempt produced.
sealed class FormatResult {
  const FormatResult();
}

/// The document was valid and is now formatted.
class FormatSuccess extends FormatResult {
  const FormatSuccess({required this.text, required this.changed});

  final String text;

  /// False when the document was already formatted, so the caller can avoid
  /// dirtying a clean buffer and starting an auto-save for nothing.
  final bool changed;
}

/// The document was not valid JSON. Nothing was changed.
class FormatFailure extends FormatResult {
  const FormatFailure({required this.message, this.offset, this.line});

  final String message;

  /// Character offset of the problem, when the parser reported one.
  final int? offset;

  /// 1-based line containing [offset], for "go to the problem".
  final int? line;
}

/// Re-indents [source] with [indent] spaces per level.
///
/// A tab indent is expressed by passing `\t` as the unit; the caller reads the
/// document's own indent style, so formatting a tab-indented file does not
/// silently convert it to spaces.
FormatResult formatJson(String source, {String indent = '  '}) {
  final String trimmed = source.trim();
  if (trimmed.isEmpty) {
    return const FormatFailure(message: 'There is nothing to format');
  }

  final Object? parsed;
  try {
    parsed = jsonDecode(trimmed);
  } on FormatException catch (e) {
    return FormatFailure(
      message: e.message,
      offset: e.offset,
      line: e.offset == null ? null : _lineOf(source, e.offset!),
    );
  }

  final String formatted = JsonEncoder.withIndent(indent).convert(parsed);
  // Preserve a trailing newline if the file had one: adding or removing one is
  // a real diff, and this command is not meant to produce one.
  final String out = source.endsWith('\n') ? '$formatted\n' : formatted;
  return FormatSuccess(text: out, changed: out != source);
}

/// True when [source] parses as JSON. Used to enable the action honestly.
bool isValidJson(String source) {
  if (source.trim().isEmpty) {
    return false;
  }
  try {
    jsonDecode(source);
    return true;
  } on FormatException {
    return false;
  }
}

/// 1-based line number containing [offset].
int _lineOf(String source, int offset) {
  final int limit = offset.clamp(0, source.length);
  int line = 1;
  for (int i = 0; i < limit; i++) {
    if (source.codeUnitAt(i) == 0x0A) {
      line++;
    }
  }
  return line;
}
