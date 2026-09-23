/// The JavaScript harness and the console bridge.
///
/// The WebView itself cannot run under `flutter_test`, so what is covered here
/// is the page construction — which is where a mistake would silently break
/// every run.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/features/runner/presentation/run_pane.dart';

void main() {
  group('javascriptHarness', () {
    test('includes the source', () {
      final String page = javascriptHarness('console.log(1 + 1);');
      expect(page, contains('console.log(1 + 1);'));
    });

    test('installs the console overrides before the user code', () {
      final String page = javascriptHarness('throw new Error("boom");');

      expect(page.indexOf('TcodeConsole.postMessage'),
          lessThan(page.indexOf('throw new Error')),
          reason: 'an error on the first line still has to be captured');
    });

    test('captures uncaught errors and rejected promises', () {
      final String page = javascriptHarness('');
      expect(page, contains('window.onerror'));
      expect(page, contains('unhandledrejection'));
    });

    test('reports line numbers relative to the user file, not the wrapper', () {
      // The wrapper is ~40 lines; without subtracting it an error on line 4
      // is reported as line 44 and sends people hunting through a short file.
      final String page = javascriptHarness('boom();');
      final RegExpMatch? offset =
          RegExp(r'\(line " \+ \(line - (\d+)\)').firstMatch(page);

      expect(offset, isNotNull, reason: 'the harness must subtract an offset');
      final int subtracted = int.parse(offset!.group(1)!);

      final List<String> lines = page.split('\n');
      final int sourceLine =
          lines.indexWhere((String l) => l.contains('boom();')) + 1;

      expect(sourceLine - subtracted, 1,
          reason: 'the first line of the source must report as line 1');
    });

    test('gives the page a dark background', () {
      // An unstyled page is a white slab in the middle of a dark app.
      expect(javascriptHarness(''), contains('background: #101418'));
    });

    test('a closing script tag in the source cannot end the block', () {
      final String page = javascriptHarness(r'var s = "</script>";');

      expect(page, isNot(contains('var s = "</script>"')));
      expect(page, contains(r'<\/script>'));
    });

    test('is a complete document', () {
      final String page = javascriptHarness('');
      expect(page, startsWith('<!DOCTYPE html>'));
      expect(page, contains('<meta name="viewport"'));
    });
  });

  group('withConsoleBridge', () {
    test('injects before </head> when there is one', () {
      const String html = '<html><head><title>t</title></head><body></body></html>';
      final String out = withConsoleBridge(html);

      expect(out.indexOf('__tcodeBridge'), lessThan(out.indexOf('</head>')),
          reason: 'a script in the body must already be covered');
      expect(out, contains('<title>t</title>'));
    });

    test('prepends when the page has no head', () {
      const String html = '<p>bare</p>';
      final String out = withConsoleBridge(html);

      expect(out.trimLeft(), startsWith('<script>'));
      expect(out, contains('<p>bare</p>'));
    });

    test('matches a head tag whatever its case', () {
      final String out = withConsoleBridge('<HTML><HEAD></HEAD></HTML>');
      expect(out.indexOf('__tcodeBridge'), lessThan(out.indexOf('</HEAD>')));
    });

    test('guards against being injected twice', () {
      // The same page can be re-run; installing the overrides again would
      // double every log line.
      expect(kConsoleBridge, contains('if (window.__tcodeBridge) return;'));
    });
  });

  group('ConsoleLine', () {
    test('classifies levels', () {
      expect(const ConsoleLine(level: 'error', text: 'x').isError, isTrue);
      expect(const ConsoleLine(level: 'warn', text: 'x').isWarning, isTrue);
      expect(const ConsoleLine(level: 'log', text: 'x').isError, isFalse);
      expect(const ConsoleLine(level: 'log', text: 'x').isWarning, isFalse);
    });
  });
}
