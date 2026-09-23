/// Proposing the changes in a downloaded folder as a pull request (GitHub) or
/// merge request (GitLab).
///
/// Every state the user can land in says what is going on and what to do:
/// a folder that was not downloaded, one downloaded before the app recorded
/// commits, no token, nothing changed, and every failure from the host.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/data/models/repo_link.dart';
import 'package:pocket_code/features/accounts/application/accounts_controller.dart';
import 'package:pocket_code/features/accounts/presentation/accounts_screen.dart';
import 'package:pocket_code/features/change_request/application/change_request_session.dart';
import 'package:pocket_code/features/change_request/presentation/change_request_widgets.dart';
import 'package:pocket_code/features/diff/presentation/diff_view.dart';
import 'package:pocket_code/services/diff/line_diff.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/git_host/change_set.dart';
import 'package:pocket_code/services/git_host/git_host_client.dart';
import 'package:pocket_code/services/git_host/repo_link_store.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

enum _Phase { loading, notLinked, noBase, needsToken, scanning, ready, sending, done }

class ChangeRequestScreen extends ConsumerStatefulWidget {
  const ChangeRequestScreen({
    required this.provider,
    required this.folderId,
    required this.folderName,
    super.key,
  });

  final FileSystemProvider provider;
  final String folderId;
  final String folderName;

  @override
  ConsumerState<ChangeRequestScreen> createState() =>
      _ChangeRequestScreenState();
}

