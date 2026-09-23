/// Inlining a page's siblings so it can render with no origin and no network.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/services/runner/html_bundler.dart';

import '../support/fake_file_system.dart';

const HtmlBundler bundler = HtmlBundler();

FakeFileSystemProvider seeded() => FakeFileSystemProvider()
  ..seed(<String, String>{
    '/w/index.html': '',
    '/w/style.css': 'body { color: red; }',
    '/w/app.js': 'console.log("hi");',
    '/w/assets/extra.css': '.extra { margin: 0 }',
    '/w/secret.txt': 'not referenced',
  });

Future<BundledPage> bundle(String html, [FakeFileSystemProvider? provider]) {
  final FakeFileSystemProvider fs = provider ?? seeded();
  return bundler.bundle(html: html, fileId: '/w/index.html', provider: fs);
}

void main() {
  group('stylesheets', () {
    test('a relative stylesheet is inlined', () async {
      final BundledPage page = await bundle(
        '<html><head><link rel="stylesheet" href="style.css"></head></html>',
      );

      expect(page.html, contains('<style>'));
      expect(page.html, contains('body { color: red; }'));
      expect(page.html, isNot(contains('<link')));
      expect(page.notes, isEmpty);
    });

    test('a stylesheet in a subfolder is found', () async {
      final BundledPage page = await bundle(
        '<link rel="stylesheet" href="assets/extra.css">',
      );
      expect(page.html, contains('.extra { margin: 0 }'));
    });

    test('a remote stylesheet is left alone and reported', () async {
      final BundledPage page = await bundle(
        '<link rel="stylesheet" href="https://cdn.example.com/a.css">',
      );

      expect(page.html, contains('https://cdn.example.com/a.css'),
          reason: 'the tag stays, so the page is still what the user wrote');
      expect(page.notes.single, contains('never fetch remote files'));
    });

    test('a missing stylesheet is reported, not silently dropped', () async {
      final BundledPage page =
          await bundle('<link rel="stylesheet" href="gone.css">');

      expect(page.notes.single, contains('gone.css'));
      expect(page.html, contains('gone.css'),
          reason: 'a missing file must not look like broken CSS');
    });
  });

  group('scripts', () {
    test('a relative script is inlined', () async {
      final BundledPage page =
          await bundle('<script src="app.js"></script>');

      expect(page.html, contains('console.log("hi");'));
      expect(page.html, isNot(contains('src="app.js"')));
    });

    test('an inline script is untouched', () async {
      const String html = '<script>var x = 1;</script>';
      final BundledPage page = await bundle(html);
      expect(page.html, contains('var x = 1;'));
    });

    test('a closing script tag inside the code cannot break the page', () async {
      final FakeFileSystemProvider fs = seeded()
        ..seed(<String, String>{
          '/w/tricky.js': r'var s = "</script>"; console.log(s);',
        });

      final BundledPage page =
          await bundle('<script src="tricky.js"></script>', fs);

      expect(page.html, isNot(contains('"</script>"')),
          reason: 'a literal </script> would end the block early');
      expect(page.html, contains(r'<\/script>'));
    });

    test('a remote script is left alone and reported', () async {
      final BundledPage page = await bundle(
        '<script src="//cdn.example.com/x.js"></script>',
      );
      expect(page.notes.single, contains('never fetch remote files'));
    });
  });

  group('images', () {
    test('a relative image becomes a data URI', () async {
      final FakeFileSystemProvider fs = seeded()
        ..seed(<String, String>{'/w/logo.png': 'PNGDATA'});

      final BundledPage page = await bundle('<img src="logo.png">', fs);

      expect(page.html, contains('data:image/png;base64,'));
      expect(page.html, isNot(contains('src="logo.png"')));
    });

    test('an existing data URI is untouched', () async {
      const String html = '<img src="data:image/gif;base64,AAAA">';
      final BundledPage page = await bundle(html);
      expect(page.html, html);
      expect(page.notes, isEmpty);
    });
  });

  group('escaping the folder is refused', () {
    test('a parent reference is skipped and reported', () async {
      final BundledPage page =
          await bundle('<link rel="stylesheet" href="../outside.css">');

      expect(page.notes.single, contains('outside this folder'));
      expect(page.html, contains('../outside.css'),
          reason: 'refused, never resolved');
    });

    test('an absolute path is skipped', () async {
      final BundledPage page =
          await bundle('<script src="/etc/passwd"></script>');
      expect(page.notes.single, contains('outside this folder'));
    });
  });

  group('resolveReference', () {
    test('resolves a plain sibling and a subfolder', () {
      final FakeFileSystemProvider fs = seeded();
      expect(resolveReference(fs, '/w', 'style.css'), '/w/style.css');
      expect(resolveReference(fs, '/w', 'assets/extra.css'),
          '/w/assets/extra.css');
    });

    test('strips a query string and a fragment', () {
      final FakeFileSystemProvider fs = seeded();
      expect(resolveReference(fs, '/w', 'style.css?v=2'), '/w/style.css');
      expect(resolveReference(fs, '/w', 'style.css#top'), '/w/style.css');
    });

    test('refuses anything that climbs out or is absolute', () {
      final FakeFileSystemProvider fs = seeded();
      expect(resolveReference(fs, '/w', '../x.css'), isNull);
      expect(resolveReference(fs, '/w', 'a/../../x.css'), isNull);
      expect(resolveReference(fs, '/w', '/x.css'), isNull);
      expect(resolveReference(fs, '/w', ''), isNull);
    });
  });

  group('isRemote', () {
    test('recognises the schemes this app cannot reach', () {
      expect(isRemote('https://a/b'), isTrue);
      expect(isRemote('http://a/b'), isTrue);
      expect(isRemote('//a/b'), isTrue);
      expect(isRemote('  HTTPS://A '), isTrue);
      expect(isRemote('style.css'), isFalse);
      expect(isRemote('assets/a.css'), isFalse);
    });
  });

  test('a page with no references is returned unchanged', () async {
    const String html = '<html><body><p>Hello</p></body></html>';
    final BundledPage page = await bundle(html);
    expect(page.html, html);
    expect(page.notes, isEmpty);
  });
}
