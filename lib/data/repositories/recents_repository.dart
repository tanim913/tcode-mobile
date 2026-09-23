/// The recent workspaces and files list.
library;

import 'package:pocket_code/data/models/workspace.dart';
import 'package:pocket_code/data/repositories/support_storage.dart';

/// What was open recently, as stored.
class RecentItems {
  const RecentItems({
    this.workspaces = const <RecentWorkspace>[],
    this.files = const <RecentFile>[],
  });

  final List<RecentWorkspace> workspaces;
  final List<RecentFile> files;

  RecentItems copyWith({
    List<RecentWorkspace>? workspaces,
    List<RecentFile>? files,
  }) =>
      RecentItems(
        workspaces: workspaces ?? this.workspaces,
        files: files ?? this.files,
      );

  bool get isEmpty => workspaces.isEmpty && files.isEmpty;
}

class RecentsRepository {
  const RecentsRepository(this._storage);

  static const String fileName = 'recents.json';

  final SupportStorage _storage;

  Future<RecentItems> load() async {
    final Map<String, Object?>? json = await _storage.readJson(fileName);
    if (json == null) {
      return const RecentItems();
    }
    return RecentItems(
      workspaces: _list(json['workspaces'], RecentWorkspace.fromJson),
      files: _list(json['files'], RecentFile.fromJson),
    );
  }

  Future<void> save(RecentItems items) => _storage.writeJson(
        fileName,
        <String, Object?>{
          'version': 1,
          'workspaces':
              items.workspaces.map((RecentWorkspace w) => w.toJson()).toList(),
          'files': items.files.map((RecentFile f) => f.toJson()).toList(),
        },
      );

  /// One malformed entry drops that entry, not the whole list.
  static List<T> _list<T>(
    Object? raw,
    T Function(Map<String, Object?>) fromJson,
  ) {
    if (raw is! List) {
      return <T>[];
    }
    final List<T> out = <T>[];
    for (final Object? item in raw) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      try {
        out.add(fromJson(item));
      } on Object {
        continue;
      }
    }
    return out;
  }
}
