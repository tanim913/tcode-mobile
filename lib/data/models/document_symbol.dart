/// A named thing found inside a document — a class, a function, a heading.
///
/// Deliberately free of any Flutter or language-server types. Today the only
/// producer is the regex-based [SymbolExtractor], but the model is shaped the
/// way a real language server reports symbols, so swapping the producer later
/// does not change the outline panel or Go to Symbol.
library;

import 'package:flutter/foundation.dart';

/// What kind of declaration a symbol is.
///
/// Icons and colours are chosen in the presentation layer, so the model stays
/// usable from a background isolate and from tests with no widget binding.
enum SymbolKind {
  classType('Class'),
  interfaceType('Interface'),
  enumType('Enum'),
  constructor('Constructor'),
  method('Method'),
  function('Function'),
  property('Property'),
  module('Module'),
  heading('Heading');

  const SymbolKind(this.label);

  final String label;
}

@immutable
class DocumentSymbol {
  const DocumentSymbol({
    required this.name,
    required this.kind,
    required this.line,
    required this.column,
    this.level = 0,
    this.detail,
  });

  final String name;

  final SymbolKind kind;

  /// 1-based, matching what the editor and the status bar show.
  final int line;

  /// 1-based column of the symbol's name, so Go to Symbol can land the caret
  /// on the identifier rather than at the start of the line.
  final int column;

  /// Nesting depth for indentation in the outline: a method inside a class is
  /// 1, a Markdown `###` is 2. Flat lists are all 0.
  final int level;

  /// Optional second line, e.g. a receiver type or a signature fragment.
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is DocumentSymbol &&
      other.name == name &&
      other.kind == kind &&
      other.line == line &&
      other.column == column &&
      other.level == level;

  @override
  int get hashCode => Object.hash(name, kind, line, column, level);

  @override
  String toString() => '$kind $name @$line:$column (level $level)';
}
