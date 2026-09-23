/// Decoding and encoding of text files, preserving their physical format.
///
/// Pure Dart with no platform dependencies, so every rule here is covered by
/// fast unit tests rather than discovered on a device.
///
/// The contract that matters: the editor always works with `\n` line endings
/// internally, and [encodeText] puts the file's original endings, BOM and
/// final-newline state back on the way out. A user who opens a CRLF file and
/// changes one character gets a one-line diff, not a whole-file rewrite.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/text_format.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';

abstract final class TextCodec {
  static const List<int> _utf8Bom = <int>[0xEF, 0xBB, 0xBF];
  static const List<int> _utf16leBom = <int>[0xFF, 0xFE];
  static const List<int> _utf16beBom = <int>[0xFE, 0xFF];

  /// A file is treated as binary if it contains a null byte in its first 8 KB.
  ///
  /// This is the same heuristic git uses. It is not perfect — UTF-16 text
  /// contains null bytes — so the BOM check runs first.
  static bool isBinary(Uint8List bytes) {
    if (_startsWith(bytes, _utf16leBom) || _startsWith(bytes, _utf16beBom)) {
      return false;
    }
    final int limit = bytes.length < AppLimits.binarySniffBytes
        ? bytes.length
        : AppLimits.binarySniffBytes;
    for (int i = 0; i < limit; i++) {
      if (bytes[i] == 0) {
        return true;
      }
    }
    return false;
  }

  /// Identifies the encoding from a byte-order mark alone.
  ///
  /// Returns null when there is no BOM, in which case UTF-8 is assumed and
  /// verified by actually decoding.
  static TextEncoding? encodingFromBom(Uint8List bytes) {
    if (_startsWith(bytes, _utf8Bom)) {
      return TextEncoding.utf8Bom;
    }
    // UTF-16 LE and BE BOMs share no prefix, so order does not matter, but
    // both must be checked before falling through.
    if (_startsWith(bytes, _utf16leBom)) {
      return TextEncoding.utf16le;
    }
    if (_startsWith(bytes, _utf16beBom)) {
      return TextEncoding.utf16be;
    }
    return null;
  }

  /// Decodes [bytes] into text plus the format they were stored in.
  ///
  /// When [forced] is null the encoding is detected. Detection failing is not a
  /// crash — it throws [EncodingFailure] so the caller can offer "Reopen as
  /// Latin-1" rather than silently substituting replacement characters into a
  /// file the user might then save.
  static TextFileContents decode(Uint8List bytes, {TextEncoding? forced}) {
    final TextEncoding encoding = forced ?? encodingFromBom(bytes) ?? TextEncoding.utf8;

    final String raw;
    switch (encoding) {
      case TextEncoding.utf8:
        raw = _decodeUtf8(bytes, 0);
      case TextEncoding.utf8Bom:
        raw = _decodeUtf8(bytes, _utf8Bom.length);
      case TextEncoding.utf16le:
        raw = _decodeUtf16(bytes, littleEndian: true);
      case TextEncoding.utf16be:
        raw = _decodeUtf16(bytes, littleEndian: false);
      case TextEncoding.latin1:
        raw = latin1.decode(bytes, allowInvalid: true);
    }

    final LineEnding dominant = detectLineEnding(raw);
    final bool mixed = hasMixedLineEndings(raw);
    final bool trailingNewline =
        raw.endsWith('\n') || raw.endsWith('\r');

    return TextFileContents(
      // Normalise to \n for the editor. CR-only files are handled too.
      text: raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
      format: TextFormat(
        encoding: encoding,
        lineEnding: dominant,
        endsWithNewline: trailingNewline,
        hasMixedLineEndings: mixed,
      ),
    );
  }

  /// Turns editor text back into bytes in the file's original format.
  static Uint8List encodeText(String text, TextFormat format) {
    // The editor's text is \n-only, so restoring endings is a single pass.
    String out = format.lineEnding == LineEnding.lf
        ? text
        : text.replaceAll('\n', format.lineEnding.sequence);

    // Preserve whether the file ended with a newline. Adding or removing one
    // silently is a real diff that the user did not ask for.
    final String eol = format.lineEnding.sequence;
    final bool endsNow = out.endsWith(eol);
    if (format.endsWithNewline && !endsNow && out.isNotEmpty) {
      out += eol;
    } else if (!format.endsWithNewline && endsNow) {
      out = out.substring(0, out.length - eol.length);
    }

    switch (format.encoding) {
      case TextEncoding.utf8:
        return Uint8List.fromList(utf8.encode(out));
      case TextEncoding.utf8Bom:
        return Uint8List.fromList(<int>[..._utf8Bom, ...utf8.encode(out)]);
      case TextEncoding.utf16le:
        return _encodeUtf16(out, littleEndian: true);
      case TextEncoding.utf16be:
        return _encodeUtf16(out, littleEndian: false);
      case TextEncoding.latin1:
        // Characters outside Latin-1 cannot be represented. Replace rather than
        // throw, because the user explicitly chose this encoding.
        return Uint8List.fromList(
          out.codeUnits.map((int c) => c <= 0xFF ? c : 0x3F).toList(),
        );
    }
  }

