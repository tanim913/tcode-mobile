/// Picks the right [ShareService] for the target platform.
///
/// Same seam as `provider_factory.dart`: this is what keeps `dart:io` out of
/// the web build.
library;

export 'share_io.dart' if (dart.library.js_interop) 'share_web.dart';
