/// Git's own id for a file's contents, computed locally.
///
/// A git blob id is `sha1("blob <byte length>\0" + bytes)`. The host's tree
/// listing gives that id for every file at the downloaded commit, so hashing
/// the local copy is enough to know whether a file changed — **no baseline
/// copy of the repository has to be kept**.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

String gitBlobSha(Uint8List bytes) {
  // Chunked, so a large file is hashed without first being copied behind its
  // header.
  final _DigestSink result = _DigestSink();
  sha1.startChunkedConversion(result)
    ..add(ascii.encode('blob ${bytes.length}\u0000'))
    ..add(bytes)
    ..close();
  return result.digest.toString();
}

class _DigestSink implements Sink<Digest> {
  late Digest digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
