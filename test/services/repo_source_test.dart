/// Turning a pasted repository link into a download.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

RepoSource ok(String input, {String branch = 'main'}) {
  final Object result = parseRepoUrl(input, branch: branch);
  expect(result, isA<RepoSource>(), reason: input);
  return result as RepoSource;
}

RepoUrlError bad(String input) {
  final Object result = parseRepoUrl(input);
  expect(result, isA<RepoUrlError>(), reason: input);
  return result as RepoUrlError;
}

void main() {
  group('the forms people paste', () {
    test('a GitHub page link', () {
      final RepoSource r = ok('https://github.com/flutter/samples');
      expect(r.host, RepoHost.github);
      expect(r.owner, 'flutter');
      expect(r.name, 'samples');
      expect(r.branch, 'main');
    });

    test('a clone link ending in .git', () {
      expect(ok('https://github.com/flutter/samples.git').name, 'samples');
    });

    test('a link with a trailing slash', () {
      expect(ok('https://github.com/flutter/samples/').name, 'samples');
    });

    test('a bare owner/name is treated as GitHub', () {
      final RepoSource r = ok('flutter/samples');
      expect(r.host, RepoHost.github);
      expect(r.owner, 'flutter');
    });

    test('a GitLab link', () {
      final RepoSource r = ok('https://gitlab.com/group/project');
      expect(r.host, RepoHost.gitlab);
      expect(r.name, 'project');
    });

    test('www and http are accepted', () {
      expect(ok('http://www.github.com/a/b').owner, 'a');
    });
  });

  group('branches', () {
    test('a /tree/ link uses the branch in the URL', () {
      final RepoSource r =
          ok('https://github.com/flutter/samples/tree/develop');
      expect(r.branch, 'develop',
          reason: 'the branch in the link is the one being looked at');
    });

    test('a branch with a slash survives', () {
      final RepoSource r =
          ok('https://github.com/a/b/tree/feature/new-thing');
      expect(r.branch, 'feature/new-thing');
    });

    test('the supplied default is used when the URL names none', () {
      expect(ok('https://github.com/a/b', branch: 'master').branch, 'master');
    });

    test('a query or fragment does not become part of the branch', () {
      expect(ok('https://github.com/a/b/tree/dev?x=1').branch, 'dev');
      expect(ok('https://github.com/a/b/tree/dev#readme').branch, 'dev');
    });
  });

  group('what is refused, with a reason', () {
    test('an SSH link', () {
      expect(bad('git@github.com:flutter/samples.git').message,
          contains('SSH'));
    });

    test('a host that is not supported', () {
      expect(bad('https://bitbucket.org/a/b').message, contains('Import from ZIP'));
    });

    test('a link with no repository name', () {
      expect(bad('https://github.com/flutter').message, contains('owner'));
    });

    test('empty input', () {
      expect(bad('   ').message, contains('Paste'));
    });
  });

  group('archive URLs', () {
    test('GitHub uses codeload', () {
      final Uri url = ok('https://github.com/flutter/samples').archiveUrl;
      expect(url.host, 'codeload.github.com');
      expect(url.path, '/flutter/samples/zip/refs/heads/main');
      expect(url.scheme, 'https');
    });

    test('GitLab uses its archive path', () {
      final Uri url =
          ok('https://gitlab.com/group/project/tree/dev').archiveUrl;
      expect(url.host, 'gitlab.com');
      expect(url.path, contains('/-/archive/dev/'));
    });
  });

  group('folderNameFor', () {
    test('keeps an ordinary name', () {
      expect(folderNameFor(ok('https://github.com/a/my-repo.v2')), 'my-repo.v2');
    });

    test('replaces characters a file system may refuse', () {
      const RepoSource source = RepoSource(
        host: RepoHost.github,
        owner: 'a',
        name: 'we:ird/name',
        branch: 'main',
      );
      expect(folderNameFor(source), 'we_ird_name');
    });
  });
}
