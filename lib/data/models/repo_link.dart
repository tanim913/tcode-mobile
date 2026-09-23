/// Which repository a downloaded folder came from, and at which commit.
///
/// Stored **inside** the folder as `.tcode/repo.json`, not in app-private
/// storage, so it travels with the folder through a rename, a move or a ZIP
/// export — the same reason git keeps `.git` beside the files.
///
/// Next to it, `.tcode/files` lists every file the download unpacked. That
/// list is what makes "deleted" exact: GitHub and GitLab archives honour
/// `export-ignore`, so a file can be in the remote tree yet never have been
/// downloaded, and without the list it would look deleted and a pull request
/// would delete it.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

/// The folder that holds the link, and everything else this app keeps inside
/// a repository. Never part of a change set or a pull request.
const String kRepoMetaFolder = '.tcode';
const String kRepoLinkFile = 'repo.json';
const String kRepoFilesList = 'files';

@immutable
class RepoLink {
  const RepoLink({
    required this.host,
    required this.owner,
    required this.name,
    required this.branch,
    required this.downloadedAt,
    this.baseSha,
  });

  final RepoHost host;
  final String owner;
  final String name;
  final String branch;

  /// The commit the files were downloaded at. Null when it could not be
  /// resolved, and then no pull request can be made: without the base, every
  /// change made on the remote since would look like a local revert.
  final String? baseSha;

  final DateTime downloadedAt;

  bool get canPropose => baseSha != null;

  RepoSource get source =>
      RepoSource(host: host, owner: owner, name: name, branch: branch);

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'host': host.name,
        'owner': owner,
        'name': name,
        'branch': branch,
        'baseSha': baseSha,
        'downloadedAt': downloadedAt.toUtc().toIso8601String(),
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Null for anything that is not a valid link — a hand-edited or truncated
  /// file must disable the feature, not crash the explorer.
  static RepoLink? decode(String text) {
    try {
      final Object? json = jsonDecode(text);
      if (json is! Map<String, Object?>) {
        return null;
      }
      final RepoHost? host = RepoHost.values
          .where((RepoHost h) => h.name == json['host'])
          .firstOrNull;
      final Object? owner = json['owner'];
      final Object? name = json['name'];
      final Object? branch = json['branch'];
      final Object? sha = json['baseSha'];
      if (host == null ||
          owner is! String ||
          name is! String ||
          branch is! String ||
          owner.isEmpty ||
          name.isEmpty ||
          branch.isEmpty) {
        return null;
      }
      final bool shaValid =
          sha is String && RegExp(r'^[0-9a-f]{40}$').hasMatch(sha);
      final Object? at = json['downloadedAt'];
      return RepoLink(
        host: host,
        owner: owner,
        name: name,
        branch: branch,
        baseSha: shaValid ? sha : null,
        downloadedAt: (at is String ? DateTime.tryParse(at) : null) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    } on FormatException {
      return null;
    }
  }
}
