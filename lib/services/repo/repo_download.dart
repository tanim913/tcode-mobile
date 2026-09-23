/// Downloading a public repository as a branch archive.
///
/// Deliberately narrow: public repositories only, no authentication, no git
/// protocol. The implementation is chosen by the conditional export in
/// `repo_download_factory.dart`, so this file stays free of `dart:io` and the
/// web build still compiles.
library;

import 'dart:typed_data';

/// How far along a download is.
class DownloadProgress {
  const DownloadProgress({required this.received, required this.total});

  final int received;

  /// Bytes expected, or null when the server does not say.
  final int? total;

  double? get fraction =>
      total == null || total == 0 ? null : received / total!;
}

typedef DownloadProgressCallback = void Function(DownloadProgress);

abstract interface class RepoDownload {
  /// Whether this build can reach the network at all.
  ///
  /// False in the Play flavour, which declares no `INTERNET` permission, and
  /// on the web where the archive hosts send no CORS headers. The UI reads
  /// this rather than assuming, so the offline builds say why instead of
  /// failing at the first request.
  bool get isAvailable;

  /// Why downloading is unavailable, for the UI to show.
  String get unavailableReason;

  /// Fetches [url], following redirects.
  Future<Uint8List> fetch(Uri url, {DownloadProgressCallback? onProgress});
}

/// Largest archive this app will pull into memory.
///
/// The bytes are unzipped in memory, so a huge repository is an out-of-memory
/// crash rather than a slow download. Refused up front with the size named.
const int kMaxArchiveBytes = 100 * 1024 * 1024;
