/// Picks the client for a host.
library;

import 'package:pocket_code/services/git_host/git_host_client.dart';
import 'package:pocket_code/services/git_host/github_client.dart';
import 'package:pocket_code/services/git_host/gitlab_client.dart';
import 'package:pocket_code/services/git_host/http_transport.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

GitHostClient clientFor(
  RepoHost host, {
  required HttpTransport transport,
  String? token,
  Pause? pause,
}) =>
    switch (host) {
      RepoHost.github =>
        GitHubClient(transport: transport, token: token, pause: pause),
      RepoHost.gitlab =>
        GitLabClient(transport: transport, token: token, pause: pause),
    };
