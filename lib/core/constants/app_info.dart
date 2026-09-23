/// Identity of the application.
///
/// The display name is defined once, here, so renaming the app is a one-line
/// change rather than a search-and-replace across the tree. The Dart package is
/// still called `pocket_code` internally; that name is invisible to users and
/// renaming it would touch every import for no benefit.
library;

abstract final class AppInfo {
  /// Shown in the top bar, the welcome screen and the Android task switcher.
  static const String name = 'Tcode Mobile';

  /// Used in file headers, the about screen and the workspace file format.
  static const String version = '1.0.0';

  /// Extension for multi-root workspace files. Deliberately the same as
  /// VS Code's so the files are interchangeable.
  static const String workspaceFileExtension = '.code-workspace';

  /// Folder created inside app-private storage that holds user projects.
  static const String projectsFolderName = 'Projects';

  /// App-private folder that deleted items are moved to, so a delete can be
  /// undone. Purged after the undo window and on next launch.
  static const String trashFolderName = '.trash';

  /// App-private folder holding unsaved-buffer backups written when the app is
  /// paused, so nothing is lost if the OS kills the process.
  static const String backupsFolderName = '.backups';
}
