/// Icon and colour for a file or folder, by extension or exact name.
///
/// A registry rather than a switch statement: adding a file type is one map
/// entry. Colours come from the icon's own identity (Dart blue, Rust orange)
/// rather than the theme, because they act as recognisable badges — but they are
/// tinted for contrast against the current surface.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/data/models/file_node.dart';

@immutable
class FileIcon {
  const FileIcon(this.icon, this.color);

  final IconData icon;
  final Color color;
}

abstract final class FileIcons {
  // Shared palette for the badges. Chosen to stay legible on both the dark and
  // light sidebar surfaces.
  static const Color _blue = Color(0xFF4FA3F7);
  static const Color _teal = Color(0xFF3EC9C4);
  static const Color _green = Color(0xFF7BC96F);
  static const Color _yellow = Color(0xFFE3C05C);
  static const Color _orange = Color(0xFFE08B4F);
  static const Color _red = Color(0xFFE0655F);
  static const Color _purple = Color(0xFFB57BE0);
  static const Color _grey = Color(0xFF8A93A1);

  /// Exact file names win over extensions: `Dockerfile` has no extension, and
  /// `pubspec.yaml` deserves its own badge rather than the generic YAML one.
  static const Map<String, FileIcon> _byName = <String, FileIcon>{
    'pubspec.yaml': FileIcon(Icons.flutter_dash, _blue),
    'pubspec.lock': FileIcon(Icons.lock_outline, _grey),
    'package.json': FileIcon(Icons.inventory_2_outlined, _green),
    'package-lock.json': FileIcon(Icons.lock_outline, _grey),
    'Dockerfile': FileIcon(Icons.directions_boat_outlined, _blue),
    'docker-compose.yml': FileIcon(Icons.directions_boat_outlined, _blue),
    'Makefile': FileIcon(Icons.build_outlined, _orange),
    'Cargo.toml': FileIcon(Icons.settings_outlined, _orange),
    'Gemfile': FileIcon(Icons.diamond_outlined, _red),
    '.gitignore': FileIcon(Icons.visibility_off_outlined, _orange),
    '.gitattributes': FileIcon(Icons.tune_outlined, _orange),
    '.editorconfig': FileIcon(Icons.straighten_outlined, _grey),
    '.env': FileIcon(Icons.key_outlined, _yellow),
    'LICENSE': FileIcon(Icons.balance_outlined, _grey),
    'README.md': FileIcon(Icons.menu_book_outlined, _blue),
    'analysis_options.yaml': FileIcon(Icons.rule_outlined, _purple),
  };

