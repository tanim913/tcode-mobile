/// The app's own file clipboard, separate from the system clipboard.
///
/// Cut and Copy in the explorer move *file references*, not text. Putting them
/// on the system clipboard would clobber whatever the user had copied for the
/// editor, and the system clipboard cannot represent "these three entries, from
/// this provider, pending a move". So this is a small app-level holder instead.
///
/// It holds nodes rather than ids so the paste target can show names and icons
/// without re-reading the source folder — the source may have been collapsed,
/// or scrolled out of the tree, by the time the user pastes.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/data/models/file_node.dart';

/// Whether a later paste moves the entries or duplicates them.
enum FileClipboardMode { cut, copy }

/// One entry on the clipboard, tagged with the workspace root it came from so a
/// multi-root workspace can find the provider that owns it.
@immutable
class ClipboardItem {
  const ClipboardItem({required this.rootIndex, required this.node});

  final int rootIndex;
  final FileSystemNode node;

  bool get isFolder => node is FolderNode;

  @override
  bool operator ==(Object other) =>
      other is ClipboardItem &&
      other.rootIndex == rootIndex &&
      other.node.id == node.id;

  @override
  int get hashCode => Object.hash(rootIndex, node.id);
}

@immutable
class FileClipboard {
  const FileClipboard({
    this.mode = FileClipboardMode.copy,
    this.items = const <ClipboardItem>[],
  });

  final FileClipboardMode mode;
  final List<ClipboardItem> items;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
  int get length => items.length;
  bool get isCut => mode == FileClipboardMode.cut;

  /// Label for the chip in the explorer header, e.g. "2 items to paste".
  String get chipLabel {
    final String verb = isCut ? 'to move' : 'to paste';
    if (items.length == 1) {
      return '${items.single.node.name} $verb';
    }
    return '${items.length} items $verb';
  }
}

class FileClipboardNotifier extends Notifier<FileClipboard> {
  @override
  FileClipboard build() => const FileClipboard();

  void cut(Iterable<ClipboardItem> items) => _set(FileClipboardMode.cut, items);

  void copy(Iterable<ClipboardItem> items) =>
      _set(FileClipboardMode.copy, items);

  void clear() => state = const FileClipboard();

  void _set(FileClipboardMode mode, Iterable<ClipboardItem> items) {
    final List<ClipboardItem> list = items.toList(growable: false);
    if (list.isEmpty) {
      clear();
      return;
    }
    state = FileClipboard(mode: mode, items: list);
  }
}

final NotifierProvider<FileClipboardNotifier, FileClipboard>
    fileClipboardProvider =
    NotifierProvider<FileClipboardNotifier, FileClipboard>(
  FileClipboardNotifier.new,
);
