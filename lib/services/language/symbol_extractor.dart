/// Regex-based outline extraction — the "Basic outline" the brief asks for.
///
/// This is a heuristic, and the UI is required to say so. It reads one line at
/// a time with per-language patterns; it does not parse, does not resolve
/// imports and does not know about generics it has not seen. That is a
/// deliberate trade: an outline that appears instantly on a 5,000 line file and
/// is right most of the time beats a correct one that needs a language server
/// the app cannot ship.
///
/// The interface exists so a real analyzer can replace this wholesale later
/// without the outline panel or Go to Symbol changing at all.
library;

import 'package:pocket_code/data/models/document_symbol.dart';

abstract interface class SymbolExtractor {
  /// Shown as the outline panel's title. Named here rather than in the widget
  /// so every surface that lists symbols labels the feature identically.
  static const String outlineLabel = 'Basic outline';

  /// Shown instead of an empty list when the language has no patterns.
  static const String unavailableMessage =
      'Outline not available for this language';

  bool supports(String languageId);

  /// Symbols in document order. Returns empty for an unsupported language;
  /// callers distinguish "nothing found" from "cannot do this" with [supports].
  List<DocumentSymbol> extract({
    required String languageId,
    required String text,
  });
}

class RegexSymbolExtractor implements SymbolExtractor {
  const RegexSymbolExtractor();

  static const Set<String> supportedLanguageIds = <String>{
    'dart',
    'javascript',
    'typescript',
    'python',
    'java',
    'kotlin',
    'go',
    'rust',
    'markdown',
  };

  @override
  bool supports(String languageId) =>
      supportedLanguageIds.contains(languageId);

  @override
  List<DocumentSymbol> extract({
    required String languageId,
    required String text,
  }) {
    if (text.isEmpty) {
      return const <DocumentSymbol>[];
    }
    final List<String> lines = text.split('\n');
    return switch (languageId) {
      'markdown' => _markdown(lines),
      'dart' => _scan(lines, _dartRules),
      'javascript' || 'typescript' => _scan(lines, _scriptRules),
      'python' => _scan(lines, _pythonRules, commentPrefixes: _hashComment),
      'java' => _scan(lines, _javaRules),
      'kotlin' => _scan(lines, _kotlinRules),
      'go' => _scan(lines, _goRules),
      'rust' => _scan(lines, _rustRules),
      _ => const <DocumentSymbol>[],
    };
  }

  // --- The generic line scanner ---------------------------------------------

  static const List<String> _slashComment = <String>['//', '*', '/*'];
  static const List<String> _hashComment = <String>['#'];

