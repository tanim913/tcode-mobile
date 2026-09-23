/// One recorded version of a file, and the index of them all.
library;

import 'package:flutter/foundation.dart';

@immutable
class FileVersion {
  const FileVersion({
    required this.stamp,
    required this.savedAt,
    required this.byteLength,
    required this.contentHash,
  });

  /// Microseconds since the epoch, and the snapshot's file name.
  ///
  /// Microseconds rather than milliseconds for the same reason the trash uses
  /// them: `saveAll()` can write several tabs inside one millisecond.
  final int stamp;

  /// When this content stopped being current.
  final DateTime savedAt;

  final int byteLength;

  /// Used to skip recording content identical to the newest version, without
  /// reading the snapshot back off disk.
  final String contentHash;

  String get fileName => '$stamp.snap';

  Map<String, Object?> toJson() => <String, Object?>{
        'stamp': stamp,
        'savedAt': savedAt.toIso8601String(),
        'bytes': byteLength,
        'hash': contentHash,
      };

  static FileVersion? fromJson(Map<String, Object?> json) {
    final Object? stamp = json['stamp'];
    if (stamp is! int) {
      return null;
    }
    return FileVersion(
      stamp: stamp,
      savedAt: DateTime.tryParse(
            json['savedAt'] is String ? json['savedAt']! as String : '',
          ) ??
          DateTime.fromMicrosecondsSinceEpoch(stamp),
      byteLength: json['bytes'] is int ? json['bytes']! as int : 0,
      contentHash: json['hash'] is String ? json['hash']! as String : '',
    );
  }
}

/// What a history folder knows about the file it belongs to.
@immutable
class FileHistoryMeta {
  const FileHistoryMeta({
    required this.key,
    required this.name,
    required this.displayPath,
    this.versions = const <FileVersion>[],
  });

  /// The full key this folder was created for.
  ///
  /// Stored so a hash collision is **detected** rather than silently mixing two
  /// files' history together: a folder whose key does not match is not ours.
  final String key;

  final String name;
  final String displayPath;

  /// Newest first.
  final List<FileVersion> versions;

  FileVersion? get newest => versions.isEmpty ? null : versions.first;

  int get totalBytes =>
      versions.fold(0, (int sum, FileVersion v) => sum + v.byteLength);

  FileHistoryMeta copyWith({
    String? key,
    String? name,
    String? displayPath,
    List<FileVersion>? versions,
  }) =>
      FileHistoryMeta(
        key: key ?? this.key,
        name: name ?? this.name,
        displayPath: displayPath ?? this.displayPath,
        versions: versions ?? this.versions,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'key': key,
        'name': name,
        'displayPath': displayPath,
        'versions': versions.map((FileVersion v) => v.toJson()).toList(),
      };

  static FileHistoryMeta? fromJson(Map<String, Object?> json) {
    final Object? key = json['key'];
    if (key is! String || key.isEmpty) {
      return null;
    }
    final Object? versions = json['versions'];
    return FileHistoryMeta(
      key: key,
      name: json['name'] is String ? json['name']! as String : '',
      displayPath:
          json['displayPath'] is String ? json['displayPath']! as String : '',
      versions: <FileVersion>[
        if (versions is List)
          for (final Object? item in versions)
            if (item is Map<String, Object?>)
              if (FileVersion.fromJson(item) case final FileVersion v) v,
      ],
    );
  }
}
