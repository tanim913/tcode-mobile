/// The MIME mapping behind Share and Open with.
///
/// Only the pure half is tested here: staging a file and launching a chooser
/// need a real device, and are verified there.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/services/share/share_service.dart';

void main() {
  group('mimeTypeFor', () {
    test('maps the common document types', () {
      expect(mimeTypeFor('notes.txt'), 'text/plain');
      expect(mimeTypeFor('README.md'), 'text/markdown');
      expect(mimeTypeFor('index.html'), 'text/html');
      expect(mimeTypeFor('data.json'), 'application/json');
      expect(mimeTypeFor('photo.png'), 'image/png');
      expect(mimeTypeFor('archive.zip'), 'application/zip');
    });

    test('treats source files as plain text', () {
      // An app registered for text/plain can display them; a made-up
      // "text/x-dart" resolves to nothing on most devices.
      for (final String name in <String>[
        'main.dart',
        'script.py',
        'Main.java',
        'build.sh',
        'query.sql',
      ]) {
        expect(mimeTypeFor(name), 'text/plain', reason: name);
      }
    });

    test('is case-insensitive about the extension', () {
      expect(mimeTypeFor('PHOTO.PNG'), 'image/png');
      expect(mimeTypeFor('Notes.TXT'), 'text/plain');
    });

    test('falls back to octet-stream for anything unknown', () {
      expect(mimeTypeFor('firmware.bin'), 'application/octet-stream');
      expect(mimeTypeFor('noextension'), 'application/octet-stream');
      expect(mimeTypeFor(''), 'application/octet-stream');
    });

    test('a dotfile with no extension is not mistaken for one', () {
      expect(mimeTypeFor('.gitignore'), 'application/octet-stream');
    });
  });
}
