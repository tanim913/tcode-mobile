import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/services/language/language_service.dart';

void main() {
  const LexicalLanguageService service = LexicalLanguageService();

  String idFor(String name, {String? firstLine}) =>
      service.detectByName(name, firstLine: firstLine).id;

  group('detection by extension', () {
    test('common languages', () {
      expect(idFor('main.dart'), 'dart');
      expect(idFor('app.py'), 'python');
      expect(idFor('Main.java'), 'java');
      expect(idFor('server.go'), 'go');
      expect(idFor('lib.rs'), 'rust');
      expect(idFor('index.html'), 'html');
      expect(idFor('style.css'), 'css');
      expect(idFor('query.sql'), 'sql');
    });

    test('JSX and TSX ride on their base grammars', () {
      expect(idFor('App.jsx'), 'javascript');
      expect(idFor('App.tsx'), 'typescript');
    });

    test('extension matching is case insensitive', () {
      expect(idFor('MAIN.DART'), 'dart');
      expect(idFor('Readme.MD'), 'markdown');
    });
  });

  group('detection by exact file name', () {
    test('extensionless files are recognised', () {
      expect(idFor('Dockerfile'), 'dockerfile');
      expect(idFor('Makefile'), 'makefile');
      expect(idFor('Gemfile'), 'ruby');
    });

    test('a file name beats a generic extension match', () {
      expect(idFor('pubspec.yaml'), 'yaml');
      expect(idFor('Cargo.toml'), 'toml');
    });

    test('dotfiles are recognised by name', () {
      expect(idFor('.bashrc'), 'bash');
      expect(idFor('.editorconfig'), 'toml');
    });
  });

  group('detection by shebang', () {
    test('direct interpreter path', () {
      expect(idFor('deploy', firstLine: '#!/bin/bash'), 'bash');
    });

    test('env-style shebang', () {
      expect(idFor('build', firstLine: '#!/usr/bin/env python3'), 'python');
      expect(idFor('script', firstLine: '#!/usr/bin/env ruby'), 'ruby');
    });

    test('a shebang does not override a known extension', () {
      // The extension is the stronger signal; a .dart file with a shell
      // shebang is still Dart.
      expect(idFor('tool.dart', firstLine: '#!/bin/bash'), 'dart');
    });

    test('a non-shebang first line is ignored', () {
      expect(idFor('notes', firstLine: 'just some text'), 'plaintext');
    });
  });

  group('fallback', () {
    test('unknown extensions open as plain text', () {
      expect(idFor('data.xyzzy'), 'plaintext');
      expect(idFor('nameless'), 'plaintext');
    });

    test('plain text reports no highlighting rather than guessing', () {
      expect(service.detectByName('data.xyzzy').hasHighlighting, isFalse);
    });
  });

  group('comment syntax', () {
    test('line comment markers are language-correct', () {
      expect(service.detectByName('a.dart').lineComment, '//');
      expect(service.detectByName('a.py').lineComment, '#');
      expect(service.detectByName('a.sql').lineComment, '--');
      expect(service.detectByName('a.lua').lineComment, '--');
    });

    test('JSON correctly has no line comment', () {
      expect(service.detectByName('a.json').lineComment, isNull);
    });

    test('HTML has a block comment but no line comment', () {
      expect(service.detectByName('a.html').lineComment, isNull);
      expect(service.detectByName('a.html').blockComment, ('<!--', '-->'));
    });
  });
}
