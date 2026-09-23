/// Turns a file on disk into an [OpenTab], applying the size, binary, image
/// and long-line guards before anything reaches the editor.
///
/// Separated from the tab controller so the rules can be unit tested without a
/// widget tree, and so "what happens when you open a 40 MB file" is answered in
/// one readable place.
library;

import 'dart:typed_data';

import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/data/models/text_format.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/filesystem/text_codec.dart';
import 'package:pocket_code/services/language/language_registry.dart';
import 'package:pocket_code/services/language/language_service.dart';

/// Extensions shown in the image viewer rather than the text editor.
const Set<String> kImageExtensions = <String>{
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
};

class DocumentLoader {
  const DocumentLoader({
    this.languages = const LexicalLanguageService(),
  });

  final LanguageService languages;

  /// Reads [node] and decides how it should be presented.
  ///
  /// Throws [AppFailure] for anything that stops the file opening at all; a
  /// file that opens in a restricted mode returns normally with the reason set
  /// on the tab, because that is information rather than an error.
  Future<OpenTab> load({
    required FileNode node,
    required int rootIndex,
    required FileSystemProvider provider,
    required AppSettings settings,
    bool preview = false,
  }) async {
    // Re-stat rather than trusting the size from a cached directory listing:
    // the whole point of the guard is to not load something enormous, and a
    // stale size defeats it.
    final FileSystemNode fresh = await provider.stat(node.id);
    final int size = fresh is FileNode ? fresh.size : node.size;
    final FileNode current = fresh is FileNode ? fresh : node;

    if (size > AppLimits.refuseFileSizeBytes) {
      throw UnsupportedOperationFailure(
        what: 'This file is ${formatBytes(size)}, which is too large to safely '
            'open in the editor. Use Open with or Share instead.',
        path: node.displayPath,
      );
    }

    if (kImageExtensions.contains(node.extension)) {
      return _restricted(
        node: current,
        rootIndex: rootIndex,
        restriction: DocumentRestriction.image,
        preview: preview,
      );
    }

    final Uint8List bytes = await provider.readBytes(node.id);

    if (TextCodec.isBinary(bytes)) {
      return _restricted(
        node: current,
        rootIndex: rootIndex,
        restriction: DocumentRestriction.binary,
        preview: preview,
        notice: 'This is a binary file, so it is not shown as text.',
      );
    }

    // A file that is not valid UTF-8 still opens — as Latin-1, with a notice —
    // rather than refusing. Latin-1 cannot fail, so the bytes round-trip and
    // saving cannot corrupt the file.
    TextFileContents contents;
    String? encodingNotice;
    try {
      contents = TextCodec.decode(bytes);
    } on EncodingFailure {
      contents = TextCodec.decode(bytes, forced: TextEncoding.latin1);
      encodingNotice = 'This file is not valid UTF-8, so it was opened as '
          'Latin-1. Check it looks right before saving.';
    }

    final String firstLine =
        contents.text.isEmpty ? '' : contents.text.split('\n').first;

    DocumentRestriction restriction = DocumentRestriction.none;
    String? notice = encodingNotice;

    if (size > settings.readOnlyFileSizeBytes) {
      restriction = DocumentRestriction.tooLargeToEdit;
      notice = 'Opened read-only: this file is ${formatBytes(size)}, and '
          'highlighting is off to keep scrolling smooth.';
    } else if (TextCodec.hasExcessivelyLongLines(contents.text)) {
      restriction = DocumentRestriction.longLines;
      notice = 'Highlighting is off: this file has a line longer than '
          '${AppLimits.longLineCharacters} characters, which would make '
          'scrolling stutter.';
    } else if (size > settings.warnFileSizeBytes && notice == null) {
      notice = 'This is a large file (${formatBytes(size)}). Editing may feel '
          'slower than usual.';
    }

    return OpenTab(
      node: current,
      rootIndex: rootIndex,
      text: contents.text,
      savedText: contents.text,
      format: contents.format,
      language: languages.detect(current, firstLine: firstLine),
      indent: settings.editor.detectIndentation
          ? TextCodec.detectIndent(contents.text)
          : IndentStyle(
              useSpaces: settings.editor.insertSpaces,
              size: settings.editor.tabSize,
            ),
      isPreview: preview,
      restriction: restriction,
      notice: notice,
    );
  }

  OpenTab _restricted({
    required FileNode node,
    required int rootIndex,
    required DocumentRestriction restriction,
    required bool preview,
    String? notice,
  }) {
    return OpenTab(
      node: node,
      rootIndex: rootIndex,
      text: '',
      savedText: '',
      format: const TextFormat(),
      language: LanguageRegistry.plainText,
      indent: const IndentStyle.fallback(),
      isPreview: preview,
      restriction: restriction,
      notice: notice,
    );
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
