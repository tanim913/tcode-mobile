/// Native [HttpTransport], on `dart:io`'s `HttpClient`.
///
/// Redirects are switched **off** here and followed by
/// `sendFollowingRedirects`, which is what keeps a token on the host it was
/// issued for. Availability follows the build flavour exactly as
/// `IoRepoDownload` does: only `full` declares `INTERNET`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show appFlavor;
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/git_host/http_transport.dart';
import 'package:pocket_code/services/repo/repo_download.dart';

HttpTransport createHttpTransport() => IoHttpTransport();

class IoHttpTransport implements HttpTransport {
  IoHttpTransport({String? flavor}) : _flavor = flavor ?? appFlavor;

  final String? _flavor;

  @override
  bool get isAvailable => !Platform.isAndroid || _flavor == 'full';

  @override
  Future<TransportResponse> send(
    TransportRequest request, {
    int maxBytes = 8 * 1024 * 1024,
    DownloadProgressCallback? onProgress,
  }) async {
    if (!isAvailable) {
      throw const UnsupportedOperationFailure(
        what: 'This build has no network permission at all.',
      );
    }
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..userAgent = 'TcodeMobile';
    try {
      final HttpClientRequest out =
          await client.openUrl(request.method, request.uri);
      out.followRedirects = false;
      request.headers.forEach(out.headers.set);
      final Uint8List? body = request.body;
      if (body != null) {
        out.contentLength = body.length;
        out.add(body);
      }
      final HttpClientResponse response = await out.close();

      final Map<String, String> headers = <String, String>{};
      response.headers.forEach((String name, List<String> values) {
        headers[name.toLowerCase()] = values.join(',');
      });

      final int? total =
          response.contentLength >= 0 ? response.contentLength : null;
      if (total != null && total > maxBytes) {
        throw UnsupportedOperationFailure(
          what: 'That is ${(total / (1024 * 1024)).round()} MB, more than '
              'this app will hold in memory.',
        );
      }
      final BytesBuilder builder = BytesBuilder(copy: false);
      await for (final List<int> chunk in response) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw const UnsupportedOperationFailure(
            what: 'That is larger than this app will hold in memory.',
          );
        }
        onProgress?.call(
          DownloadProgress(received: builder.length, total: total),
        );
      }
      return TransportResponse(
        status: response.statusCode,
        headers: headers,
        body: builder.takeBytes(),
      );
    } on SocketException catch (e) {
      throw UnknownFailure(
        detail: 'Could not reach ${request.uri.host}. Check your connection.',
        path: request.uri.host,
        cause: e,
      );
    } on HttpException catch (e) {
      throw UnknownFailure(
        detail: 'The connection to ${request.uri.host} failed part way.',
        path: request.uri.host,
        cause: e,
      );
    } finally {
      client.close();
    }
  }
}