  static List<DocumentSymbol> _scan(
    List<String> lines,
    List<_Rule> rules, {
    List<String> commentPrefixes = _slashComment,
  }) {
    final int unit = _indentUnit(lines);
    final List<DocumentSymbol> symbols = <DocumentSymbol>[];
    bool inBlockComment = false;

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      final String trimmed = line.trimLeft();
      if (trimmed.isEmpty) {
        continue;
      }
      // Block comments are tracked rather than ignored: a commented-out class
      // showing up in the outline is worse than missing one.
      if (inBlockComment) {
        if (trimmed.contains('*/')) {
          inBlockComment = false;
        }
        continue;
      }
      if (trimmed.startsWith('/*') && !trimmed.contains('*/')) {
        inBlockComment = true;
        continue;
      }
      if (commentPrefixes.any(trimmed.startsWith)) {
        continue;
      }

      final int level = (line.length - trimmed.length) ~/ unit;
      for (final _Rule rule in rules) {
        final RegExpMatch? match = rule.pattern.firstMatch(line);
        if (match == null) {
          continue;
        }
        final String? name = match.group(rule.nameGroup);
        if (name == null || name.isEmpty || _statementKeywords.contains(name)) {
          continue;
        }
        if (rule.accept != null && !rule.accept!(match, line)) {
          continue;
        }
        symbols.add(
          DocumentSymbol(
            name: name.replaceAll('`', ''),
            kind: rule.resolveKind?.call(match, level) ?? rule.kind,
            line: i + 1,
            column: line.indexOf(name, match.start) + 1,
            level: level,
            detail: rule.detailGroup == null
                ? null
                : match.group(rule.detailGroup!)?.trim(),
          ),
        );
        break; // One symbol per line: the first matching rule is the specific one.
      }
    }
    return symbols;
  }

  /// Smallest positive indentation in the file, used to turn a column count
  /// into a nesting level without assuming two or four spaces.
  static int _indentUnit(List<String> lines) {
    int smallest = 0;
    for (final String line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }
      final int indent = line.length - line.trimLeft().length;
      if (indent > 0 && (smallest == 0 || indent < smallest)) {
        smallest = indent;
      }
    }
    return smallest == 0 ? 4 : smallest;
  }

  // --- Markdown --------------------------------------------------------------

  static final RegExp _atxHeading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*\S)\s*$');
  static final RegExp _setextUnderline = RegExp(r'^\s{0,3}(=+|-{2,})\s*$');
  static final RegExp _fence = RegExp('^\\s*(```|~~~)');

  static List<DocumentSymbol> _markdown(List<String> lines) {
    final List<DocumentSymbol> symbols = <DocumentSymbol>[];
    bool fenced = false;
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      if (_fence.hasMatch(line)) {
        fenced = !fenced;
        continue;
      }
      // A `#` inside a fenced block is a shell comment, not a heading.
      if (fenced) {
        continue;
      }
      final RegExpMatch? atx = _atxHeading.firstMatch(line);
      if (atx != null) {
        final int depth = atx.group(1)!.length;
        symbols.add(
          DocumentSymbol(
            name: atx.group(2)!.replaceAll(RegExp(r'\s*#+\s*$'), '').trim(),
            kind: SymbolKind.heading,
            line: i + 1,
            column: line.indexOf('#') + 1,
            level: depth - 1,
          ),
        );
        continue;
      }
      // Setext headings: the text is on this line, the `===` on the next.
      final String trimmed = line.trim();
      if (trimmed.isEmpty || i + 1 >= lines.length) {
        continue;
      }
      final RegExpMatch? underline = _setextUnderline.firstMatch(lines[i + 1]);
      if (underline != null) {
        symbols.add(
          DocumentSymbol(
            name: trimmed,
            kind: SymbolKind.heading,
            line: i + 1,
            column: line.indexOf(trimmed[0]) + 1,
            level: underline.group(1)!.startsWith('=') ? 0 : 1,
          ),
        );
      }
    }
    return symbols;
  }
}

/// Words that can appear where an identifier would, and must never become a
/// symbol. `return Widget(...)` and `if (x) {` both look like declarations to a
/// pattern that only reads one line.
const Set<String> _statementKeywords = <String>{
  'if', 'for', 'while', 'switch', 'catch', 'return', 'assert', 'super',
  'this', 'else', 'do', 'try', 'finally', 'await', 'yield', 'throw', 'new',
  'case', 'with', 'extends', 'implements', 'in', 'is', 'as', 'on', 'break',
  'continue', 'rethrow', 'delete', 'typeof', 'instanceof', 'void', 'match',
  'when', 'loop', 'unsafe', 'print', 'require', 'import', 'export', 'default',
};

typedef _KindResolver = SymbolKind Function(RegExpMatch match, int level);

class _Rule {
  const _Rule(
    this.pattern,
    this.kind, {
    this.nameGroup = 1,
    this.resolveKind,
    this.accept,
    this.detailGroup,
  });

  final RegExp pattern;
  final SymbolKind kind;
  final int nameGroup;

  /// Lets one pattern produce different kinds — a Go `func` with a receiver is
  /// a method, without one it is a function.
  final _KindResolver? resolveKind;

  /// Second-stage check that a regex cannot express, such as "the parameter
  /// list is followed by a body and not by `.pop();`".
  final bool Function(RegExpMatch match, String line)? accept;

  final int? detailGroup;
}

