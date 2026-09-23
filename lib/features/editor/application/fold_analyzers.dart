/// Which lines the editor offers to fold, and for which languages.
///
/// `re_editor` ships one analyser, `DefaultCodeChunkAnalyzer`, and it folds on
/// `{}`, `[]` and `()` only. That covers most of the registry and none of the
/// languages where folding matters most on a phone: Python and YAML have no
/// closing brace, so a brace analyser finds nothing to fold in them at all.
/// [IndentCodeChunkAnalyzer] fills that gap.
///
/// **Every analyser here must be `const`.** `CodeEditor.didUpdateWidget`
/// disposes and recreates its `CodeChunkController` whenever the analyser
/// changes *identity*, so handing it a fresh instance on each build would
/// re-run the analysis every frame and silently drop every collapsed region.
/// Dart canonicalises `const` constructor calls with identical arguments, so
/// returning consts from [analyzerFor] is what makes the identity stable —
/// and `fold_analyzers_test.dart` asserts exactly that.
library;

import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/services/language/language_definition.dart';
import 'package:re_editor/re_editor.dart';

/// Languages folded by indentation rather than by brackets.
///
/// Deliberately a small set held here rather than a field on
/// [LanguageDefinition]: adding a field would mean touching all 28 registry
/// entries to serve two of them.
const Set<String> kIndentFoldedLanguages = <String>{'python', 'yaml'};

/// The width a tab counts as when measuring indentation.
///
/// Indentation is compared, never reproduced, so this only has to be
/// consistent — but it follows the editor's own tab size so a file indented
/// with tabs folds the same way it looks.
int indentWidthOf(String line, int tabSize) {
  int width = 0;
  for (int i = 0; i < line.length; i++) {
    final String ch = line[i];
    if (ch == ' ') {
      width += 1;
    } else if (ch == '\t') {
      width += tabSize - (width % tabSize);
    } else {
      return width;
    }
  }
  // All whitespace: the caller treats this as a blank line.
  return width;
}

bool _isBlank(String line) => line.trim().isEmpty;

/// Foldable ranges derived from indentation, as `(start, end)` pairs.
///
/// `end` is **one past the last line of the block**, because
/// `collapseChunk(start, end)` hides `start + 1 … end - 1`. A brace language
/// gets that for free — the closing brace is the line to keep visible — but an
/// indented block has no closing line, so the range has to run one line past
/// its body or the last line of every folded block would stay on screen.
///
/// Trailing blank lines are excluded: folding a function should not swallow
/// the blank line separating it from the next one.
List<(int, int)> indentFoldRanges({
  required int lineCount,
  required String Function(int) lineAt,
  int tabSize = 2,
}) {
  if (lineCount < 2) {
    return const <(int, int)>[];
  }

  // One pass to measure, so the nested scan below is pure arithmetic.
  final List<int> indents = List<int>.filled(lineCount, -1);
  for (int i = 0; i < lineCount; i++) {
    final String line = lineAt(i);
    indents[i] = _isBlank(line) ? -1 : indentWidthOf(line, tabSize);
  }

  final List<(int, int)> ranges = <(int, int)>[];
  for (int i = 0; i < lineCount; i++) {
    final int depth = indents[i];
    if (depth < 0) {
      continue;
    }

    // The block opens only if the next line with content is deeper.
    int next = i + 1;
    while (next < lineCount && indents[next] < 0) {
      next++;
    }
    if (next >= lineCount || indents[next] <= depth) {
      continue;
    }

    // Run to the last line with content that is still deeper than the opener.
    int lastContent = next;
    for (int k = next; k < lineCount; k++) {
      if (indents[k] < 0) {
        continue;
      }
      if (indents[k] <= depth) {
        break;
      }
      lastContent = k;
    }

    ranges.add((i, lastContent + 1));
  }
  return ranges;
}

/// Folds on indentation, for languages that have no closing bracket.
///
/// `const` and deeply immutable because `CodeChunkController` sends the
/// analyser itself across an isolate to run it.
///
/// The tab width is fixed rather than following the editor setting, because
/// indentation here is only ever *compared*, never reproduced — any consistent
/// width gives the same nesting. Fixing it also keeps a single canonical
/// instance, which is what the identity rule at the top of this file needs.
class IndentCodeChunkAnalyzer implements CodeChunkAnalyzer {
  const IndentCodeChunkAnalyzer();

  /// Python rejects mixing tabs and spaces at one level and YAML forbids tabs
  /// for indentation outright, so a fixed width cannot misread a valid file.
  static const int _tabWidth = 4;

  @override
  List<CodeChunk> run(CodeLines codeLines) {
    final List<(int, int)> ranges = indentFoldRanges(
      lineCount: codeLines.length,
      lineAt: (int i) => codeLines[i].text,
      tabSize: _tabWidth,
    );
    return <CodeChunk>[
      for (final (int start, int end) in ranges)
        if (end - start - 1 > 0) CodeChunk(start, end),
    ];
  }
}

// Canonical instances. Returning these — rather than building one per call —
// is what keeps the analyser's identity stable across rebuilds.
const NonCodeChunkAnalyzer _noFolding = NonCodeChunkAnalyzer();
const DefaultCodeChunkAnalyzer _bracketFolding = DefaultCodeChunkAnalyzer();
const IndentCodeChunkAnalyzer _indentFolding = IndentCodeChunkAnalyzer();

/// The analyser for [language], honouring the user's folding setting.
CodeChunkAnalyzer analyzerFor(
  LanguageDefinition language,
  EditorSettings settings,
) {
  if (!settings.codeFolding) {
    return _noFolding;
  }
  if (kIndentFoldedLanguages.contains(language.id)) {
    return _indentFolding;
  }
  return _bracketFolding;
}
