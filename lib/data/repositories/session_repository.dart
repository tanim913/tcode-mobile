/// Persists the workspace session and hot-exit backups.
///
/// Two separate concerns, deliberately stored separately:
///
/// * **Session** — which roots, tabs and positions were open. Small, written
///   often, kept as one JSON file.
/// * **Hot-exit backups** — the actual text of unsaved buffers. Potentially
///   large, written only when the app is paused, one file per dirty tab.
///
/// Keeping them apart means the frequent write stays cheap, and a corrupt
/// backup can never take the session index down with it.
library;

import 'dart:convert';

import 'package:pocket_code/core/constants/app_info.dart';
import 'package:pocket_code/core/utils/stable_hash.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/data/models/text_format.dart';
import 'package:pocket_code/data/models/workspace.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';

/// Everything needed to put the user back where they were.
class SavedSession {
  const SavedSession({
    required this.roots,
    required this.tabs,
    required this.activeTabIndex,
    this.workspaceName,
    this.expandedFolders = const <String>[],
    this.sidebarOpen = true,
  });

  final List<WorkspaceRoot> roots;
  final List<SavedTab> tabs;
  final int activeTabIndex;
  final String? workspaceName;
  final List<String> expandedFolders;
  final bool sidebarOpen;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'roots': roots.map((WorkspaceRoot r) => r.toJson()).toList(),
        'tabs': tabs.map((SavedTab t) => t.toJson()).toList(),
        'activeTabIndex': activeTabIndex,
        'workspaceName': workspaceName,
        'expandedFolders': expandedFolders,
        'sidebarOpen': sidebarOpen,
      };

  factory SavedSession.fromJson(Map<String, Object?> json) {
    final Object? roots = json['roots'];
    final Object? tabs = json['tabs'];
    return SavedSession(
      roots: roots is List
          ? roots
              .whereType<Map<String, Object?>>()
              .map(WorkspaceRoot.fromJson)
              .toList()
          : <WorkspaceRoot>[],
      tabs: tabs is List
          ? tabs
              .whereType<Map<String, Object?>>()
              .map(SavedTab.fromJson)
              .toList()
          : <SavedTab>[],
      activeTabIndex: json['activeTabIndex'] is int
          ? json['activeTabIndex']! as int
          : -1,
      workspaceName:
          json['workspaceName'] is String ? json['workspaceName']! as String : null,
      expandedFolders: json['expandedFolders'] is List
          ? (json['expandedFolders']! as List).whereType<String>().toList()
          : const <String>[],
      sidebarOpen: json['sidebarOpen'] is bool ? json['sidebarOpen']! as bool : true,
    );
  }
}

class SavedTab {
  const SavedTab({
    required this.rootIndex,
    required this.fileId,
    required this.name,
    required this.editorState,
    this.isPreview = false,
    this.wasDirty = false,
  });

  final int rootIndex;
  final String fileId;
  final String name;
  final EditorState editorState;
  final bool isPreview;

  /// Whether a hot-exit backup should exist for this tab.
  final bool wasDirty;

  Map<String, Object?> toJson() => <String, Object?>{
        'rootIndex': rootIndex,
        'fileId': fileId,
        'name': name,
        'isPreview': isPreview,
        'wasDirty': wasDirty,
        'editorState': editorState.toJson(),
      };

  factory SavedTab.fromJson(Map<String, Object?> json) {
    final Object? editorState = json['editorState'];
    return SavedTab(
      rootIndex: json['rootIndex'] is int ? json['rootIndex']! as int : 0,
      fileId: json['fileId'] is String ? json['fileId']! as String : '',
      name: json['name'] is String ? json['name']! as String : '',
      editorState: editorState is Map<String, Object?>
          ? EditorState.fromJson(editorState)
          : const EditorState(),
      isPreview: json['isPreview'] is bool ? json['isPreview']! as bool : false,
      wasDirty: json['wasDirty'] is bool ? json['wasDirty']! as bool : false,
    );
  }
}

/// Reads and writes session state through a [FileSystemProvider] rooted at the
/// app's private support directory.
///
/// Going through the provider rather than `dart:io` is what lets this work
/// unchanged on web, where the same data lives in the Origin Private File
/// System.
class SessionRepository {
  const SessionRepository._(this._provider, this._supportRootId);

  factory SessionRepository({
    required FileSystemProvider provider,
    required String supportRootId,
  }) =>
      SessionRepository._(provider, supportRootId);

  static const String _sessionFile = 'session.json';

  final FileSystemProvider _provider;
  final String _supportRootId;

  String get _sessionId => _provider.childId(_supportRootId, _sessionFile);

  String get _backupsFolderId =>
      _provider.childId(_supportRootId, AppInfo.backupsFolderName);

  Future<void> saveSession(SavedSession session) async {
    await _writeJson(_sessionId, session.toJson());
  }

  /// Returns null when there is no session, or when the file is unreadable.
  ///
  /// A corrupt session must never stop the app from starting — the worst
  /// acceptable outcome is landing on the welcome screen.
  Future<SavedSession?> loadSession() async {
    try {
      if (!await _provider.exists(_sessionId)) {
        return null;
      }
      final TextFileContents contents = await _provider.readText(_sessionId);
      final Object? decoded = jsonDecode(contents.text);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      return SavedSession.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  Future<void> clearSession() async {
    try {
      if (await _provider.exists(_sessionId)) {
        await _provider.delete(_sessionId);
      }
    } on Object {
      // Nothing useful to do; a stale session is harmless.
    }
  }

  // --- Hot exit -------------------------------------------------------------

  /// Backs up one unsaved buffer.
  ///
  /// The file name is derived from a hash of the tab key rather than the path,
  /// because a path contains separators and may be a URI.
  Future<void> writeBackup(String tabKey, String text) async {
    final String id = _backupId(tabKey);
    await _ensureBackupsFolder();
    await _provider.writeText(id, text, const TextFormat());
  }

  Future<String?> readBackup(String tabKey) async {
    try {
      final String id = _backupId(tabKey);
      if (!await _provider.exists(id)) {
        return null;
      }
      return (await _provider.readText(id)).text;
    } on Object {
      return null;
    }
  }

  Future<void> deleteBackup(String tabKey) async {
    try {
      final String id = _backupId(tabKey);
      if (await _provider.exists(id)) {
        await _provider.delete(id);
      }
    } on Object {
      // A leftover backup is cleaned up on the next launch.
    }
  }

  /// Removes every backup. Called once the session has been fully restored.
  Future<void> purgeBackups() async {
    try {
      if (!await _provider.exists(_backupsFolderId)) {
        return;
      }
      for (final FileSystemNode node in await _provider.list(_backupsFolderId)) {
        await _provider.delete(node.id);
      }
    } on Object {
      // Best effort.
    }
  }

  String _backupId(String tabKey) =>
      _provider.childId(_backupsFolderId, '${stableHash(tabKey)}.bak');

  Future<void> _ensureBackupsFolder() async {
    if (!await _provider.exists(_backupsFolderId)) {
      await _provider.createFolder(
        _supportRootId,
        AppInfo.backupsFolderName,
      );
    }
  }

  Future<void> _writeJson(String id, Map<String, Object?> json) async {
    if (!await _provider.exists(id)) {
      await _provider.createFile(
        _provider.parentOf(id) ?? _supportRootId,
        _provider.nameOf(id),
      );
    }
    await _provider.writeText(
      id,
      const JsonEncoder.withIndent('  ').convert(json),
      const TextFormat(),
    );
  }

}
