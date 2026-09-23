/// A scripted [HttpTransport] that records every request. No sockets.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pocket_code/services/git_host/http_transport.dart';
import 'package:pocket_code/services/repo/repo_download.dart';

typedef Responder = TransportResponse Function(TransportRequest request);

class FakeTransport implements HttpTransport {
  FakeTransport({this.available = true});

  final bool available;
  final List<TransportRequest> requests = <TransportRequest>[];
  final List<(String, RegExp, Responder)> _routes =
      <(String, RegExp, Responder)>[];

  /// Answers [method] requests whose `host + path` matches [pattern]. Later
  /// routes win, so a test can override a default.
  void on(String method, String pattern, Responder responder) =>
      _routes.insert(0, (method, RegExp('^$pattern\$'), responder));

  void onJson(String method, String pattern, Object? json, {int status = 200}) =>
      on(method, pattern, (_) => jsonResponse(json, status: status));

  @override
  bool get isAvailable => available;

  @override
  Future<TransportResponse> send(
    TransportRequest request, {
    int maxBytes = 0,
    DownloadProgressCallback? onProgress,
  }) async {
    requests.add(request);
    final String target = '${request.uri.host}${request.uri.path}';
    for (final (String method, RegExp pattern, Responder responder)
        in _routes) {
      if (method == request.method && pattern.hasMatch(target)) {
        return responder(request);
      }
    }
    return jsonResponse(<String, Object?>{'message': 'Not Found'}, status: 404);
  }

  /// `METHOD host/path` for every request, in order.
  List<String> get log => <String>[
        for (final TransportRequest r in requests)
          '${r.method} ${r.uri.host}${r.uri.path}',
      ];

  Object? bodyOf(int index) {
    final Uint8List? body = requests[index].body;
    return body == null ? null : jsonDecode(utf8.decode(body));
  }
}

TransportResponse jsonResponse(
  Object? json, {
  int status = 200,
  Map<String, String> headers = const <String, String>{},
}) =>
    TransportResponse(
      status: status,
      headers: headers,
      body: Uint8List.fromList(utf8.encode(jsonEncode(json))),
    );