  static const Map<String, FileIcon> _byExtension = <String, FileIcon>{
    // Languages
    'dart': FileIcon(Icons.flutter_dash, _blue),
    'js': FileIcon(Icons.javascript_outlined, _yellow),
    'mjs': FileIcon(Icons.javascript_outlined, _yellow),
    'jsx': FileIcon(Icons.javascript_outlined, _yellow),
    'ts': FileIcon(Icons.code_outlined, _blue),
    'tsx': FileIcon(Icons.code_outlined, _blue),
    'py': FileIcon(Icons.terminal_outlined, _blue),
    'java': FileIcon(Icons.coffee_outlined, _red),
    'kt': FileIcon(Icons.hexagon_outlined, _purple),
    'kts': FileIcon(Icons.hexagon_outlined, _purple),
    'swift': FileIcon(Icons.flutter_dash, _orange),
    'c': FileIcon(Icons.data_object, _blue),
    'h': FileIcon(Icons.data_object, _purple),
    'cpp': FileIcon(Icons.data_object, _blue),
    'cc': FileIcon(Icons.data_object, _blue),
    'hpp': FileIcon(Icons.data_object, _purple),
    'cs': FileIcon(Icons.data_object, _green),
    'go': FileIcon(Icons.bolt_outlined, _teal),
    'rs': FileIcon(Icons.settings_outlined, _orange),
    'php': FileIcon(Icons.php_outlined, _purple),
    'rb': FileIcon(Icons.diamond_outlined, _red),
    'lua': FileIcon(Icons.nightlight_outlined, _blue),
    'sh': FileIcon(Icons.terminal_outlined, _green),
    'bash': FileIcon(Icons.terminal_outlined, _green),
    'zsh': FileIcon(Icons.terminal_outlined, _green),
    'sql': FileIcon(Icons.storage_outlined, _orange),

    // Markup and data
    'html': FileIcon(Icons.html_outlined, _orange),
    'htm': FileIcon(Icons.html_outlined, _orange),
    'css': FileIcon(Icons.css_outlined, _blue),
    'scss': FileIcon(Icons.css_outlined, _red),
    'sass': FileIcon(Icons.css_outlined, _red),
    'json': FileIcon(Icons.data_object, _yellow),
    'xml': FileIcon(Icons.code_outlined, _orange),
    'svg': FileIcon(Icons.image_outlined, _yellow),
    'yaml': FileIcon(Icons.list_alt_outlined, _purple),
    'yml': FileIcon(Icons.list_alt_outlined, _purple),
    'toml': FileIcon(Icons.settings_outlined, _orange),
    'ini': FileIcon(Icons.settings_outlined, _grey),
    'md': FileIcon(Icons.notes_outlined, _blue),
    'markdown': FileIcon(Icons.notes_outlined, _blue),
    'txt': FileIcon(Icons.description_outlined, _grey),
    'csv': FileIcon(Icons.table_chart_outlined, _green),

    // Images
    'png': FileIcon(Icons.image_outlined, _teal),
    'jpg': FileIcon(Icons.image_outlined, _teal),
    'jpeg': FileIcon(Icons.image_outlined, _teal),
    'gif': FileIcon(Icons.gif_box_outlined, _teal),
    'webp': FileIcon(Icons.image_outlined, _teal),
    'bmp': FileIcon(Icons.image_outlined, _teal),
    'ico': FileIcon(Icons.image_outlined, _teal),

    // Archives
    'zip': FileIcon(Icons.folder_zip_outlined, _yellow),
    'tar': FileIcon(Icons.folder_zip_outlined, _yellow),
    'gz': FileIcon(Icons.folder_zip_outlined, _yellow),
    'rar': FileIcon(Icons.folder_zip_outlined, _yellow),
    '7z': FileIcon(Icons.folder_zip_outlined, _yellow),

    // Binaries and bundles
    'pdf': FileIcon(Icons.picture_as_pdf_outlined, _red),
    'apk': FileIcon(Icons.android_outlined, _green),
    'jar': FileIcon(Icons.coffee_outlined, _red),
    'so': FileIcon(Icons.memory_outlined, _grey),
    'dll': FileIcon(Icons.memory_outlined, _grey),
    'exe': FileIcon(Icons.memory_outlined, _grey),
    'ttf': FileIcon(Icons.font_download_outlined, _purple),
    'otf': FileIcon(Icons.font_download_outlined, _purple),
    'woff': FileIcon(Icons.font_download_outlined, _purple),
    'woff2': FileIcon(Icons.font_download_outlined, _purple),
  };

  /// Folders whose role is obvious from their name get a distinct icon, which
  /// makes a project tree scannable at a glance.
  static const Map<String, FileIcon> _specialFolders = <String, FileIcon>{
    'lib': FileIcon(Icons.folder_special_outlined, _blue),
    'src': FileIcon(Icons.folder_special_outlined, _blue),
    'test': FileIcon(Icons.science_outlined, _green),
    'tests': FileIcon(Icons.science_outlined, _green),
    'assets': FileIcon(Icons.perm_media_outlined, _purple),
    'images': FileIcon(Icons.perm_media_outlined, _purple),
    'fonts': FileIcon(Icons.font_download_outlined, _purple),
    'android': FileIcon(Icons.android_outlined, _green),
    'ios': FileIcon(Icons.phone_iphone_outlined, _grey),
    'web': FileIcon(Icons.language_outlined, _orange),
    'build': FileIcon(Icons.construction_outlined, _grey),
    'dist': FileIcon(Icons.construction_outlined, _grey),
    'node_modules': FileIcon(Icons.inventory_2_outlined, _grey),
    '.git': FileIcon(Icons.commit_outlined, _orange),
    '.github': FileIcon(Icons.commit_outlined, _grey),
    '.dart_tool': FileIcon(Icons.construction_outlined, _grey),
    'docs': FileIcon(Icons.menu_book_outlined, _blue),
    'bin': FileIcon(Icons.terminal_outlined, _grey),
  };

  static const FileIcon _genericFile = FileIcon(Icons.description_outlined, _grey);
  static const FileIcon _genericFolder = FileIcon(Icons.folder_outlined, _blue);
  static const FileIcon _openFolder = FileIcon(Icons.folder_open_outlined, _blue);

  /// Resolves the icon for [node]. [expanded] only affects generic folders —
  /// a special folder keeps its identifying icon either way.
  static FileIcon forNode(FileSystemNode node, {bool expanded = false}) {
    if (node is FolderNode) {
      final FileIcon? special = _specialFolders[node.name.toLowerCase()];
      if (special != null) {
        return special;
      }
      return expanded ? _openFolder : _genericFolder;
    }
    final FileIcon? byName = _byName[node.name];
    if (byName != null) {
      return byName;
    }
    return _byExtension[node.extension] ?? _genericFile;
  }
}
