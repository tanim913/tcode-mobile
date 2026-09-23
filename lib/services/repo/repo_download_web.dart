/// Browser implementation: downloading is not available.
///
/// GitHub and GitLab serve their archives without CORS headers, so a browser
/// cannot read the response even though the request would succeed. Saying so
/// beats a request that fails with an opaque error.
library;

import 'dart:typed_data';

import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/repo/repo_download.dart';

RepoDownload createRepoDownload() => const WebRepoDownload();

class WebRepoDownload implements RepoDownload {
  const WebRepoDownload();

  @override
  bool get isAvailable => false;

  @override
  String get unavailableReason =>
      'Browsers cannot read these archives because the hosts send no CORS '
      'headers. Download the ZIP yourself and use "Import from ZIP".';

  @override
  Future<Uint8List> fetch(Uri url, {DownloadProgressCallback? onProgress}) {
    throw UnsupportedOperationFailure(what: unavailableReason);
  }
}
