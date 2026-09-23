/// Share, and Open with.
///
/// Both work from *bytes*, not from a path, because two of the three providers
/// have no path to give: a SAF document is a `content://` URI and a browser
/// handle has no location at all.
///
/// The implementation is chosen by the conditional export in
/// `share_factory.dart`, the same seam the file system uses — this file must
/// stay free of `dart:io` so the web build still compiles.
library;

import 'dart:typed_data';

import 'package:path/path.dart' as p;

abstract interface class ShareService {
  /// Shares plain text — a selection, or a path.
  Future<void> shareText(String text, {String? subject});

  /// Shares a file by content, under [name].
  Future<void> shareFile({required String name, required Uint8List bytes});

  /// Hands the file to another app with ACTION_VIEW.
  ///
  /// Returns false when the device has nothing registered for the type, so the
  /// caller can say so rather than appearing to do nothing.
  Future<bool> openWith({required String name, required Uint8List bytes});

  /// Whether this platform can do "Open with" at all.
  bool get canOpenWith;
}

/// Best-guess MIME type from a file name.
///
/// Deliberately small: a wrong specific type stops an app from opening a file
/// it could have handled, whereas `text/plain` and `application/octet-stream`
/// are safe fallbacks that always resolve to something.
String mimeTypeFor(String name) {
  final String ext = p.extension(name).toLowerCase().replaceFirst('.', '');
  return switch (ext) {
    'txt' || 'log' || 'ini' || 'cfg' || 'env' => 'text/plain',
    'md' || 'markdown' => 'text/markdown',
    'html' || 'htm' => 'text/html',
    'css' => 'text/css',
    'csv' => 'text/csv',
    'json' => 'application/json',
    'xml' => 'text/xml',
    'yaml' || 'yml' => 'text/yaml',
    'js' || 'mjs' || 'cjs' => 'text/javascript',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    'svg' => 'image/svg+xml',
    'pdf' => 'application/pdf',
    'zip' => 'application/zip',
    // Source files are text, and an app that handles text/plain can show them.
    'dart' ||
    'py' ||
    'java' ||
    'kt' ||
    'c' ||
    'cpp' ||
    'h' ||
    'go' ||
    'rs' ||
    'rb' ||
    'php' ||
    'sh' ||
    'sql' ||
    'ts' =>
      'text/plain',
    _ => 'application/octet-stream',
  };
}
