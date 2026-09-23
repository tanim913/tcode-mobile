/// Immutable snapshot of every open tab.
library;

import 'package:flutter/foundation.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/open_tab.dart';

@immutable
class TabsState {
  const TabsState({
    this.tabs = const <OpenTab>[],
    this.activeIndex = -1,
    this.isLoading = false,
    this.error,
  });

  final List<OpenTab> tabs;

  /// -1 when nothing is open.
  final int activeIndex;

  final bool isLoading;

  /// A failure that stopped a file from opening. Cleared on the next success.
  final AppFailure? error;

  OpenTab? get active =>
      activeIndex >= 0 && activeIndex < tabs.length ? tabs[activeIndex] : null;

  bool get hasTabs => tabs.isNotEmpty;

  bool get anyDirty => tabs.any((OpenTab t) => t.isDirty);

  int indexOfKey(String key) =>
      tabs.indexWhere((OpenTab t) => t.key == key);

  TabsState copyWith({
    List<OpenTab>? tabs,
    int? activeIndex,
    bool? isLoading,
    AppFailure? error,
    bool clearError = false,
  }) {
    return TabsState(
      tabs: tabs ?? this.tabs,
      activeIndex: activeIndex ?? this.activeIndex,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
