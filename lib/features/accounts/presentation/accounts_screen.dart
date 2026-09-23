/// Settings → Accounts: paste a token for GitHub or GitLab.
///
/// Says exactly what the token is for, which permissions it needs, where it is
/// kept and where it is sent — a screen that asks for a credential owes the
/// user all four.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/data/repositories/credentials_repository.dart';
import 'package:pocket_code/features/accounts/application/accounts_controller.dart';
import 'package:pocket_code/services/git_host/git_host_client.dart';
import 'package:pocket_code/services/git_host/git_hosts.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

/// The row on the settings screen that leads here.
class AccountsSummary extends ConsumerWidget {
  const AccountsSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AccountsState accounts = ref.watch(accountsProvider);
    final List<String> names = <String>[
      for (final Account a in accounts.accounts.values)
        '${a.host.label} (@${a.username})',
    ];
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.key_outlined, size: 16),
        label: Text(names.isEmpty ? 'Add a token' : names.join(', ')),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AccountsScreen()),
        ),
      ),
    );
  }
}

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    final AccountsState state = ref.watch(accountsProvider);
    final TextStyle? muted =
        Theme.of(context).textTheme.bodySmall?.copyWith(color: tokens.textMuted);

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(title: const Text('Accounts')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          Text(
            'A token lets this app download your private repositories and '
            'open pull requests (GitHub) or merge requests (GitLab) from the '
            'files you changed.\n\n'
            'It is kept in Android\'s encrypted keystore on this device and '
            'sent only to the host it belongs to, over HTTPS. Remove it here '
            'at any time, and revoke it on the host\'s website to be sure.',
            style: muted,
          ),
          const SizedBox(height: 16),
          if (!state.loaded)
            const Center(child: CircularProgressIndicator())
          else
            for (final RepoHost host in RepoHost.values) ...<Widget>[
              _HostCard(host: host, account: state[host]),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _HostCard extends ConsumerStatefulWidget {
  const _HostCard({required this.host, required this.account});

  final RepoHost host;
  final Account? account;

  @override
  ConsumerState<_HostCard> createState() => _HostCardState();
}

class _HostCardState extends ConsumerState<_HostCard> {
  final TextEditingController _token = TextEditingController();
  bool _busy = false;
  AppFailure? _error;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  /// A client with no token, only to read the host's own wording.
  GitHostClient get _describer =>
      clientFor(widget.host, transport: ref.read(httpTransportProvider));

  Future<void> _signIn() async {
    if (_token.text.trim().isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(accountsProvider.notifier)
          .signIn(widget.host, _token.text);
      _token.clear();
    } on AppFailure catch (failure) {
      _error = failure;
    }
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text('Remove the ${widget.host.label} token?'),
            content: const Text(
              'It is deleted from this device. It keeps working on the host '
              'until you revoke it there.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) {
      await ref.read(accountsProvider.notifier).signOut(widget.host);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppColorTokens tokens = theme.extension<AppColorTokens>()!;
    final TextStyle? muted =
        theme.textTheme.bodySmall?.copyWith(color: tokens.textMuted);
    final Account? account = widget.account;
    final GitHostClient describer = _describer;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.host.label, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (account != null) ...<Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.check_circle, size: 18, color: tokens.success),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Signed in as @${account.username}')),
                  TextButton(onPressed: _signOut, child: const Text('Remove')),
                ],
              ),
            ] else ...<Widget>[
              TextField(
                controller: _token,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !_busy,
                onSubmitted: (_) => _signIn(),
                decoration: InputDecoration(
                  labelText: 'Personal access token',
                  errorText: _error?.message,
                  errorMaxLines: 2,
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(_error!.hint, style: muted),
              ],
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: Text(_busy ? 'Checking…' : 'Sign in'),
                ),
              ),
              const SizedBox(height: 8),
              Text('Needs ${describer.neededPermissions}.', style: muted),
              const SizedBox(height: 6),
              _CopyableLink(url: describer.tokenPage),
            ],
          ],
        ),
      ),
    );
  }
}

/// The token page's address, with a copy button. There is no in-app browser
/// and no url_launcher dependency, so copying is the honest offer.
class _CopyableLink extends StatelessWidget {
  const _CopyableLink({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    return Row(
      children: <Widget>[
        Expanded(
          child: SelectableText(
            url,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: tokens.accent),
          ),
        ),
        IconButton(
          tooltip: 'Copy link',
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied')),
              );
            }
          },
        ),
      ],
    );
  }
}
