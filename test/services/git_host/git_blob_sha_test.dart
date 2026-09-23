/// The local blob id must equal git's exactly, or every file looks changed.
/// Expected values come from `git hash-object --no-filters`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/services/git_host/git_blob_sha.dart';

Uint8List bytes(List<int> b) => Uint8List.fromList(b);

void main() {
  test('empty file', () {
    expect(gitBlobSha(Uint8List(0)), 'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391');
  });

  test('ASCII text with a final newline', () {
    expect(
      gitBlobSha(bytes(utf8.encode('hello\n'))),
      'ce013625030ba8dba906f756967f9e9ca394464a',
    );
  });

  test('CRLF line endings are hashed as they are, not normalised', () {
    expect(
      gitBlobSha(bytes(utf8.encode('a\r\nb\r\n'))),
      'c30dea8a3641ea99b125d04d599d843712292759',
    );
  });

  test('binary bytes, including zero and 0xff', () {
    expect(
      gitBlobSha(bytes(<int>[0, 1, 2, 255])),
      'f971a5e28b6c4cb237ca3c7349e33bb600dbc907',
    );
  });

  test('the length in the header is in bytes, not characters', () {
    expect(
      gitBlobSha(bytes(utf8.encode('héllo'))),
      'e507eb59f765207ed66c258795260c8bedbee89c',
    );
  });
}
