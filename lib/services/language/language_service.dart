/// Language detection and language-aware text operations.
///
/// Declared as an interface so a language server client can replace it later
/// without touching the editor. Today's implementation is lexical only — it
/// never claims to understand code, and the outline it produces is labelled
/// "Basic outline" in the UI for exactly that reason.
library;

import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/services/language/language_definition.dart';
import 'package:pocket_code/services/language/language_registry.dart';

abstract interface class LanguageService {
  /// Best guess at the language of [node], optionally sharpened by the file's
  /// first line (for a `#!` shebang).
  LanguageDefinition detect(FileSystemNode node, {String? firstLine});

  /// Detection from a bare name, for cases where no node exists yet.
  LanguageDefinition detectByName(String fileName, {String? firstLine});

  List<LanguageDefinition> get available;
}

class LexicalLanguageService implements LanguageService {
  const LexicalLanguageService();

  @override
  List<LanguageDefinition> get available => LanguageRegistry.all;

  @override
  LanguageDefinition detect(FileSystemNode node, {String? firstLine}) =>
      detectByName(node.name, firstLine: firstLine);

  @override
  LanguageDefinition detectByName(String fileName, {String? firstLine}) {
    // Order matters. An exact file name is the strongest signal: `Dockerfile`
    // has no extension, and `pubspec.yaml` should be YAML even though a project
    // might map .yaml elsewhere.
    final LanguageDefinition? byName = _byFileName(fileName);
    if (byName != null) {
      return byName;
    }

    final LanguageDefinition? byExtension = _byExtension(_extensionOf(fileName));
    if (byExtension != null) {
      return byExtension;
    }

    // A shebang is the last resort, and the only signal an extensionless
    // script like `deploy` gives us.
    if (firstLine != null) {
      final LanguageDefinition? byShebang = _byShebang(firstLine);
      if (byShebang != null) {
        return byShebang;
      }
    }

    return LanguageRegistry.plainText;
  }

  LanguageDefinition? _byFileName(String fileName) {
    for (final LanguageDefinition l in LanguageRegistry.all) {
      if (l.fileNames.contains(fileName)) {
        return l;
      }
    }
    return null;
  }

  LanguageDefinition? _byExtension(String extension) {
    if (extension.isEmpty) {
      return null;
    }
    for (final LanguageDefinition l in LanguageRegistry.all) {
      if (l.extensions.contains(extension)) {
        return l;
      }
    }
    return null;
  }

  /// Parses `#!/usr/bin/env python3` and `#!/bin/bash` alike by taking the last
  /// path segment of each word and matching any of them.
  LanguageDefinition? _byShebang(String firstLine) {
    final String line = firstLine.trimLeft();
    if (!line.startsWith('#!')) {
      return null;
    }
    final List<String> words = line
        .substring(2)
        .split(RegExp(r'[\s/]+'))
        .where((String w) => w.isNotEmpty)
        .toList();
    for (final LanguageDefinition l in LanguageRegistry.all) {
      for (final String interpreter in l.shebangs) {
        if (words.contains(interpreter)) {
          return l;
        }
      }
    }
    return null;
  }

  /// Lowercase extension without the dot. A leading dot means a dotfile, so
  /// `.gitignore` has no extension rather than an extension of `gitignore`.
  String _extensionOf(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) {
      return '';
    }
    return fileName.substring(dot + 1).toLowerCase();
  }
}
