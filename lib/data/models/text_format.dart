/// How a text file is physically encoded on disk.
///
/// These are carried with every open document because the brief requires saving
/// to preserve the encoding, byte-order mark, line endings and final-newline
/// state exactly as they were found. Losing any of them silently rewrites a
/// file the user did not ask to change.
library;

import 'package:flutter/foundation.dart';

enum TextEncoding {
  utf8('UTF-8'),
  utf8Bom('UTF-8 with BOM'),
  utf16le('UTF-16 LE'),
  utf16be('UTF-16 BE'),
  latin1('Latin-1');

  const TextEncoding(this.label);

  /// Shown in the status bar and the encoding picker.
  final String label;

  bool get hasBom =>
      this == utf8Bom || this == utf16le || this == utf16be;
}

enum LineEnding {
  lf('LF', '\n'),
  crlf('CRLF', '\r\n'),
  cr('CR', '\r');

  const LineEnding(this.label, this.sequence);

  final String label;
  final String sequence;
}

/// The physical shape of a text file, discovered on read and reapplied on write.
@immutable
class TextFormat {
  const TextFormat({
    this.encoding = TextEncoding.utf8,
    this.lineEnding = LineEnding.lf,
    this.endsWithNewline = true,
    this.hasMixedLineEndings = false,
  });

  final TextEncoding encoding;

  /// The dominant line ending. A file with mixed endings is normalised to this
  /// one on save, with [hasMixedLineEndings] set so the UI can warn first.
  final LineEnding lineEnding;

  /// Whether the file ended with a newline. POSIX tools care; diffs care.
  final bool endsWithNewline;

  final bool hasMixedLineEndings;

  TextFormat copyWith({
    TextEncoding? encoding,
    LineEnding? lineEnding,
    bool? endsWithNewline,
    bool? hasMixedLineEndings,
  }) {
    return TextFormat(
      encoding: encoding ?? this.encoding,
      lineEnding: lineEnding ?? this.lineEnding,
      endsWithNewline: endsWithNewline ?? this.endsWithNewline,
      hasMixedLineEndings: hasMixedLineEndings ?? this.hasMixedLineEndings,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TextFormat &&
      other.encoding == encoding &&
      other.lineEnding == lineEnding &&
      other.endsWithNewline == endsWithNewline &&
      other.hasMixedLineEndings == hasMixedLineEndings;

  @override
  int get hashCode =>
      Object.hash(encoding, lineEnding, endsWithNewline, hasMixedLineEndings);
}

/// Whether a file uses tabs or spaces, and how many.
///
/// Detected from the file's own content where possible, because reindenting
/// someone's file to match your settings is the fastest way to ruin a diff.
@immutable
class IndentStyle {
  const IndentStyle({required this.useSpaces, required this.size});

  /// Fallback when a file gives no evidence either way (empty, or one line).
  const IndentStyle.fallback() : useSpaces = true, size = 2;

  final bool useSpaces;
  final int size;

  /// The string inserted for one indent level.
  String get unit => useSpaces ? ' ' * size : '\t';

  /// Shown in the status bar, e.g. "Spaces: 2".
  String get label => useSpaces ? 'Spaces: $size' : 'Tab: $size';

  @override
  bool operator ==(Object other) =>
      other is IndentStyle && other.useSpaces == useSpaces && other.size == size;

  @override
  int get hashCode => Object.hash(useSpaces, size);
}
