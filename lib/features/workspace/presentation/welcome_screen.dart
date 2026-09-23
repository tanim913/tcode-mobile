/// Shown when no workspace is open.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/core/constants/app_info.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/features/accounts/application/accounts_controller.dart';
import 'package:pocket_code/features/repo/application/download_repo.dart';
import 'package:pocket_code/features/repo/presentation/download_repo_dialog.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';
import 'package:pocket_code/features/workspace/presentation/recent_list.dart';
import 'package:pocket_code/services/filesystem/provider_factory.dart';
import 'package:pocket_code/services/git_host/git_host_client.dart';
import 'package:pocket_code/services/repo/repo_download.dart';
import 'package:pocket_code/services/repo/repo_download_factory.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _busy = false;
  String? _error;

  /// Progress of a running download, or null when nothing is downloading.
  ///
  /// A repository can easily be tens of megabytes — the one this was tested
  /// against is 47 MB — and a bare spinner for three minutes is
  /// indistinguishable from the app having hung. `RepoInstaller` already
  /// reports bytes and stage; this shows them.
  RepoProgress? _progress;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    try {
      await action();
    } on AppFailure catch (failure) {
      if (mounted) {
        setState(() => _error = '${failure.message}. ${failure.hint}');
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  /// "Downloading… 12.4 MB of 47.0 MB", or the stage alone when the server
  /// sends no length.
  String _progressLabel(RepoProgress progress) {
    String mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return switch (progress.stage) {
      RepoStage.downloading when progress.total != null =>
        'Downloading… ${mb(progress.received)} of ${mb(progress.total!)}',
      RepoStage.downloading when progress.received > 0 =>
        'Downloading… ${mb(progress.received)}',
      RepoStage.downloading => 'Downloading…',
      RepoStage.unpacking => 'Unpacking…',
    };
  }

  /// Downloads a repository into the Projects folder and opens it — through
  /// the host's API with the account's token when there is one, which is what
  /// reaches a private repository.
  ///
  /// Always into Projects rather than wherever the user is: that folder always
  /// exists, always works, and needs no permission — so the download cannot
  /// fail for a reason unrelated to the download.
  ///
  /// What is then *opened* is the downloaded folder itself, not Projects.
  /// Opening Projects showed every repository ever downloaded side by side, so
  /// downloading a second one looked as though the first had come back.
  Future<void> _downloadRepo() async {
    final RepoDownload download = createRepoDownload();
    final RepoSource? source = await promptForRepo(
      context,
      available: download.isAvailable,
      unavailableReason: download.unavailableReason,
    );
    if (source == null || !mounted) {
      return;
    }

    await _run(() async {
      final PickedRoot projects = await openProjectsFolder();
      final GitHostClient? api = await ref
          .read(accountsProvider.notifier)
          .clientForHost(source.host);
      final FolderNode folder =
          await RepoInstaller(download: download, api: api).install(
            source: source,
            provider: projects.provider,
            parentId: projects.rootId,
            onProgress: (RepoProgress progress) {
              if (mounted) {
                setState(() => _progress = progress);
              }
            },
          );
      ref
          .read(workspaceProvider.notifier)
          .openFolder(
            PickedRoot(
              provider: projects.provider,
              rootId: folder.id,
              displayName: folder.name,
            ),
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context)
        .extension<AppColorTokens>()!;
    final bool canPick = ref.watch(canPickFolderProvider);
    final bool externalUsable = ref.watch(externalFoldersUsableProvider);

    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // The same `< >` mark as the launcher icon, drawn from the
                  // icon font rather than an image so it follows the theme's
                  // accent colour instead of shipping a second copy of the art.
                  Center(
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: tokens.accent.withValues(alpha: 0.14),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(14),
                        ),
                      ),
                      child: Icon(
                        Icons.code_rounded,
                        size: 30,
                        color: tokens.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    AppInfo.name,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    // Kept true per build. The Play flavour has no network
                    // permission at all. The direct-APK build downloads
                    // repositories and, when the user asks, sends their
                    // changes as a pull request — so "nothing is ever
                    // uploaded" would now be false there.
                    createRepoDownload().isAvailable
                        ? 'A code editor that keeps your work on this device. '
                              'Nothing is uploaded unless you open a pull '
                              'request.'
                        : 'A code editor that works entirely on this device. '
                              'It has no network access at all.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 26),

                  // Always works, everywhere, with no permission: app-private
                  // storage on Android, the Origin Private File System on web.
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            ref.read(workspaceProvider.notifier).openProjects,
                          ),
                    icon: const Icon(Icons.folder_special_outlined, size: 18),
                    label: const Text('Open my projects'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy || !canPick
                        ? null
                        : () => _run(
                            ref
                                .read(workspaceProvider.notifier)
                                .openPickedFolder,
                          ),
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('Open another folder…'),
                  ),

                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _downloadRepo,
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: const Text('Download a repository…'),
                  ),

                  if (!canPick) ...<Widget>[
                    const SizedBox(height: 12),
                    _Hint(
                      icon: Icons.info_outline,
                      text:
                          'This browser cannot open local folders. '
                          'Chrome or Edge on desktop can.',
                      tokens: tokens,
                    ),
                  ] else if (!externalUsable) ...<Widget>[
                    const SizedBox(height: 12),
                    _Hint(
                      icon: Icons.info_outline,
                      // Reached only on a platform that can show a picker but
                      // cannot read what it returns. Android used to be one,
                      // before the Storage Access Framework provider landed.
                      text:
                          'This platform can show a folder picker but '
                          'cannot read the folder it returns. '
                          '"Open my projects" is the reliable route here.',
                      tokens: tokens,
                    ),
                  ],

                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _Hint(
                      icon: Icons.error_outline,
                      text: _error!,
                      tokens: tokens,
                      color: tokens.danger,
                    ),
                  ],

                  RecentWorkspaceList(onOpened: () {}),
                  if (_busy) ...<Widget>[
                    const SizedBox(height: 18),
                    Center(
                      child: Column(
                        children: <Widget>[
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              // A determinate bar as soon as the size is
                              // known, so a large repository stops looking
                              // like a hang.
                              value: _progress?.fraction,
                            ),
                          ),
                          if (_progress != null) ...<Widget>[
                            const SizedBox(height: 10),
                            Text(
                              _progressLabel(_progress!),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({
    required this.icon,
    required this.text,
    required this.tokens,
    this.color,
  });

  final IconData icon;
  final String text;
  final AppColorTokens tokens;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color tone = color ?? tokens.textMuted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 14, color: tone),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tone),
          ),
        ),
      ],
    );
  }
}
