/// Access tokens for GitHub and GitLab, kept in the platform's secure store.
///
/// On Android that is the Keystore, through `flutter_secure_storage`: the
/// token is encrypted with a key that never leaves the device's secure
/// hardware. It is never written to SharedPreferences, to a session file, to a
/// log or into an error message, and [toString] does not print it.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

/// The three operations the repository needs, so tests can use a map.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformSecretStore implements SecretStore {
  const PlatformSecretStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// A signed-in account: the host and the name it answered with.
class Account {
  const Account({required this.host, required this.username});

  final RepoHost host;
  final String username;
}

class CredentialsRepository {
  const CredentialsRepository(this._store);

  final SecretStore _store;

  String _tokenKey(RepoHost host) => 'token.${host.name}';
  String _userKey(RepoHost host) => 'user.${host.name}';

  /// Null when not signed in, or when the secure store cannot be read — a
  /// broken keystore must leave the app working, just signed out.
  Future<String?> tokenFor(RepoHost host) async {
    try {
      final String? token = await _store.read(_tokenKey(host));
      return token == null || token.isEmpty ? null : token;
    } on Object {
      return null;
    }
  }

  Future<Account?> accountFor(RepoHost host) async {
    try {
      final String? user = await _store.read(_userKey(host));
      if (user == null || await tokenFor(host) == null) {
        return null;
      }
      return Account(host: host, username: user);
    } on Object {
      return null;
    }
  }

  Future<void> save(RepoHost host, {
    required String token,
    required String username,
  }) async {
    await _store.write(_tokenKey(host), token);
    await _store.write(_userKey(host), username);
  }

  Future<void> remove(RepoHost host) async {
    await _store.delete(_tokenKey(host));
    await _store.delete(_userKey(host));
  }

  @override
  String toString() => 'CredentialsRepository()';
}
