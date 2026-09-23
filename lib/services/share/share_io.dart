/// Native implementation of [ShareService].
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/share/share_service.dart';
import 'package:share_plus/share_plus.dart';

/// The cache subdirectory the Android FileProvider is allowed to serve.
///
/// Must stay in step with `android/app/src/main/res/xml/file_paths.xml`; that
/// file exposes this folder and nothing else.
const String kShareFolder = 'shared';

ShareService createShareService() => const IoShareService();

class IoShareService implements ShareService {
  const IoShareService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('dev.tcode.mobile/saf');

  final MethodChannel _channel;

  @override
  bool get canOpenWith => Platform.isAndroid;

  @override
  Future<void> shareText(String text, {String? subject}) async {
    if (text.isEmpty) {
      throw const UnsupportedOperationFailure(what: 'There is nothing to share.');
    }
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }

  @override
  Future<void> shareFile({
    required String name,
    required Uint8List bytes,
  }) async {
    final File file = await _stage(name, bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile(file.path, name: name, mimeType: mimeTypeFor(name)),
        ],
        subject: name,
      ),
    );
  }

  @override
  Future<bool> openWith({
    required String name,
    required Uint8List bytes,
  }) async {
    if (!canOpenWith) {
      throw const UnsupportedOperationFailure(
        what: '"Open with" is only available on Android.',
      );
    }
    final File file = await _stage(name, bytes);
    try {
      return await _channel.invokeMethod<bool>('openWith', <String, Object?>{
            'path': file.path,
            'mime': mimeTypeFor(name),
          }) ??
          false;
    } on PlatformException catch (e) {
      throw UnknownFailure(
        detail: e.message ?? 'No app could open this file.',
        path: name,
        cause: e,
      );
    } on MissingPluginException {
      throw const UnsupportedOperationFailure(
        what: '"Open with" is only available on Android.',
      );
    }
  }

  /// Writes [bytes] into the share cache and returns the file.
  ///
  /// The folder is wiped each time, so yesterday's shared copy is not left in
  /// cache where another app could still hold a URI for it. It is also the only
  /// path the FileProvider exposes, so another app never receives a handle on
  /// the user's working file — only on this copy.
  Future<File> _stage(String name, Uint8List bytes) async {
    final Directory cache = await getTemporaryDirectory();
    final Directory dir = Directory(p.join(cache.path, kShareFolder));
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
    final File file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes);
    return file;
  }
}
