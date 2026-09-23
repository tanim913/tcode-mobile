/// Workspace models.
///
/// A workspace is one or more root folders opened together. The file format is
/// deliberately compatible with VS Code's `.code-workspace`: a `folders` array
/// of `{ "path": ... }` objects plus an optional `settings` object. A workspace
/// file written here opens in VS Code and vice versa.
library;

import 'package:flutter/foundation.dart';

/// One root folder inside a workspace.
///
/// [providerScheme] and [rootId] together are what reopen it later. The id is
/// opaque — an absolute path, a `content://` URI, or a browser handle key —
/// and only the provider that issued it knows how to read it.
@immutable
class WorkspaceRoot {
  const WorkspaceRoot({
    required this.providerScheme,
    required this.rootId,
    required this.name,
    this.displayPath,
    this.available = true,
  });

  /// Matches [FileSystemProvider.schemeId]: `io`, `saf`, or `web-fsa`.
  final String providerScheme;

  final String rootId;

  /// Shown as the section header in the explorer.
  final String name;

  /// Human-readable location for the Properties dialog and recent list.
  final String? displayPath;

  /// False when the folder was deleted, the storage unmounted, or the
  /// permission revoked. Such a root is shown with Locate and Remove actions
  /// rather than failing silently.
  final bool available;

  WorkspaceRoot copyWith({String? name, String? rootId, bool? available}) {
    return WorkspaceRoot(
      providerScheme: providerScheme,
      rootId: rootId ?? this.rootId,
      name: name ?? this.name,
      displayPath: displayPath,
      available: available ?? this.available,
    );
  }

  /// VS Code stores a bare path string. We keep the extra fields alongside it
  /// under our own keys, which VS Code ignores.
  Map<String, Object?> toJson() => <String, Object?>{
        'path': rootId,
        if (displayPath != null) 'name': name,
        'pocketProvider': providerScheme,
      };

  factory WorkspaceRoot.fromJson(Map<String, Object?> json) {
    final String path = json['path'] is String ? json['path']! as String : '';
    return WorkspaceRoot(
      // Default to `io`: a workspace file written by VS Code has plain paths.
      providerScheme: json['pocketProvider'] is String
          ? json['pocketProvider']! as String
          : 'io',
      rootId: path,
      name: json['name'] is String
          ? json['name']! as String
          : _lastSegment(path),
      displayPath: path,
    );
  }

  static String _lastSegment(String path) {
    final String trimmed =
        path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final int slash = trimmed.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? trimmed : trimmed.substring(slash + 1);
  }

  @override
  bool operator ==(Object other) =>
      other is WorkspaceRoot &&
      other.providerScheme == providerScheme &&
      other.rootId == rootId;

  @override
  int get hashCode => Object.hash(providerScheme, rootId);
}

@immutable
class Workspace {
  const Workspace({
    required this.roots,
    this.name,
    this.filePath,
    this.settingsOverrides = const <String, Object?>{},
  });

  /// A single folder opened directly, with no workspace file.
  factory Workspace.singleRoot(WorkspaceRoot root) =>
      Workspace(roots: <WorkspaceRoot>[root], name: root.name);

  final List<WorkspaceRoot> roots;

  /// Explicit name, otherwise derived from the first root.
  final String? name;

  /// Where the `.code-workspace` file lives, or null for an unsaved workspace.
  final String? filePath;

  /// Per-workspace settings that override the global ones. Stored as raw JSON
  /// so an unknown key written by another version survives a round trip.
  final Map<String, Object?> settingsOverrides;

  bool get isMultiRoot => roots.length > 1;

  String get displayName {
    if (name != null && name!.isNotEmpty) {
      return name!;
    }
    if (roots.isEmpty) {
      return 'Untitled workspace';
    }
    return roots.first.name;
  }

  Workspace copyWith({
    List<WorkspaceRoot>? roots,
    String? name,
    String? filePath,
    Map<String, Object?>? settingsOverrides,
  }) {
    return Workspace(
      roots: roots ?? this.roots,
      name: name ?? this.name,
      filePath: filePath ?? this.filePath,
      settingsOverrides: settingsOverrides ?? this.settingsOverrides,
    );
  }

