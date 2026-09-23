/// Turning a repository URL into something downloadable.
///
/// This is **not** a git client. There is no git binary on Android and no
/// libgit2 without a native build, so what the app does instead is fetch the
/// branch archive that GitHub and GitLab already serve over plain HTTPS, and
/// unpack it. The user gets the files; they do not get `.git`, history, `pull`
/// or `push`, and the UI says "Download" rather than "Clone" for that reason.
library;

/// Where a repository lives, and which branch to take.
class RepoSource {
  const RepoSource({
    required this.host,
    required this.owner,
    required this.name,
    required this.branch,
  });

  final RepoHost host;
  final String owner;
  final String name;
  final String branch;

  /// The folder the archive should be unpacked into.
  String get folderName => name;

  /// The branch archive URL.
  ///
  /// Both hosts expose this without authentication for public repositories,
  /// which is exactly the limit of what this feature claims to do.
  Uri get archiveUrl => switch (host) {
        RepoHost.github => Uri.parse(
            'https://codeload.github.com/$owner/$name/zip/refs/heads/$branch',
          ),
        RepoHost.gitlab => Uri.parse(
            'https://gitlab.com/$owner/$name/-/archive/$branch/$name-$branch.zip',
          ),
      };

  /// The archive at exactly one commit, so the files match the commit that
  /// was recorded even if the branch moves during the download.
  Uri archiveUrlAt(String sha) => switch (host) {
        RepoHost.github =>
          Uri.parse('https://codeload.github.com/$owner/$name/zip/$sha'),
        RepoHost.gitlab => Uri.parse(
            'https://gitlab.com/$owner/$name/-/archive/$sha/$name-$sha.zip',
          ),
      };

  @override
  String toString() => '$owner/$name @ $branch';
}

enum RepoHost {
  github('GitHub'),
  gitlab('GitLab');

  const RepoHost(this.label);

  final String label;
}

/// Why a URL could not be used.
class RepoUrlError {
  const RepoUrlError(this.message);

  final String message;
}

/// Parses a repository URL, defaulting to [branch] when the URL names none.
///
/// Accepts the forms people actually paste: the page URL, the `.git` clone
/// URL, a `/tree/<branch>` link, and `owner/name` on its own. An SSH URL is
/// rejected with a reason, because it needs a key this app does not have.
///
/// Returns either a [RepoSource] or a [RepoUrlError]; never throws, so the
/// dialog can show the problem while the user is still typing.
Object parseRepoUrl(String input, {String branch = 'main'}) {
  final String raw = input.trim();
  if (raw.isEmpty) {
    return const RepoUrlError('Paste a repository link');
  }
  if (raw.startsWith('git@') || raw.startsWith('ssh://')) {
    return const RepoUrlError(
      'SSH links need a key this app does not have. Use the https:// link.',
    );
  }

  String rest = raw;
  RepoHost? host;

  for (final (String prefix, RepoHost candidate) in <(String, RepoHost)>[
    ('github.com/', RepoHost.github),
    ('gitlab.com/', RepoHost.gitlab),
  ]) {
    final int at = rest.toLowerCase().indexOf(prefix);
    if (at >= 0) {
      host = candidate;
      rest = rest.substring(at + prefix.length);
      break;
    }
  }

  if (host == null) {
    // A bare `owner/name` is assumed to be GitHub, which is where almost every
    // pasted shorthand comes from. Anything else needs a full URL.
    if (raw.contains('://') || raw.contains('.')) {
      return const RepoUrlError(
        'Only github.com and gitlab.com links work. Paste the repository page '
        'link, or download a ZIP and use "Import from ZIP".',
      );
    }
    host = RepoHost.github;
    rest = raw;
  }

  final List<String> parts = rest
      .split('/')
      .where((String s) => s.isNotEmpty)
      .toList();
  if (parts.length < 2) {
    return const RepoUrlError('That link has no owner and repository name');
  }

  final String owner = parts[0];
  String name = parts[1];
  if (name.toLowerCase().endsWith('.git')) {
    name = name.substring(0, name.length - 4);
  }
  // Strip a query or fragment that survived the split.
  name = name.split('?').first.split('#').first;

  if (owner.isEmpty || name.isEmpty) {
    return const RepoUrlError('That link has no owner and repository name');
  }

  // A `/tree/<branch>` or `/-/tree/<branch>` link names the branch, and the
  // one in the URL is what the user is looking at, so it wins over the default.
  String resolved = branch;
  final int tree = parts.indexOf('tree');
  if (tree >= 0 && tree + 1 < parts.length) {
    resolved = parts.sublist(tree + 1).join('/');
    resolved = resolved.split('?').first.split('#').first;
  }
  if (resolved.trim().isEmpty) {
    resolved = branch;
  }

  return RepoSource(
    host: host,
    owner: owner,
    name: name,
    branch: resolved.trim(),
  );
}

/// A folder name that is safe to create, derived from a repository name.
///
/// Repository names allow characters a file system may not, so the name is
/// filtered rather than trusted.
String folderNameFor(RepoSource source) {
  final String cleaned =
      source.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return cleaned.isEmpty ? 'repository' : cleaned;
}
