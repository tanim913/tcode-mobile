library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/data/repositories/credentials_repository.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

class MapStore implements SecretStore {
  final Map<String, String> values = <String, String>{};
  bool broken = false;

  @override
  Future<String?> read(String key) async {
    if (broken) {
      throw StateError('keystore unavailable');
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  test('stores, reads back and removes per host', () async {
    final MapStore store = MapStore();
    final CredentialsRepository repo = CredentialsRepository(store);

    await repo.save(RepoHost.github, token: 'ghp_sekrit', username: 'me');
    expect(await repo.tokenFor(RepoHost.github), 'ghp_sekrit');
    expect((await repo.accountFor(RepoHost.github))!.username, 'me');
    expect(await repo.tokenFor(RepoHost.gitlab), isNull);

    await repo.remove(RepoHost.github);
    expect(await repo.tokenFor(RepoHost.github), isNull);
    expect(await repo.accountFor(RepoHost.github), isNull);
    expect(store.values, isEmpty);
  });

  test('a broken keystore means signed out, not a crash', () async {
    final MapStore store = MapStore()..broken = true;
    final CredentialsRepository repo = CredentialsRepository(store);
    expect(await repo.tokenFor(RepoHost.github), isNull);
    expect(await repo.accountFor(RepoHost.github), isNull);
  });

  test('printing the repository never prints a token', () async {
    final CredentialsRepository repo = CredentialsRepository(MapStore());
    await repo.save(RepoHost.gitlab, token: 'glpat-sekrit', username: 'me');
    expect(repo.toString(), isNot(contains('sekrit')));
  });
}