  /// VS Code-compatible `.code-workspace` contents.
  Map<String, Object?> toJson() => <String, Object?>{
        'folders': roots.map((WorkspaceRoot r) => r.toJson()).toList(),
        if (settingsOverrides.isNotEmpty) 'settings': settingsOverrides,
      };

  factory Workspace.fromJson(
    Map<String, Object?> json, {
    String? filePath,
    String? name,
  }) {
    final Object? folders = json['folders'];
    final List<WorkspaceRoot> roots = folders is List
        ? folders
            .whereType<Map<String, Object?>>()
            .map(WorkspaceRoot.fromJson)
            .toList()
        : <WorkspaceRoot>[];
    final Object? settings = json['settings'];
    return Workspace(
      roots: roots,
      name: name,
      filePath: filePath,
      settingsOverrides:
          settings is Map<String, Object?> ? settings : const <String, Object?>{},
    );
  }
}

/// An entry in the "recent workspaces" list.
@immutable
class RecentWorkspace {
  const RecentWorkspace({
    required this.name,
    required this.roots,
    required this.lastOpened,
    this.filePath,
    this.available = true,
  });

  final String name;
  final List<WorkspaceRoot> roots;
  final DateTime lastOpened;
  final String? filePath;

  /// Checked lazily when the recent list is shown, so a missing folder appears
  /// as unavailable with Locate and Remove rather than erroring on open.
  final bool available;

  /// Identity for de-duplication: the workspace file if there is one, else the
  /// set of root ids.
  String get key =>
      filePath ?? roots.map((WorkspaceRoot r) => r.rootId).join('|');

  RecentWorkspace copyWith({bool? available, DateTime? lastOpened}) {
    return RecentWorkspace(
      name: name,
      roots: roots,
      lastOpened: lastOpened ?? this.lastOpened,
      filePath: filePath,
      available: available ?? this.available,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'roots': roots.map((WorkspaceRoot r) => r.toJson()).toList(),
        'lastOpened': lastOpened.toIso8601String(),
        if (filePath != null) 'filePath': filePath,
      };

  factory RecentWorkspace.fromJson(Map<String, Object?> json) {
    final Object? roots = json['roots'];
    return RecentWorkspace(
      name: json['name'] is String ? json['name']! as String : 'Workspace',
      roots: roots is List
          ? roots
              .whereType<Map<String, Object?>>()
              .map(WorkspaceRoot.fromJson)
              .toList()
          : <WorkspaceRoot>[],
      lastOpened: DateTime.tryParse(
            json['lastOpened'] is String ? json['lastOpened']! as String : '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      filePath: json['filePath'] is String ? json['filePath']! as String : null,
    );
  }
}

/// An entry in the "recent files" list.
@immutable
class RecentFile {
  const RecentFile({
    required this.providerScheme,
    required this.fileId,
    required this.name,
    required this.lastOpened,
    this.displayPath,
    this.available = true,
  });

  final String providerScheme;
  final String fileId;
  final String name;
  final DateTime lastOpened;
  final String? displayPath;
  final bool available;

  RecentFile copyWith({bool? available}) => RecentFile(
        providerScheme: providerScheme,
        fileId: fileId,
        name: name,
        lastOpened: lastOpened,
        displayPath: displayPath,
        available: available ?? this.available,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'provider': providerScheme,
        'id': fileId,
        'name': name,
        'lastOpened': lastOpened.toIso8601String(),
        if (displayPath != null) 'displayPath': displayPath,
      };

  factory RecentFile.fromJson(Map<String, Object?> json) => RecentFile(
        providerScheme:
            json['provider'] is String ? json['provider']! as String : 'io',
        fileId: json['id'] is String ? json['id']! as String : '',
        name: json['name'] is String ? json['name']! as String : '',
        lastOpened: DateTime.tryParse(
              json['lastOpened'] is String ? json['lastOpened']! as String : '',
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        displayPath: json['displayPath'] is String
            ? json['displayPath']! as String
            : null,
      );
}
