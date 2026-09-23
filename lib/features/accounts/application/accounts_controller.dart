/// Who the app is signed in as, on each host.
///
/// Signing in is pasting a personal access token. It is validated against the
/// host before it is stored, so a typo is caught on the Accounts screen rather
/// than at the end of a download.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/repositories/credentials_repository.dart';
import 'package:pocket_code/services/git_host/git_host_client.dart';
import 'package:pocket_code/services/git_host/git_hosts.dart';
import 'package:pocket_code/services/git_host/http_transport.dart';
import 'package:pocket_code/services/git_host/http_transport_factory.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

/// The network, for repository work. Unavailable in the Play build and on web.
final Provider<HttpTransport> httpTransportProvider =
    Provider<HttpTransport>((Ref ref) => createHttpTransport());

/// Null wherever there is no network: a token the app can never use is not
/// worth asking for, and the Play build must not look as if it signs in.
final Provider<CredentialsRepository?> credentialsRepositoryProvider =
    Provider<CredentialsRepository?>((Ref ref) {
  return ref.watch(httpTransportProvider).isAvailable
      ? const CredentialsRepository(PlatformSecretStore())
      : null;
});

@immutable
class AccountsState {
  const AccountsState({
    this.accounts = const <RepoHost, Account>{},
    this.loaded = false,
  });

  final Map<RepoHost, Account> accounts;
  final bool loaded;

  Account? operator [](RepoHost host) => accounts[host];
}

class AccountsController extends Notifier<AccountsState> {
  @override
  AccountsState build() {
    unawaited(_load());
    return const AccountsState();
  }

  CredentialsRepository? get _repo => ref.read(credentialsRepositoryProvider);

  bool get available => _repo != null;

  Future<void> _load() async {
    final CredentialsRepository? repo = _repo;
    final Map<RepoHost, Account> accounts = <RepoHost, Account>{};
    if (repo != null) {
      for (final RepoHost host in RepoHost.values) {
        final Account? account = await repo.accountFor(host);
        if (account != null) {
          accounts[host] = account;
        }
      }
    }
    state = AccountsState(accounts: accounts, loaded: true);
  }

  /// Checks [token] with the host, then stores it. Throws the host's refusal
  /// as an `AppFailure`, and stores nothing in that case.
  Future<Account> signIn(RepoHost host, String token) async {
    final CredentialsRepository? repo = _repo;
    final String trimmed = token.trim();
    if (repo == null || trimmed.isEmpty) {
      throw const UnsupportedOperationFailure(
        what: 'Paste a token first. Accounts are only available in the '
            'direct-APK build.',
      );
    }
    final String username = await clientFor(
      host,
      transport: ref.read(httpTransportProvider),
      token: trimmed,
    ).whoAmI();
    await repo.save(host, token: trimmed, username: username);
    final Account account = Account(host: host, username: username);
    state = AccountsState(
      accounts: <RepoHost, Account>{...state.accounts, host: account},
      loaded: true,
    );
    return account;
  }

  Future<void> signOut(RepoHost host) async {
    await _repo?.remove(host);
    state = AccountsState(
      accounts: <RepoHost, Account>{...state.accounts}..remove(host),
      loaded: true,
    );
  }

  Future<void> signOutAll() async {
    for (final RepoHost host in RepoHost.values) {
      await signOut(host);
    }
  }

  /// A client for [host], signed in when there is a token. Null where there is
  /// no network at all.
  Future<GitHostClient?> clientForHost(RepoHost host) async {
    final HttpTransport transport = ref.read(httpTransportProvider);
    if (!transport.isAvailable) {
      return null;
    }
    return clientFor(
      host,
      transport: transport,
      token: await _repo?.tokenFor(host),
    );
  }
}

final NotifierProvider<AccountsController, AccountsState> accountsProvider =
    NotifierProvider<AccountsController, AccountsState>(
  AccountsController.new,
);