SymbolKind _methodWhenNested(RegExpMatch match, int level) =>
    level > 0 ? SymbolKind.method : SymbolKind.function;

/// What may legally follow a declaration's parameter list.
///
/// This is the guard that separates `void save() {` from `Navigator.of(c).pop();`
/// — both start with an identifier and an open paren, but only one is followed
/// by a body, an arrow, an initialiser list or a semicolon and nothing else.
final RegExp _declarationTail = RegExp(
  r'^\s*(?::[^{]*)?'
  r'(?:\b(?:async|sync)\b\*?\s*)?'
  r'(?:\b(?:throws|rethrows)\b[^{;]*)?'
  r'(?:->\s*[^{;]+)?'
  r'\s*(?:\{|=>|;)?\s*$',
);

/// Whether [line] is a declaration rather than a call, judged by what comes
/// after the balanced parameter list. An unbalanced list means the signature
/// continues on the next line, which is a declaration by definition.
bool _hasDeclarationTail(RegExpMatch match, String line) {
  final int open = line.indexOf('(', match.end - 1);
  if (open < 0) {
    return false;
  }
  int depth = 0;
  for (int i = open; i < line.length; i++) {
    final String c = line[i];
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) {
        return _declarationTail.hasMatch(line.substring(i + 1));
      }
    }
  }
  return true;
}

// --- Dart ---------------------------------------------------------------

/// An untyped `Foo(` is a constructor; an untyped `foo(` is a call. Dart's
/// naming convention is the only signal available on one line, and `main` is
/// the one lowercase declaration worth special-casing.
bool _dartUntypedIsDeclaration(RegExpMatch match, String line) {
  if (!_hasDeclarationTail(match, line)) {
    return false;
  }
  final String? type = match.group(1);
  if (type != null && type.trim().isNotEmpty) {
    return !_statementKeywords.contains(type.trim());
  }
  final String name = match.group(2)!;
  if (name == 'main') {
    return true;
  }
  final String head = name.startsWith('_') && name.length > 1
      ? name.substring(1)
      : name;
  return head.isNotEmpty && head[0].toUpperCase() == head[0];
}

SymbolKind _dartCallableKind(RegExpMatch match, int level) {
  final String? type = match.group(1);
  if (type == null || type.trim().isEmpty) {
    return match.group(2) == 'main'
        ? SymbolKind.function
        : SymbolKind.constructor;
  }
  return level > 0 ? SymbolKind.method : SymbolKind.function;
}

final List<_Rule> _dartRules = <_Rule>[
  _Rule(
    RegExp(
      r'^\s*(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
      r'class\s+([A-Za-z_$][\w$]*)',
    ),
    SymbolKind.classType,
  ),
  _Rule(
    RegExp(r'^\s*(?:base\s+)?mixin\s+(?!class\b)([A-Za-z_$][\w$]*)'),
    SymbolKind.interfaceType,
  ),
  _Rule(RegExp(r'^\s*enum\s+([A-Za-z_$][\w$]*)'), SymbolKind.enumType),
  _Rule(
    RegExp(r'^\s*extension(?:\s+type)?\s+([A-Za-z_$][\w$]*)'),
    SymbolKind.classType,
  ),
  _Rule(
    RegExp(r'^\s*typedef\s+([A-Za-z_$][\w$]*)'),
    SymbolKind.interfaceType,
  ),
  _Rule(
    RegExp(
      r'^\s*(?:(?:external|static|abstract|final|const|late|covariant)\s+)*'
      r'[\w$<>,\s?\[\].]+\s+get\s+([A-Za-z_$][\w$]*)',
    ),
    SymbolKind.property,
  ),
  _Rule(
    RegExp(
      r'^\s*(?:@[\w.]+(?:\([^)]*\))?\s+)*'
      r'(?:(?:external|static|abstract|factory|const|final|late|covariant)\s+)*'
      r'(?:([A-Za-z_$][\w$]*(?:\s*<[^>=]*>)?\??(?:\s*\[\s*\])?)\s+)?'
      r'(set\s+)?([A-Za-z_$][\w$]*)\s*(?:<[^>(]*>)?\s*\(',
    ),
    SymbolKind.method,
    nameGroup: 3,
    resolveKind: _dartCallableKind,
    accept: _dartUntypedIsDeclaration,
  ),
];

