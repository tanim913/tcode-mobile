/// The MicroPython harness page.
///
/// The runtime itself cannot run under `flutter_test` — it needs a WebView —
/// so what is covered here is the page construction, which is where a mistake
/// would silently break every Python run.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/services/language/language_registry.dart';
import 'package:pocket_code/services/runner/python_runtime.dart';
import 'package:pocket_code/services/runner/run_target.dart';

String page(String source) => buildPythonPage(
      glue: 'const GLUE = 1;',
      wasmBase64: 'QUJD',
      source: source,
    );

void main() {
  group('run target', () {
    test('Python now runs instead of refusing', () {
      final RunTarget target =
          runTargetForLanguage(LanguageRegistry.byId('python')!);
      expect(target.canRun, isTrue);
      expect(target.kind, RunKind.python);
    });

    test('the action names MicroPython, never plain Python', () {
      final RunTarget target =
          runTargetForLanguage(LanguageRegistry.byId('python')!);
      expect(target.explain('Python'), contains('MicroPython'));
    });

    test('other interpreted languages still refuse', () {
      for (final String id in <String>['ruby', 'php', 'lua', 'bash']) {
        expect(runTargetForLanguage(LanguageRegistry.byId(id)!).canRun, isFalse,
            reason: id);
      }
    });
  });

  group('buildPythonPage', () {
    test('embeds the glue and the wasm as a data URL', () {
      final String html = page('print(1)');
      expect(html, contains('const GLUE = 1;'));
      expect(html, contains('data:application/wasm;base64,QUJD'),
          reason: 'a data URL is what makes this work with no origin');
    });

    test('passes the source as JSON, not pasted into the script', () {
      // Python is full of quotes and backslashes; pasting it would break the
      // page on the first apostrophe.
      const String source = "print('it\\'s fine')\nx = \"a\\\\b\"";
      final String html = page(source);

      expect(html, contains(jsonEncode(source)));
      expect(html, isNot(contains("print('it's fine')")));
    });

    test('a newline in the source does not split the JavaScript', () {
      final String html = page('a = 1\nb = 2\nprint(a + b)');
      expect(html, contains(r'a = 1\nb = 2\nprint(a + b)'),
          reason: 'the source must survive as one JavaScript string');
    });

    test('sends stdout as log and stderr as error', () {
      final String html = page('print(1)');
      expect(html, contains("stdout: (line) => send('log', line)"));
      expect(html, contains("stderr: (line) => send('error', line)"));
    });

    test('explains the limits when an import fails', () {
      final String html = page('import numpy');
      expect(html, contains('No module named'));
      expect(html, contains('no numpy, pandas or requests'));
    });

    test('reports a runtime that fails to start, rather than hanging', () {
      expect(page(''), contains('failed to start'));
    });

    test('gives the page a dark background', () {
      expect(page(''), contains('background: #101418'));
    });

    test('is a module script, because the glue is an ES module', () {
      expect(page(''), contains('<script type="module">'));
    });
  });

  group('honesty', () {
    test('the label is MicroPython', () {
      expect(kPythonRuntimeLabel, 'MicroPython');
    });

    test('the limits name what is actually missing', () {
      expect(kPythonRuntimeLimits, contains('numpy'));
      expect(kPythonRuntimeLimits, contains('pip'));
      expect(kPythonRuntimeLimits.toLowerCase(), contains('reduced'));
    });
  });
}
