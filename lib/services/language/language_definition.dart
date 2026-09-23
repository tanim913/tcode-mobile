/// Describes one programming language the editor understands.
///
/// Adding a language is adding one [LanguageDefinition] to the registry list —
/// no switch statements anywhere else in the app change.
library;

import 'package:flutter/foundation.dart';
import 'package:re_highlight/re_highlight.dart';

@immutable
class LanguageDefinition {
  const LanguageDefinition({
    required this.id,
    required this.label,
    required this.mode,
    this.extensions = const <String>[],
    this.fileNames = const <String>[],
    this.shebangs = const <String>[],
    this.lineComment,
    this.blockComment,
  });

  /// Stable id, persisted when the user overrides a file's language.
  final String id;

  /// Shown in the status bar and the language picker.
  final String label;

  /// The highlight.js grammar, or null for plain text.
  final Mode? mode;

  /// Lowercase, without the dot.
  final List<String> extensions;

  /// Exact file names that identify the language regardless of extension,
  /// e.g. `Dockerfile`, `Makefile`, `pubspec.yaml`.
  final List<String> fileNames;

  /// Interpreter names matched against a `#!` first line, e.g. `python3`.
  final List<String> shebangs;

  /// Prefix used by "Toggle line comment". Null means the language has none.
  final String? lineComment;

  /// Open and close markers for a block comment.
  final (String, String)? blockComment;

  bool get hasHighlighting => mode != null;
}