// --- JavaScript and TypeScript ------------------------------------------

final List<_Rule> _scriptRules = <_Rule>[
  _Rule(
    RegExp(
      r'^\s*(?:export\s+)?(?:default\s+)?(?:abstract\s+)?'
      r'class\s+([A-Za-z_$][\w$]*)',
    ),
    SymbolKind.classType,
  ),
  _Rule(
    RegExp(
      r'^\s*(?:export\s+)?(?:declare\s+)?interface\s+([A-Za-z_$][\w$]*)',
    ),
    SymbolKind.interfaceType,
  ),
  _Rule(
    RegExp(
      r'^\s*(?:export\s+)?(?:declare\s+)?(?:const\s+)?'
      r'enum\s+([A-Za-z_$][\w$]*)',
    ),
    SymbolKind.enumType,
  ),
  _Rule(
    RegExp(
      r'^\s*(?:export\s+)?(?:declare\s+)?type\s+([A-Za-z_$][\w$]*)\s*[=<]',
    ),
    SymbolKind.interfaceType,
  ),
  _Rule(
    RegExp(
      r'^\s*(?:export\s+)?(?:default\s+)?(?:declare\s+)?(?:async\s+)?'
      r'function\s*\*?\s*([A-Za-z_$][\w$]*)',
    ),
    SymbolKind.function,
  ),
  // `const render = (props) => {` reads as a function to every JS developer,
  // so the outline treats it as one.
  _Rule(
    RegExp(
      r'^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*)'
      r'\s*(?::[^=]+)?=\s*(?:async\s+)?'
      r'(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*(?::[^=]+)?=>',
    ),
    SymbolKind.function,
  ),
  _Rule(
    RegExp(
      r'^(\s+)(?:(?:public|private|protected|static|readonly|abstract|'
      r'override|async)\s+)*(?:(?:get|set)\s+)?\*?\s*'
      r'([A-Za-z_$][\w$]*)\s*(?:<[^>(]*>)?\s*\(',
    ),
    SymbolKind.method,
    nameGroup: 2,
    resolveKind: (RegExpMatch match, int level) =>
        match.group(2) == 'constructor'
            ? SymbolKind.constructor
            : SymbolKind.method,
    accept: _hasDeclarationTail,
  ),
];

// --- Python ---------------------------------------------------------------

final List<_Rule> _pythonRules = <_Rule>[
  _Rule(RegExp(r'^\s*class\s+([A-Za-z_]\w*)'), SymbolKind.classType),
  _Rule(
    RegExp(r'^\s*(?:async\s+)?def\s+([A-Za-z_]\w*)'),
    SymbolKind.function,
    resolveKind: _methodWhenNested,
  ),
];

// --- Java -----------------------------------------------------------------

/// Java has no bare declarations: a method has either a return type or at least
/// one modifier. A constructor has the modifier but no type, which is exactly
/// how this tells `public Foo(` from `foo(` in a statement.
bool _javaIsDeclaration(RegExpMatch match, String line) {
  if (!_hasDeclarationTail(match, line)) {
    return false;
  }
  final String modifiers = match.group(2) ?? '';
  final String? type = match.group(3);
  if (type != null && _statementKeywords.contains(type.trim())) {
    return false;
  }
  return modifiers.trim().isNotEmpty || (type != null && type.isNotEmpty);
}

