/// Native implementation of [RepoDownload].
///
/// Availability is decided by the build flavour, not by trying a request: the
/// `play` flavour declares no `INTERNET` permission, so a request there fails
/// with an opaque socket error. Checking `appFlavor` lets the UI explain
/// instead.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show appFlavor;
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/repo/repo_download.dart';

RepoDownload createRepoDownload() => IoRepoDownload();

class IoRepoDownload implements RepoDownload {
  IoRepoDownload({String? flavor}) : _flavor = flavor ?? appFlavor;

  final String? _flavor;

  /// The flavour that declares `INTERNET`.
  ///
  /// Keeping the Play build genuinely unable to reach the network is what lets
  /// the rest of the app tell the user it has no network access and be right.
  static const String _networkFlavor = 'full';

  @override
  bool get isAvailable => !Platform.isAndroid || _flavor == _networkFlavor;

  @override
  String get unavailableReason =>
      'This build has no network permission at all, which is why it can '
      'promise that nothing leaves your device. Download the ZIP yourself and '
      'use "Import from ZIP", or install the direct-APK build.';

  @override
  Future<Uint8List> fetch(
    Uri url, {
    DownloadProgressCallback? onProgress,
  }) async {
    if (!isAvailable) {
      throw UnsupportedOperationFailure(what: unavailableReason);
    }
    if (url.scheme != 'https') {
      // Plain HTTP is refused rather than silently upgraded: the app declares
      // no cleartext permission, and a downgrade is not something to do
      // quietly on the user's behalf.
      throw const UnsupportedOperationFailure(
        what: 'Only https:// links are downloaded.',
      );
    }

    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..userAgent = 'TcodeMobile';
    try {
      final HttpClientRequest request = await client.getUrl(url);
      // Redirects are how both hosts serve archives; `followRedirects` is on by
      // default but the limit is stated so a redirect loop ends as an error.
      request.maxRedirects = 5;
      final HttpClientResponse response = await request.close();

      if (response.statusCode == 404) {
        // Deliberately not `NotFoundFailure`: that one is about a file on this
        // device and tells the user to refresh the explorer, which explains
        // nothing when the real cause is a branch called "main" that does not
        // exist. The wording the user sees has to match what actually happened.
        throw const RepositoryNotFoundFailure();
      }
      if (response.statusCode == 403 || response.statusCode == 401) {
        throw const RepositoryPrivateFailure();
      }
      if (response.statusCode >= 400) {
        throw UnknownFailure(
          detail: 'The server answered ${response.statusCode}.',
          path: url.host,
        );
      }

      final int? total =
          response.contentLength >= 0 ? response.contentLength : null;
      if (total != null && total > kMaxArchiveBytes) {
        throw UnsupportedOperationFailure(
          what: 'That archive is ${(total / (1024 * 1024)).round()} MB, more '
              'than this app will unpack in memory.',
        );
      }

      final BytesBuilder builder = BytesBuilder(copy: false);
      await for (final List<int> chunk in response) {
        builder.add(chunk);
        if (builder.length > kMaxArchiveBytes) {
          // Checked while streaming too: a server that reports no length could
          // otherwise fill memory before the size was known.
          throw const UnsupportedOperationFailure(
            what: 'That archive is larger than this app will unpack in memory.',
          );
        }
        onProgress?.call(
          DownloadProgress(received: builder.length, total: total),
        );
      }
      return builder.takeBytes();
    } on SocketException catch (e) {
      throw UnknownFailure(
        detail: 'Could not reach ${url.host}. Check your connection.',
        path: url.host,
        cause: e,
      );
    } on HttpException catch (e) {
      throw UnknownFailure(
        detail: 'The download failed part way through.',
        path: url.host,
        cause: e,
      );
    } finally {
      client.close();
    }
  }
}
