/// Keeps the word index for one tab up to date.
///
/// **Why this is not on an isolate.** The obvious move is to hand the buffer to
/// `compute`, and it is the wrong one: the whole string would be copied on every
/// rebuild, which for a large file costs more than the scan itself, and
/// `dart:isolate` does not exist on web. The app already has one answer for
/// exactly this shape of problem — `io_bulk_worker.dart` yields to the event
/// loop every 32 entries, and `WebFileSystemProvider` mirrors that cadence — so
/// this does the same: the walk is sliced across event-loop turns and abandoned
/// the moment a newer one starts. One code path, and no frame sees more than a
/// fraction of the work.
library;

import 'dart:async';

import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/features/editor/application/word_index.dart';
import 'package:re_editor/re_editor.dart';

/// Lines scanned before yielding. Mirrors `io_bulk_worker`'s `_yieldEvery`.
const int _linesPerSlice = 512;

/// How long typing must pause before the index is rebuilt.
const Duration _rebuildDebounce = Duration(milliseconds: 300);

class AutocompleteController {
  AutocompleteController({
    required this.controller,
    required this.maxFileBytes,
  }) {
    controller.addListener(_onChanged);
    // Never synchronous: the controller is created from `initState` and
    // `didUpdateWidget`, both of which run inside a build phase, and touching
    // the editor's controller there can mark its listeners dirty mid-build.
    scheduleMicrotask(_rebuild);
  }

  final CodeLineEditingController controller;

  /// Above this the buffer is not indexed. Language keywords still work, so
  /// completion degrades rather than vanishing — and the user can already see
  /// why in the status bar, which says the file is large.
  final int maxFileBytes;

  Set<String> _words = <String>{};
  Timer? _debounce;
  int _generation = 0;
  bool _disposed = false;

  /// The current index. Safe to call on every keystroke: it never rebuilds.
  Set<String> get words => _words;

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(_rebuildDebounce, () => unawaited(_rebuild()));
  }

  Future<void> _rebuild() async {
    final int generation = ++_generation;
    final int lineCount = controller.lineCount;

    // A cheap proxy for the byte size: lines are rarely longer than this on
    // average, and reading `controller.text` to measure it exactly would copy
    // the whole buffer, which is the cost being avoided.
    if (lineCount * 80 > maxFileBytes) {
      _words = <String>{};
      return;
    }

    final Set<String> next = <String>{};
    for (int i = 0; i < lineCount; i++) {
      if (_disposed || generation != _generation) {
        return;
      }
      collectWordsInto(
        controller.codeLines[i].text,
        next,
        minLength: AppLimits.completionMinWordLength,
      );
      if (next.length >= AppLimits.completionMaxIndexedWords) {
        break;
      }
      if (i % _linesPerSlice == _linesPerSlice - 1) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (_disposed || generation != _generation) {
      return;
    }
    // Swapped in whole, so a keystroke never sees a half-built index.
    _words = next;
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    controller.removeListener(_onChanged);
  }
}
