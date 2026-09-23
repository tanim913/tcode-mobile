/// Picks the right [RepoDownload] for the target platform.
///
/// Same seam as `provider_factory.dart` and `share_factory.dart`: it is what
/// keeps `dart:io` out of the web build.
library;

export 'repo_download_io.dart'
    if (dart.library.js_interop) 'repo_download_web.dart';
