/// Browser [HttpTransport]: not available, for the same reason repository
/// downloads are not — see `repo_download_web.dart`.
library;

import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/git_host/http_transport.dart';
import 'package:pocket_code/services/repo/repo_download.dart';

HttpTransport createHttpTransport() => const WebHttpTransport();

class WebHttpTransport implements HttpTransport {
  const WebHttpTransport();

  @override
  bool get isAvailable => false;

  @override
  Future<TransportResponse> send(
    TransportRequest request, {
    int maxBytes = 0,
    DownloadProgressCallback? onProgress,
  }) {
    throw const UnsupportedOperationFailure(
      what: 'Accounts are not available in the browser build.',
    );
  }
}