final List<_Rule> _javaRules = <_Rule>[
  _Rule(
    RegExp(
      r'^\s*(?:(?:public|protected|private|static|final|abstract|sealed|'
      r'non-sealed|strictfp)\s+)*(?:class|interface|enum|record)\s+'
      r'([A-Za-z_$][\w$]*)',
    ),
    SymbolKind.classType,
  ),
  _Rule(
    RegExp(
      r'^(\s*)((?:(?:public|protected|private|static|final|abstract|'
      r'synchronized|native|default|strictfp)\s+)*)(?:<[^>]+>\s*)?'
      r'(?:([\w$<>\[\],.?]+)\s+)?([A-Za-z_$][\w$]*)\s*\(',
    ),
    SymbolKind.method,
    nameGroup: 4,
    resolveKind: (RegExpMatch match, int level) =>
        (match.group(3) ?? '').trim().isEmpty
            ? SymbolKind.constructor
            : SymbolKind.method,
    accept: _javaIsDeclaration,
  ),
];

// --- Kotlin ---------------------------------------------------------------

final List<_Rule> _kotlinRules = <_Rule>[
  _Rule(
    RegExp(
      r'^\s*(?:(?:public|private|internal|protected|open|abstract|sealed|'
      r'data|enum|annotation|inner|value|companion)\s+)*'
      r'(?:class|interface|object)\s+([A-Za-z_`][\w`]*)',
    ),
    SymbolKind.classType,
  ),
  _Rule(
    RegExp(
      r'^\s*(?:(?:public|private|internal|protected|open|override|abstract|'
      r'final|suspend|inline|operator|infix|external|tailrec)\s+)*'
      r'fun\s+(?:<[^>]+>\s*)?(?:[\w.<>?]+\.)?([A-Za-z_`][\w`]*)',
    ),
    SymbolKind.function,
    resolveKind: _methodWhenNested,
  ),
];

// --- Go -------------------------------------------------------------------

final List<_Rule> _goRules = <_Rule>[
  _Rule(
    RegExp(r'^func\s+(?:\(\s*([^)]*)\)\s+)?([A-Za-z_]\w*)'),
    SymbolKind.function,
    nameGroup: 2,
    detailGroup: 1,
    resolveKind: (RegExpMatch match, int level) =>
        match.group(1) == null ? SymbolKind.function : SymbolKind.method,
  ),
  _Rule(
    RegExp(r'^type\s+([A-Za-z_]\w*)\s+struct\b'),
    SymbolKind.classType,
  ),
  _Rule(
    RegExp(r'^type\s+([A-Za-z_]\w*)\s+interface\b'),
    SymbolKind.interfaceType,
  ),
];

// --- Rust -----------------------------------------------------------------

final List<_Rule> _rustRules = <_Rule>[
  _Rule(
    RegExp(
      r'^\s*(?:pub(?:\s*\([^)]*\))?\s+)?(?:default\s+)?(?:const\s+)?'
      r'(?:async\s+)?(?:unsafe\s+)?(?:extern\s+"[^"]*"\s+)?'
      r'fn\s+([A-Za-z_]\w*)',
    ),
    SymbolKind.function,
    resolveKind: _methodWhenNested,
  ),
  _Rule(
    RegExp(r'^\s*(?:pub(?:\s*\([^)]*\))?\s+)?struct\s+([A-Za-z_]\w*)'),
    SymbolKind.classType,
  ),
  _Rule(
    RegExp(r'^\s*(?:pub(?:\s*\([^)]*\))?\s+)?enum\s+([A-Za-z_]\w*)'),
    SymbolKind.enumType,
  ),
  _Rule(
    RegExp(
      r'^\s*(?:pub(?:\s*\([^)]*\))?\s+)?(?:unsafe\s+)?trait\s+([A-Za-z_]\w*)',
    ),
    SymbolKind.interfaceType,
  ),
  _Rule(
    RegExp(r'^\s*(?:pub(?:\s*\([^)]*\))?\s+)?mod\s+([A-Za-z_]\w*)'),
    SymbolKind.module,
  ),
  // `impl Display for Point` — the useful name is the type being implemented,
  // with the trait as the detail line.
  _Rule(
    RegExp(
      r'^\s*(?:unsafe\s+)?impl(?:\s*<[^>]*>)?\s+'
      r'(?:([\w:]+(?:<[^>]*>)?)\s+for\s+)?([\w:]+)',
    ),
    SymbolKind.classType,
    nameGroup: 2,
    detailGroup: 1,
  ),
];
