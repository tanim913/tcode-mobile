/// Picks the right [HttpTransport] for the target platform. Same seam as
/// `repo_download_factory.dart`.
library;

export 'http_transport_io.dart'
    if (dart.library.js_interop) 'http_transport_web.dart';