class _ChangeRequestScreenState extends ConsumerState<ChangeRequestScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _message = TextEditingController();
  final TextEditingController _branch = TextEditingController();

  _Phase _phase = _Phase.loading;
  RepoLink? _link;
  ChangeRequestSession? _session;
  final Set<FileChange> _included = <FileChange>{};
  (int, int) _scanned = (0, 0);
  SubmitProgress? _progress;
  ChangeRequestResult? _result;
  AppFailure? _failure;

  String get _noun =>
      _link?.host == RepoHost.gitlab ? 'merge request' : 'pull request';

  @override
  void initState() {
    super.initState();
    _branch.text = defaultBranchName(DateTime.now());
    unawaited(_start());
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _message.dispose();
    _branch.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.loading;
      _failure = null;
    });
    final RepoLink? link = await RepoLinkStore(widget.provider).read(
      widget.folderId,
    );
    if (!mounted) {
      return;
    }
    _link = link;
    if (link == null) {
      setState(() => _phase = _Phase.notLinked);
      return;
    }
    if (!link.canPropose) {
      setState(() => _phase = _Phase.noBase);
      return;
    }
    final GitHostClient? client =
        await ref.read(accountsProvider.notifier).clientForHost(link.host);
    if (!mounted) {
      return;
    }
    if (client == null || client.token == null) {
      setState(() => _phase = _Phase.needsToken);
      return;
    }
    _session = ChangeRequestSession(
      provider: widget.provider,
      folderId: widget.folderId,
      link: link,
      client: client,
    );
    await _scan();
  }

  Future<void> _scan() async {
    final ChangeRequestSession? session = _session;
    if (session == null) {
      return;
    }
    setState(() {
      _phase = _Phase.scanning;
      _failure = null;
      _scanned = (0, 0);
    });
    try {
      final List<FileChange> changes = await session.scan(
        onProgress: (int done, int total) {
          if (mounted) {
            setState(() => _scanned = (done, total));
          }
        },
      );
      _included
        ..clear()
        ..addAll(changes);
    } on AppFailure catch (failure) {
      _failure = failure;
    }
    if (mounted) {
      setState(() => _phase = _Phase.ready);
    }
  }

  Future<void> _openDiff(FileChange change) async {
    final ChangeRequestSession? session = _session;
    if (session == null) {
      return;
    }
    try {
      final (String before, String after) = await session.textsOf(change);
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DiffScreen(
            title: change.path,
            subtitle: '${change.kind.label} — downloaded version, compared '
                'with this device',
            diff: diffLines(splitLines(before), splitLines(after)),
            editor: ref.read(settingsProvider).editor,
          ),
        ),
      );
    } on AppFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  String? get _formProblem {
    if (_included.isEmpty) {
      return 'Tick at least one file';
    }
    if (_title.text.trim().isEmpty) {
      return 'Give the $_noun a title';
    }
    return branchNameProblem(_branch.text);
  }

  Future<void> _send() async {
    final ChangeRequestSession? session = _session;
    if (session == null || _formProblem != null) {
      return;
    }
    final String title = _title.text.trim();
    final String message = _message.text.trim();
    final ChangeRequestDraft draft = ChangeRequestDraft(
      title: title,
      description: _description.text.trim(),
      commitMessage: message.isEmpty ? title : message,
      branch: _branch.text.trim(),
    );
    setState(() {
      _phase = _Phase.sending;
      _failure = null;
      _progress = null;
    });
    try {
      final ChangeRequestResult result = await session.submit(
        draft,
        session.changes.where(_included.contains).toList(),
        onProgress: (SubmitProgress p) {
          if (mounted) {
            setState(() => _progress = p);
          }
        },
      );
      if (mounted) {
        setState(() {
          _result = result;
          _phase = _Phase.done;
        });
      }
    } on AppFailure catch (failure) {
      if (mounted) {
        setState(() {
          _failure = failure;
          _phase = _Phase.ready;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    final String title =
        _noun == 'merge request' ? 'Merge request' : 'Pull request';
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(title: Text('$title · ${widget.folderName}')),
      body: switch (_phase) {
        _Phase.loading => const Center(child: CircularProgressIndicator()),
        _Phase.notLinked => const ChangeRequestMessage(
            icon: Icons.link_off,
            title: 'Not a downloaded repository',
            body: 'Only a folder made with "Download a repository" knows '
                'where it came from. Download it again from the welcome '
                'screen, then make your changes there.',
          ),
        _Phase.noBase => const ChangeRequestMessage(
            icon: Icons.history_toggle_off,
            title: 'The downloaded commit is unknown',
            body: 'This folder was downloaded without recording which commit '
                'it came from, so there is nothing to compare against. '
                'Download it again to propose changes.',
          ),
        _Phase.needsToken => ChangeRequestMessage(
            icon: Icons.key_outlined,
            title: 'Sign in to ${_link!.host.label} first',
            body: 'Opening a $_noun needs a token with write access. Add one '
                'under Settings → Accounts.',
            action: FilledButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AccountsScreen(),
                  ),
                );
                await _start();
              },
              child: const Text('Open Accounts'),
            ),
          ),
        _Phase.scanning => ChangeRequestMessage(
            icon: Icons.compare_arrows,
            title: 'Looking for changes…',
            body: _scanned.$2 == 0
                ? 'Asking ${_link!.host.label} for the downloaded files.'
                : 'Compared ${_scanned.$1} of ${_scanned.$2} files.',
          ),
        _Phase.sending => SubmitProgressView(progress: _progress),
        _Phase.done => ChangeRequestDone(result: _result!, noun: _noun),
        _Phase.ready => _form(tokens),
      },
    );
  }

  Widget _form(AppColorTokens tokens) {
    final AppFailure? failure = _failure;
    final List<FileChange> changes = _session?.changes ?? const <FileChange>[];
    final TextStyle? muted = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: tokens.textMuted);

    if (failure != null && changes.isEmpty) {
      return ChangeRequestMessage(
        icon: Icons.error_outline,
        title: failure.message,
        body: failure.hint,
        action: FilledButton(onPressed: _start, child: const Text('Try again')),
      );
    }
    if (changes.isEmpty) {
      return ChangeRequestMessage(
        icon: Icons.check,
        title: 'Nothing has changed',
        body: 'Every file matches the version downloaded from '
            '${_link!.owner}/${_link!.name} (${_link!.branch}).',
        action: OutlinedButton(onPressed: _scan, child: const Text('Check again')),
      );
    }

    final String? problem = _formProblem;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: <Widget>[
        if (failure != null)
          Container(
            color: tokens.danger.withValues(alpha: 0.12),
            padding: const EdgeInsets.all(12),
            child: Text('${failure.message}. ${failure.hint}'),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '${changes.length} changed '
            '${changes.length == 1 ? 'file' : 'files'} against '
            '${_link!.owner}/${_link!.name} (${_link!.branch}). Tap one to '
            'see the difference.',
            style: muted,
          ),
        ),
        for (final FileChange change in changes)
          ChangeRow(
            change: change,
            included: _included.contains(change),
            onToggle: (bool on) => setState(
              () => on ? _included.add(change) : _included.remove(change),
            ),
            onOpen: () => _openDiff(change),
          ),
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _title,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              TextField(
                controller: _message,
                decoration: const InputDecoration(
                  labelText: 'Commit message',
                  helperText: 'Leave empty to use the title',
                ),
              ),
              TextField(
                controller: _branch,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'New branch',
                  errorText: _branch.text.isEmpty
                      ? null
                      : branchNameProblem(_branch.text),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.call_split, size: 18),
                onPressed: problem == null ? _send : null,
                label: Text(
                  'Open $_noun with ${_included.length} '
                  '${_included.length == 1 ? 'file' : 'files'}',
                ),
              ),
              if (problem != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(problem, textAlign: TextAlign.center, style: muted),
              ],
              const SizedBox(height: 10),
              Text(
                'The commit is made on a new branch from the version you '
                'downloaded. If the repository has moved on since, the host '
                'shows any conflicts; this app does not merge.',
                style: muted,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
