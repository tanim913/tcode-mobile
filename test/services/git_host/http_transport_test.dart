/// Following redirects by hand, and never carrying a token to another host.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/git_host/http_transport.dart';

import '../../support/fake_transport.dart';

TransportResponse redirect(String to, {int status = 302}) => TransportResponse(
      status: status,
      headers: <String, String>{'location': to},
      body: Uint8List(0),
    );

const Map<String, String> auth = <String, String>{
  'Authorization': 'Bearer secret-token',
  'Accept': 'application/json',
};

void main() {
  test('a redirect to another host drops the Authorization header', () async {
    final FakeTransport net = FakeTransport()
      ..on('GET', 'api.github.com/repos/o/r/zipball/abc',
          (_) => redirect('https://codeload.github.com/o/r/legacy.zip/abc'))
      ..onJson('GET', 'codeload.github.com/.*', <String, Object?>{});

    await sendFollowingRedirects(
      net,
      TransportRequest(
        method: 'GET',
        uri: Uri.parse('https://api.github.com/repos/o/r/zipball/abc'),
        headers: auth,
      ),
    );

    expect(net.requests, hasLength(2));
    expect(net.requests[0].headers['Authorization'], 'Bearer secret-token');
    expect(
      net.requests[1].headers.keys.where(TransportRequest.isCredentialHeader),
      isEmpty,
      reason: 'a token must never reach a host it was not issued for',
    );
    expect(net.requests[1].headers['Accept'], 'application/json',
        reason: 'only credentials are dropped');
  });

  test("GitLab's PRIVATE-TOKEN is a credential too", () async {
    final FakeTransport net = FakeTransport()
      ..on('GET', 'gitlab.com/a', (_) => redirect('https://cdn.example/b'))
      ..onJson('GET', 'cdn.example/b', <String, Object?>{});
    await sendFollowingRedirects(
      net,
      TransportRequest(
        method: 'GET',
        uri: Uri.parse('https://gitlab.com/a'),
        headers: const <String, String>{'PRIVATE-TOKEN': 'glpat-x'},
      ),
    );
    expect(net.requests[1].headers.containsKey('PRIVATE-TOKEN'), isFalse);
  });

  test('a same-host redirect keeps the credential', () async {
    final FakeTransport net = FakeTransport()
      ..on('GET', 'api.github.com/old', (_) => redirect('/new', status: 301))
      ..onJson('GET', 'api.github.com/new', <String, Object?>{});
    await sendFollowingRedirects(
      net,
      TransportRequest(
        method: 'GET',
        uri: Uri.parse('https://api.github.com/old'),
        headers: auth,
      ),
    );
    expect(net.requests[1].uri.path, '/new');
    expect(net.requests[1].headers['Authorization'], 'Bearer secret-token');
  });

  test('a redirect to plain http is refused, token or not', () async {
    final FakeTransport net = FakeTransport()
      ..on('GET', 'api.github.com/x', (_) => redirect('http://evil.example/'));
    await expectLater(
      sendFollowingRedirects(
        net,
        TransportRequest(
          method: 'GET',
          uri: Uri.parse('https://api.github.com/x'),
          headers: auth,
        ),
      ),
      throwsA(isA<UnsupportedOperationFailure>()),
    );
    expect(net.requests, hasLength(1));
  });

  test('a redirect loop ends as an error', () async {
    final FakeTransport net = FakeTransport()
      ..on('GET', 'a.example/loop', (_) => redirect('/loop'));
    await expectLater(
      sendFollowingRedirects(
        net,
        TransportRequest(method: 'GET', uri: Uri.parse('https://a.example/loop')),
      ),
      throwsA(isA<UnknownFailure>()),
    );
    expect(net.requests.length, kMaxRedirects + 1);
  });

  test('printing a request never prints a header value', () {
    final TransportRequest request = TransportRequest(
      method: 'GET',
      uri: Uri.parse('https://api.github.com/user'),
      headers: auth,
    );
    expect(request.toString(), isNot(contains('secret-token')));
  });
}
