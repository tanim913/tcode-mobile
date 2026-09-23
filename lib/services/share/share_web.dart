/// Browser implementation of [ShareService].
///
/// `share_plus` maps text sharing onto the Web Share API where the browser has
/// one. File sharing and "Open with" have no browser equivalent that works
/// without a real path, so they refuse with a reason rather than silently
/// doing nothing.
library;

import 'dart:typed_data';

import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/share/share_service.dart';
import 'package:share_plus/share_plus.dart';

ShareService createShareService() => const WebShareService();

class WebShareService implements ShareService {
  const WebShareService();

  @override
  bool get canOpenWith => false;

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
    throw const UnsupportedOperationFailure(
      what: 'Sharing a file is not available in the browser. '
          'Copy the text instead.',
    );
  }

  @override
  Future<bool> openWith({
    required String name,
    required Uint8List bytes,
  }) async {
    throw const UnsupportedOperationFailure(
      what: '"Open with" is only available on Android.',
    );
  }
}
