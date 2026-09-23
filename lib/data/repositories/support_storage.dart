/// App-private storage for the app's own state files.
///
/// Session, snippets, recent items and file history all need the same handful
/// of operations against the same directory, and all of them must go through a
/// [FileSystemProvider] rather than `dart:io` — that is what lets the same code
/// work on web, where this data lives in the Origin Private File System.
///
/// Every method is forgiving by design. This is the app's own bookkeeping, not
/// the user's work: a settings file that cannot be read should degrade the
/// feature that owns it, never stop the app from starting.
library;

import 'dart:convert';

import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/text_format.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';

class SupportStorage {
  const SupportStorage({required this.provider, required this.rootId});

  final FileSystemProvider provider;

  /// The app's private support directory within [provider].
  final String rootId;

  String idFor(String name) => provider.childId(rootId, name);

  /// The object in [name], or null when it is missing, unreadable or not an
  /// object. Never throws.
  Future<Map<String, Object?>?> readJson(String name) async {
    try {
      final String id = idFor(name);
      if (!await provider.exists(id)) {
        return null;
      }
      final Object? decoded =
          jsonDecode((await provider.readText(id)).text) as Object?;
      return decoded is Map<String, Object?> ? decoded : null;
    } on Object {
      return null;
    }
  }

  Future<void> writeJson(String name, Map<String, Object?> json) =>
      writeTextFile(idFor(name), const JsonEncoder.withIndent('  ').convert(json));

  /// Creates [id] if it does not exist, then writes [text] to it.
  Future<void> writeTextFile(String id, String text) async {
    if (!await provider.exists(id)) {
      await provider.createFile(
        provider.parentOf(id) ?? rootId,
        provider.nameOf(id),
      );
    }
    // `endsWithNewline: false` matters: the default appends a trailing newline,
    // which is right for a source file the user is editing and wrong for the
    // app's own data. A history snapshot in particular has to come back exactly
    // as it went in, or every restore would add another blank line.
    await provider.writeText(
      id,
      text,
      const TextFormat(endsWithNewline: false),
    );
  }

  Future<String?> readTextFile(String id) async {
    try {
      if (!await provider.exists(id)) {
        return null;
      }
      return (await provider.readText(id)).text;
    } on Object {
      return null;
    }
  }

  /// The id of a folder directly under the support root, created if needed.
  Future<String> ensureFolder(String name) async {
    final String id = idFor(name);
    if (!await provider.exists(id)) {
      await provider.createFolder(rootId, name);
    }
    return id;
  }

  /// Deletes [id], ignoring failure.
  ///
  /// Housekeeping follows the same rule as the trash purge: nothing the user
  /// asked for is at stake, so a failure to tidy up must not surface as an
  /// error they can do nothing about.
  Future<void> deleteQuietly(String id) async {
    try {
      if (await provider.exists(id)) {
        await provider.delete(id);
      }
    } on AppFailure {
      // Housekeeping.
    }
  }
}
