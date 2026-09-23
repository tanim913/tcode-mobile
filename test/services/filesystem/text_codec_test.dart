import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/text_format.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/filesystem/text_codec.dart';

Uint8List bytesOf(List<int> b) => Uint8List.fromList(b);

void main() {
  group('binary detection', () {
    test('plain text is not binary', () {
      expect(TextCodec.isBinary(bytesOf(utf8.encode('hello world'))), isFalse);
    });

    test('a null byte in the first 8 KB means binary', () {
      expect(TextCodec.isBinary(bytesOf(<int>[0x41, 0x00, 0x42])), isTrue);
    });

    test('a null byte beyond the sniff window is not inspected', () {
      final List<int> b = List<int>.filled(9000, 0x41, growable: true)..add(0x00);
      expect(TextCodec.isBinary(bytesOf(b)), isFalse);
    });

    test('UTF-16 is text despite containing null bytes', () {
      // "Hi" in UTF-16 LE with BOM.
      final Uint8List b = bytesOf(<int>[0xFF, 0xFE, 0x48, 0x00, 0x69, 0x00]);
      expect(TextCodec.isBinary(b), isFalse);
    });
  });

  group('encoding detection', () {
    test('no BOM means UTF-8', () {
      final TextFileContents r = TextCodec.decode(bytesOf(utf8.encode('abc')));
      expect(r.format.encoding, TextEncoding.utf8);
      expect(r.text, 'abc');
    });

    test('UTF-8 BOM is detected and stripped from the text', () {
      final Uint8List b = bytesOf(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode('abc')]);
      final TextFileContents r = TextCodec.decode(b);
      expect(r.format.encoding, TextEncoding.utf8Bom);
      expect(r.text, 'abc', reason: 'the BOM must not leak into the buffer');
    });

    test('UTF-16 LE round-trips', () {
      final Uint8List encoded = TextCodec.encodeText(
        'héllo',
        const TextFormat(encoding: TextEncoding.utf16le, endsWithNewline: false),
      );
      final TextFileContents r = TextCodec.decode(encoded);
      expect(r.format.encoding, TextEncoding.utf16le);
      expect(r.text, 'héllo');
    });

    test('UTF-16 BE round-trips', () {
      final Uint8List encoded = TextCodec.encodeText(
        'héllo',
        const TextFormat(encoding: TextEncoding.utf16be, endsWithNewline: false),
      );
      final TextFileContents r = TextCodec.decode(encoded);
      expect(r.format.encoding, TextEncoding.utf16be);
      expect(r.text, 'héllo');
    });

    test('invalid UTF-8 throws rather than substituting replacement chars', () {
      // 0xFF is never valid in UTF-8. Silently replacing it would let the user
      // save the file back and destroy the original bytes.
      expect(
        () => TextCodec.decode(bytesOf(<int>[0x41, 0xFF, 0x42])),
        throwsA(isA<EncodingFailure>()),
      );
    });

    test('forcing Latin-1 reads bytes that are invalid UTF-8', () {
      final TextFileContents r = TextCodec.decode(
        bytesOf(<int>[0x41, 0xFF, 0x42]),
        forced: TextEncoding.latin1,
      );
      expect(r.text.length, 3);
      expect(r.format.encoding, TextEncoding.latin1);
    });
  });

  group('line endings', () {
    test('CRLF is detected and normalised to LF in the buffer', () {
      final TextFileContents r =
          TextCodec.decode(bytesOf(utf8.encode('a\r\nb\r\nc')));
      expect(r.format.lineEnding, LineEnding.crlf);
      expect(r.text, 'a\nb\nc', reason: 'the editor always works in LF');
    });

    test('LF stays LF', () {
      final TextFileContents r = TextCodec.decode(bytesOf(utf8.encode('a\nb')));
      expect(r.format.lineEnding, LineEnding.lf);
    });

    test('classic Mac CR is detected', () {
      final TextFileContents r =
          TextCodec.decode(bytesOf(utf8.encode('a\rb\rc')));
      expect(r.format.lineEnding, LineEnding.cr);
      expect(r.text, 'a\nb\nc');
    });

    test('mixed endings are flagged', () {
      final TextFileContents r =
          TextCodec.decode(bytesOf(utf8.encode('a\r\nb\nc')));
      expect(r.format.hasMixedLineEndings, isTrue);
    });

    test('a CRLF file edited and saved keeps CRLF', () {
      final TextFileContents opened =
          TextCodec.decode(bytesOf(utf8.encode('one\r\ntwo\r\n')));
      final Uint8List saved =
          TextCodec.encodeText('${opened.text}three\n', opened.format);
      expect(utf8.decode(saved), 'one\r\ntwo\r\nthree\r\n');
    });
  });

  group('final newline', () {
    test('a file ending without a newline does not gain one', () {
      final TextFileContents r = TextCodec.decode(bytesOf(utf8.encode('abc')));
      expect(r.format.endsWithNewline, isFalse);
      expect(utf8.decode(TextCodec.encodeText('abcd', r.format)), 'abcd');
    });

    test('a file ending with a newline keeps it', () {
      final TextFileContents r = TextCodec.decode(bytesOf(utf8.encode('abc\n')));
      expect(r.format.endsWithNewline, isTrue);
      expect(utf8.decode(TextCodec.encodeText('abcd', r.format)), 'abcd\n');
    });
  });

  group('indent detection', () {
    test('two-space indentation', () {
      const String code = 'void main() {\n  if (x) {\n    go();\n  }\n}\n';
      final IndentStyle s = TextCodec.detectIndent(code);
      expect(s.useSpaces, isTrue);
      expect(s.size, 2);
    });

    test('four-space indentation', () {
      const String code = 'def f():\n    if x:\n        go()\n    return 1\n';
      final IndentStyle s = TextCodec.detectIndent(code);
      expect(s.useSpaces, isTrue);
      expect(s.size, 4);
    });

    test('tabs win when they dominate', () {
      const String code = 'func a() {\n\tif x {\n\t\tgo()\n\t}\n}\n';
      expect(TextCodec.detectIndent(code).useSpaces, isFalse);
    });

    test('a file with no indentation falls back to the default', () {
      final IndentStyle s = TextCodec.detectIndent('a\nb\nc\n');
      expect(s, const IndentStyle.fallback());
    });
  });

  group('long lines', () {
    test('normal code is fine', () {
      expect(TextCodec.hasExcessivelyLongLines('short\nlines\n'), isFalse);
    });

    test('a minified bundle is flagged', () {
      expect(
        TextCodec.hasExcessivelyLongLines('x' * 10001),
        isTrue,
        reason: 'highlighting a 10k-character line stalls the frame',
      );
    });

    test('the check applies to any line, not just the first', () {
      expect(TextCodec.hasExcessivelyLongLines('ok\n${'x' * 10001}\nok'), isTrue);
    });
  });
}