  /// The dominant line ending in [text]. LF wins ties, including for a file
  /// with no line breaks at all.
  static LineEnding detectLineEnding(String text) {
    int crlf = 0;
    int lf = 0;
    int cr = 0;
    for (int i = 0; i < text.length; i++) {
      final int c = text.codeUnitAt(i);
      if (c == 0x0D) {
        if (i + 1 < text.length && text.codeUnitAt(i + 1) == 0x0A) {
          crlf++;
          i++;
        } else {
          cr++;
        }
      } else if (c == 0x0A) {
        lf++;
      }
    }
    if (crlf > lf && crlf > cr) {
      return LineEnding.crlf;
    }
    if (cr > lf && cr > crlf) {
      return LineEnding.cr;
    }
    return LineEnding.lf;
  }

  static bool hasMixedLineEndings(String text) {
    final bool crlf = text.contains('\r\n');
    final String withoutCrlf = text.replaceAll('\r\n', '');
    final bool lf = withoutCrlf.contains('\n');
    final bool cr = withoutCrlf.contains('\r');
    return <bool>[crlf, lf, cr].where((bool b) => b).length > 1;
  }

  /// Infers tabs-vs-spaces and indent width from the file's own content.
  ///
  /// Looks at the *change* in indentation between consecutive lines rather than
  /// absolute leading whitespace, because a deeply nested block would otherwise
  /// suggest an indent size of 8 or 12.
  static IndentStyle detectIndent(String text) {
    final List<String> lines = text.split('\n');
    int tabLines = 0;
    int spaceLines = 0;
    final Map<int, int> deltaCounts = <int, int>{};
    int previousSpaces = 0;

    for (final String line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }
      int spaces = 0;
      int tabs = 0;
      for (int i = 0; i < line.length; i++) {
        final int c = line.codeUnitAt(i);
        if (c == 0x20) {
          spaces++;
        } else if (c == 0x09) {
          tabs++;
        } else {
          break;
        }
      }
      if (tabs > 0) {
        tabLines++;
        continue;
      }
      if (spaces > 0) {
        spaceLines++;
        final int delta = spaces - previousSpaces;
        if (delta > 0 && delta <= 8) {
          deltaCounts[delta] = (deltaCounts[delta] ?? 0) + 1;
        }
      }
      previousSpaces = spaces;
    }

    if (tabLines > spaceLines) {
      return const IndentStyle(useSpaces: false, size: 4);
    }
    if (deltaCounts.isEmpty) {
      return const IndentStyle.fallback();
    }
    int bestSize = 2;
    int bestCount = -1;
    deltaCounts.forEach((int size, int count) {
      if (count > bestCount) {
        bestCount = count;
        bestSize = size;
      }
    });
    return IndentStyle(useSpaces: true, size: bestSize);
  }

  /// Whether any line is long enough to make highlighting pathologically slow.
  static bool hasExcessivelyLongLines(String text) {
    int lineStart = 0;
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        if (i - lineStart > AppLimits.longLineCharacters) {
          return true;
        }
        lineStart = i + 1;
      }
    }
    return text.length - lineStart > AppLimits.longLineCharacters;
  }

  // --- internals -----------------------------------------------------------

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) {
      return false;
    }
    for (int i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }

  static String _decodeUtf8(Uint8List bytes, int skip) {
    final Uint8List body =
        skip == 0 ? bytes : Uint8List.sublistView(bytes, skip);
    try {
      // Strict: malformed input must be reported, not silently replaced.
      return const Utf8Decoder().convert(body);
    } on FormatException catch (e) {
      throw EncodingFailure(cause: e);
    }
  }

  /// Dart has no built-in UTF-16 codec, so this decodes the code units by hand.
  /// Surrogate pairs need no special handling: Dart strings are UTF-16 already.
  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final int start = bytes.length >= 2 ? 2 : 0; // skip the BOM
    final int count = (bytes.length - start) ~/ 2;
    final List<int> units = List<int>.filled(count, 0);
    for (int i = 0; i < count; i++) {
      final int lo = bytes[start + i * 2];
      final int hi = bytes[start + i * 2 + 1];
      units[i] = littleEndian ? (hi << 8) | lo : (lo << 8) | hi;
    }
    return String.fromCharCodes(units);
  }

  static Uint8List _encodeUtf16(String text, {required bool littleEndian}) {
    final List<int> units = text.codeUnits;
    final Uint8List out = Uint8List(2 + units.length * 2);
    // Byte-order mark first, so the file round-trips through this same decoder.
    if (littleEndian) {
      out[0] = 0xFF;
      out[1] = 0xFE;
    } else {
      out[0] = 0xFE;
      out[1] = 0xFF;
    }
    for (int i = 0; i < units.length; i++) {
      final int u = units[i];
      if (littleEndian) {
        out[2 + i * 2] = u & 0xFF;
        out[2 + i * 2 + 1] = (u >> 8) & 0xFF;
      } else {
        out[2 + i * 2] = (u >> 8) & 0xFF;
        out[2 + i * 2 + 1] = u & 0xFF;
      }
    }
    return out;
  }
}
