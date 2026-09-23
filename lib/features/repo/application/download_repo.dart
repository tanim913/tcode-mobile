/// Downloads a repository and unpacks it into a folder.
///
/// Everything here is composed from parts that already existed: the archive is
/// fetched by [RepoDownload], and unpacked by [ZipService], which already
/// refuses zip-slip, zip bombs and silent overwrites. This adds no new way to
/// write to disk.
library;

import 'dart:typed_data';

import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/repo_link.dart';
import 'package:pocket_code/services/archive/zip_service.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/git_host/git_host_client.dart';
import 'package:pocket_code/services/git_host/repo_link_store.dart';
import 'package:pocket_code/services/repo/repo_download.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

/// What stage the operation is at, for the progress dialog.
enum RepoStage { downloading, unpacking }

class RepoProgress {
  const RepoProgress({
    required this.stage,
    this.received = 0,
    this.total,
    this.files = 0,
  });

  final RepoStage stage;
  final int received;
  final int? total;
  final int files;

  /// How far along, or null when the server sent no length and a determinate
  /// bar would be a guess.
  double? get fraction {
    final int? size = total;
    if (size == null || size <= 0) {
      return null;
    }
    return (received / size).clamp(0.0, 1.0);
  }
}

typedef RepoProgressCallback = void Function(RepoProgress);

class RepoInstaller {
  const RepoInstaller({
    required this.download,
    this.api,
    this.zip = const ZipService(),
    this.clock = DateTime.now,
  });

  /// The anonymous archive route, used when there is no token.
  final RepoDownload download;

  /// The host's API. With a token it downloads too — the only way to reach a
  /// private repository. Without one it is still asked which commit the
  /// branch is at, so the folder can later be proposed back as a pull
  /// request. Null where the network is unavailable.
  final GitHostClient? api;

  final ZipService zip;
  final DateTime Function() clock;

  /// Downloads [source] and unpacks it into a new folder under [parentId].
  ///
  /// Returns the folder created. Throws [AlreadyExistsFailure] if a folder of
  /// that name is already there — replacing someone's working copy because a
  /// name collided is not something to do without asking.
  Future<FolderNode> install({
    required RepoSource source,
    required FileSystemProvider provider,
    required String parentId,
    RepoProgressCallback? onProgress,
  }) async {
    final String folderName = folderNameFor(source);
    if (await provider.exists(provider.childId(parentId, folderName))) {
      throw AlreadyExistsFailure(path: folderName);
    }

    onProgress?.call(const RepoProgress(stage: RepoStage.downloading));
    void progress(DownloadProgress p) => onProgress?.call(
          RepoProgress(
            stage: RepoStage.downloading,
            received: p.received,
            total: p.total,
          ),
        );

    final GitHostClient? api = this.api;
    String? sha;
    final Uint8List archive;
    if (api != null && api.token != null) {
      sha = await api.resolveBranch(source);
      archive = await api.downloadArchive(source, sha, onProgress: progress);
    } else {
      if (api != null) {
        try {
          sha = await api.resolveBranch(source);
        } on AppFailure {
          // Best effort. The archive request below reports the real problem
          // (a wrong branch, a private repository) in its own words; all that
          // is lost here is the ability to propose changes later.
          sha = null;
        }
      }
      archive = await download.fetch(
        sha == null ? source.archiveUrl : source.archiveUrlAt(sha),
        onProgress: progress,
      );
    }

    onProgress?.call(const RepoProgress(stage: RepoStage.unpacking));
    final FolderNode folder = await provider.createFolder(parentId, folderName);

    try {
      await zip.import(
        provider: provider,
        folderId: folder.id,
        bytes: archive,
        onProgress: (_) {},
      );
    } on AppFailure {
      // A half-unpacked folder is worse than none: it looks like a working
      // checkout. Remove it before reporting the failure.
      await provider.delete(folder.id).catchError((Object _) {});
      rethrow;
    }

    // These archives wrap everything in one `repo-branch/` folder. Left as-is
    // the user opens a folder containing exactly one folder, every time.
    await _flattenSingleChild(provider, folder);

    // Written after flattening, so the recorded file list has the paths the
    // user sees. A failure here costs only the pull request feature, never
    // the download.
    try {
      await RepoLinkStore(provider).write(
        folder.id,
        RepoLink(
          host: source.host,
          owner: source.owner,
          name: source.name,
          branch: source.branch,
          baseSha: sha,
          downloadedAt: clock(),
        ),
      );
    } on AppFailure {
      // Deliberately swallowed; see above.
    }
    return folder;
  }

  /// Moves the contents up when the archive has a single top-level folder.
  Future<void> _flattenSingleChild(
    FileSystemProvider provider,
    FolderNode folder,
  ) async {
    final List<FileSystemNode> children = await provider.list(folder.id);
    if (children.length != 1 || children.single is! FolderNode) {
      return;
    }
    final FolderNode inner = children.single as FolderNode;
    for (final FileSystemNode node in await provider.list(inner.id)) {
      await provider.move(node.id, folder.id);
    }
    await provider.delete(inner.id);
  }
}
