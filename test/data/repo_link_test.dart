library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/data/models/repo_link.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

void main() {
  final RepoLink link = RepoLink(
    host: RepoHost.gitlab,
    owner: 'me',
    name: 'app',
    branch: 'main',
    baseSha: 'a' * 40,
    downloadedAt: DateTime.utc(2026, 9, 22, 14, 32),
  );

  test('round-trips through JSON', () {
    final RepoLink back = RepoLink.decode(link.encode())!;
    expect(back.host, RepoHost.gitlab);
    expect(back.owner, 'me');
    expect(back.name, 'app');
    expect(back.branch, 'main');
    expect(back.baseSha, 'a' * 40);
    expect(back.downloadedAt, DateTime.utc(2026, 9, 22, 14, 32));
    expect(back.canPropose, isTrue);
  });

  test('garbage and hand edits disable the link rather than throwing', () {
    expect(RepoLink.decode(''), isNull);
    expect(RepoLink.decode('[1,2]'), isNull);
    expect(RepoLink.decode('{"host":"bitbucket","owner":"a","name":"b",'
        '"branch":"c"}'), isNull);
    expect(RepoLink.decode('{"host":"github","owner":"","name":"b",'
        '"branch":"c"}'), isNull);
  });

  test('a malformed base commit means no proposing, but the link survives',
      () {
    final RepoLink? back = RepoLink.decode('{"host":"github","owner":"a",'
        '"name":"b","branch":"c","baseSha":"not-a-sha"}');
    expect(back, isNotNull);
    expect(back!.baseSha, isNull);
    expect(back.canPropose, isFalse);
  });
}
