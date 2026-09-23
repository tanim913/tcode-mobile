/// The one door to the network for signed-in repository work.
///
/// An interface so the GitHub and GitLab clients can be tested against a fake
/// that records every request, with no socket anywhere. The real one lives in
/// `http_transport_io.dart`, chosen by the conditional export in
/// `http_transport_factory.dart`, which keeps `dart:io` out of the web build.
///
/// Redirects are followed **here**, not by the platform, because of one rule:
/// a token must never reach a host it was not issued for. `api.github.com`
/// answers an archive request with a redirect to `codeload.github.com`, and a
/// client that forwards every header on redirect would hand the token over.
library;

import 'dart:typed_data';

import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/repo/repo_download.dart';

/// One outgoing request.
class TransportRequest {
  const TransportRequest({
    required this.method,
    required this.uri,
    this.headers = const <String, String>{},
    this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;

  /// Already encoded. JSON bodies are small; nothing large is ever uploaded in
  /// one request except a single file's blob.
  final Uint8List? body;

  /// The request to send after a redirect. 307 and 308 keep the method and
  /// body, as the specification requires; the others become a plain GET.
  TransportRequest redirectedTo(
    Uri next, {
    required int status,
    required bool keepAuth,
  }) {
    final Map<String, String> kept = <String, String>{
      for (final MapEntry<String, String> h in headers.entries)
        if (keepAuth || !_isCredential(h.key)) h.key: h.value,
    };
    final bool keepMethod = status == 307 || status == 308;
    return TransportRequest(
      method: keepMethod ? method : 'GET',
      uri: next,
      headers: kept,
      body: keepMethod ? body : null,
    );
  }

  /// Also used by tests, to assert that a redirect to another host is clean.
  static bool isCredentialHeader(String name) => _isCredential(name);

  static bool _isCredential(String name) {
    final String lower = name.toLowerCase();
    return lower == 'authorization' || lower == 'private-token';
  }

  /// Never prints a header value: some of them are tokens.
  @override
  String toString() => 'TransportRequest($method ${uri.host}${uri.path})';
}

/// A complete response. Bodies are collected in memory, capped by the caller.
class TransportResponse {
  const TransportResponse({
    required this.status,
    required this.body,
    this.headers = const <String, String>{},
  });

  final int status;

  /// Lower-cased names.
  final Map<String, String> headers;
  final Uint8List body;

  String? header(String name) => headers[name.toLowerCase()];

  bool get isRedirect =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;
}

abstract interface class HttpTransport {
  /// False in the Play flavour and on the web. See `RepoDownload.isAvailable`.
  bool get isAvailable;

  /// Sends exactly one request, **without following redirects**.
  ///
  /// [maxBytes] stops a body that grows past it, so an archive cannot fill
  /// memory before its size is known.
  Future<TransportResponse> send(
    TransportRequest request, {
    int maxBytes,
    DownloadProgressCallback? onProgress,
  });
}

/// How many hops before a redirect chain is treated as a loop.
const int kMaxRedirects = 5;

/// Sends [request], following redirects by hand.
///
/// Credentials survive a redirect only to the **same host**. Anything that is
/// not `https` is refused, before or after a redirect: a downgrade is not
/// something to do quietly with a token in hand.
Future<TransportResponse> sendFollowingRedirects(
  HttpTransport transport,
  TransportRequest request, {
  int maxBytes = 8 * 1024 * 1024,
  DownloadProgressCallback? onProgress,
}) async {
  TransportRequest current = request;
  for (int hop = 0; hop <= kMaxRedirects; hop++) {
    if (current.uri.scheme != 'https') {
      throw const UnsupportedOperationFailure(
        what: 'Only https:// links are used.',
      );
    }
    final TransportResponse response = await transport.send(
      current,
      maxBytes: maxBytes,
      onProgress: onProgress,
    );
    if (!response.isRedirect) {
      return response;
    }
    final String? location = response.header('location');
    if (location == null) {
      return response;
    }
    final Uri next = current.uri.resolve(location);
    current = current.redirectedTo(
      next,
      status: response.status,
      keepAuth: next.host == current.uri.host,
    );
  }
  throw UnknownFailure(
    detail: 'The host redirected more than $kMaxRedirects times.',
    path: request.uri.host,
  );
}
