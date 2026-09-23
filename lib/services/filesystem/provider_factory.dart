/// Picks the right [FileSystemProvider] implementation for the target platform.
///
/// This conditional export is the seam that keeps `dart:io` out of the web
/// build and `dart:js_interop` out of the mobile build. Nothing else in the app
/// imports a concrete provider — features import this file, and the compiler
/// substitutes the correct implementation.
library;

export 'provider_factory_stub.dart'
    if (dart.library.io) 'io/io_factory.dart'
    if (dart.library.js_interop) 'web/web_factory.dart';
