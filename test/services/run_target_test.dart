/// What the app will and will not run, and what it says about the difference.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/services/language/language_registry.dart';
import 'package:pocket_code/services/runner/run_target.dart';

RunTarget forId(String id) =>
    runTargetForLanguage(LanguageRegistry.byId(id) ?? LanguageRegistry.plainText);

void main() {
  group('what runs', () {
    test('HTML renders as a page', () {
      expect(forId('html').kind, RunKind.htmlPage);
      expect(forId('html').canRun, isTrue);
    });

    test('JavaScript executes', () {
      expect(forId('javascript').kind, RunKind.javascript);
      expect(forId('javascript').canRun, isTrue);
    });
  });

  group('what does not run, and why', () {
    test('compiled languages need a compiler', () {
      for (final String id in <String>[
        'c',
        'cpp',
        'csharp',
        'go',
        'rust',
        'java',
        'kotlin',
        'swift',
      ]) {
        expect(forId(id).canRun, isFalse, reason: id);
        expect(forId(id).refusal, RunRefusal.needsCompiler, reason: id);
      }
    });

    test('interpreted languages need a runtime this app does not ship', () {
      // Python is deliberately absent: the app now ships MicroPython, so it
      // runs. Everything else here still has no runtime.
      for (final String id in <String>['ruby', 'php', 'lua', 'bash']) {
        expect(forId(id).refusal, RunRefusal.needsRuntime, reason: id);
      }
    });

    test('Python is no longer refused — MicroPython ships', () {
      expect(forId('python').canRun, isTrue);
      expect(forId('python').kind, RunKind.python);
    });

    test('TypeScript refuses rather than pretending to be JavaScript', () {
      // Stripping the types and hoping is not running TypeScript, and a file
      // that silently ran as something else would be worse than one that said
      // no.
      expect(forId('typescript').refusal, RunRefusal.needsRuntime);
    });

    test('Dart is refused for the right reason', () {
      expect(forId('dart').refusal, RunRefusal.noDartEval);
    });

    test('anything else is simply not a runnable document', () {
      expect(forId('json').refusal, RunRefusal.notSource);
      expect(forId('markdown').refusal, RunRefusal.notSource);
      expect(forId('plaintext').refusal, RunRefusal.notSource);
    });
  });

  group('explanations', () {
    test('every refusal explains itself in plain words', () {
      for (final RunRefusal refusal in RunRefusal.values) {
        final String text = RunTarget.refuses(refusal).explain('C');
        expect(text, isNotEmpty, reason: '$refusal');
        expect(text.toLowerCase(), isNot(contains('coming soon')),
            reason: 'the brief forbids promising features that do not exist');
        expect(text.toLowerCase(), isNot(contains('not implemented')),
            reason: '$refusal must say what it cannot do, not how it was built');
      }
    });

    test('the compiler refusal names the real obstacles', () {
      final String text =
          const RunTarget.refuses(RunRefusal.needsCompiler).explain('C++');
      expect(text, contains('C++'));
      expect(text.toLowerCase(), contains('compiler'));
      expect(text.toLowerCase(), contains('android'));
    });

    test('the runtime refusal promises the code is not sent away', () {
      // Wording must stay true on the direct-APK build, which can download a
      // public repository — so it describes behaviour, not the permission.
      final String text =
          const RunTarget.refuses(RunRefusal.needsRuntime).explain('Python');
      expect(text.toLowerCase(), contains('never sends'));
    });

    test('a runnable target describes what it will do', () {
      expect(
        const RunTarget.runs(RunKind.htmlPage).explain('HTML'),
        contains('HTML'),
      );
    });
  });
}
