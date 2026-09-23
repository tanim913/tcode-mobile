/// VS Code-compatible "copy" naming for Duplicate and same-folder Paste.
///
/// Pure string maths with no file system in sight, so the awkward cases —
/// dotfiles, extensionless names, double extensions — are unit testable on
/// their own.
library;

abstract final class CopyNaming {
  /// Splits a name into the part a copy suffix goes after, and the extension
  /// it goes before.
  ///
  /// A leading dot is part of the name, not an extension: `.gitignore` must
  /// become `.gitignore copy`, never ` copy.gitignore`. A name with no dot at
  /// all (`Makefile`) has an empty extension and behaves the same way.
  static (String base, String extension) split(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot <= 0) {
      return (name, '');
    }
    return (name.substring(0, dot), name.substring(dot));
  }

  /// The next free `name copy.ext` / `name copy 2.ext` for [name] in a folder
  /// that already contains [taken].
  ///
  /// Always produces a new name — callers reach this only when the original is
  /// unavailable, so returning [name] unchanged would overwrite something.
  static String nextCopyName(String name, Set<String> taken) {
    final (String base, String extension) = split(name);

    // Duplicating `main copy.dart` should give `main copy 2.dart`, not
    // `main copy copy.dart`, which is what VS Code does and what reads right
    // after the third duplicate.
    final String stem = _stripCopySuffix(base);

    final String first = '$stem copy$extension';
    if (!taken.contains(first)) {
      return first;
    }
    // Bounded only by the folder's contents; a folder deep enough to exhaust
    // this loop has already hit a file system limit.
    for (int n = 2;; n++) {
      final String candidate = '$stem copy $n$extension';
      if (!taken.contains(candidate)) {
        return candidate;
      }
    }
  }

  /// A free name for [name] in a folder containing [taken], adding a copy
  /// suffix only when the original is actually occupied. Used by "Keep Both".
  static String uniqueName(String name, Set<String> taken) =>
      taken.contains(name) ? nextCopyName(name, taken) : name;

  static final RegExp _copySuffix = RegExp(r' copy(?: (\d+))?$');

  static String _stripCopySuffix(String base) =>
      base.replaceFirst(_copySuffix, '');
}
