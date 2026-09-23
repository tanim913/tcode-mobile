/// What, if anything, running a given document means.
///
/// The honest half of the run feature. Most languages cannot run on a phone
/// with no toolchain and no network, and this is where that is decided once so
/// every surface gives the same answer and the same reason.
library;

import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/services/language/language_definition.dart';
import 'package:pocket_code/services/runner/python_runtime.dart';

/// How a document runs, or why it does not.
enum RunKind {
  /// Rendered as a web page, with its sibling CSS, JS and images inlined.
  htmlPage,

  /// Executed as a script, with console output captured.
  javascript,

  /// Executed by the bundled MicroPython runtime.
  python,

  /// Nothing here can run.
  none,
}

/// Why a document cannot be run.
///
/// Shown on the disabled Run action, because "greyed out with no explanation"
/// is the thing this project keeps refusing to ship.
enum RunRefusal {
  /// No document open.
  nothingOpen,

  /// A compiled language: the toolchain is far too large for a phone, and
  /// Android will not execute code the app generates at runtime anyway.
  needsCompiler,

  /// A runtime the app does not ship.
  needsRuntime,

  /// Flutter is ahead-of-time compiled in release; there is no `eval`.
  noDartEval,

  /// Images, binaries, and anything else that is not source.
  notSource,
}

/// A decision about one document: what it does, or what to say instead.
class RunTarget {
  const RunTarget.runs(this.kind) : refusal = null;
  const RunTarget.refuses(this.refusal) : kind = RunKind.none;

  final RunKind kind;
  final RunRefusal? refusal;

  bool get canRun => refusal == null;

  /// The sentence shown when the action is disabled.
  ///
  /// Deliberately says what the app cannot do and why, never "coming soon".
  String explain(String languageLabel) => switch (refusal) {
        null => kind == RunKind.python
            ? 'Run with $kPythonRuntimeLabel'
            : 'Run this $languageLabel document',
        RunRefusal.nothingOpen => 'Open a file to run it',
        RunRefusal.needsCompiler =>
          '$languageLabel needs a compiler. A real toolchain is far larger '
              'than this app, and Android does not let an app run code it '
              'compiled itself — so this cannot work offline on a phone.',
        RunRefusal.needsRuntime =>
          'This app ships no $languageLabel runtime, and it never sends '
              'your code anywhere to be run.',
        RunRefusal.noDartEval =>
          'A released Flutter app is compiled ahead of time and has no way to '
              'evaluate Dart at runtime — including its own language.',
        RunRefusal.notSource => 'This is not a document that can be run',
      };
}

/// Languages that need a compiler and a linker. Never runnable here.
const Set<String> _compiled = <String>{
  'c', 'cpp', 'csharp', 'go', 'rust', 'java', 'kotlin', 'swift',
};

/// Languages with an interpreter this app does not ship.
const Set<String> _interpreted = <String>{
  'ruby', 'php', 'lua', 'bash', 'typescript',
};

/// Decides what running [tab] means.
///
/// TypeScript is deliberately in the "needs a runtime" list rather than being
/// quietly run as JavaScript: stripping the types and hoping is not the same
/// thing, and a file that silently ran as something else would be worse than
/// one that refused.
RunTarget runTargetFor(OpenTab? tab) {
  if (tab == null) {
    return const RunTarget.refuses(RunRefusal.nothingOpen);
  }
  if (tab.restriction == DocumentRestriction.binary ||
      tab.restriction == DocumentRestriction.image) {
    return const RunTarget.refuses(RunRefusal.notSource);
  }
  return runTargetForLanguage(tab.language);
}

RunTarget runTargetForLanguage(LanguageDefinition language) {
  return switch (language.id) {
    'html' => const RunTarget.runs(RunKind.htmlPage),
    'javascript' => const RunTarget.runs(RunKind.javascript),
    // MicroPython, not CPython — `explain` and the console both say so.
    'python' => const RunTarget.runs(RunKind.python),
    'dart' => const RunTarget.refuses(RunRefusal.noDartEval),
    final String id when _compiled.contains(id) =>
      const RunTarget.refuses(RunRefusal.needsCompiler),
    final String id when _interpreted.contains(id) =>
      const RunTarget.refuses(RunRefusal.needsRuntime),
    _ => const RunTarget.refuses(RunRefusal.notSource),
  };
}
