/// The document currently being previewed or run.
///
/// One session at a time: a phone has no room for two previews, and a second
/// WebView is a second copy of a browser engine in memory.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

class RunSession {
  const RunSession({
    required this.tabKey,
    required this.title,
    required this.html,
    required this.notes,
  });

  /// Which tab this output belongs to, so switching files closes it rather
  /// than leaving a preview of something you are no longer looking at.
  final String tabKey;

  final String title;

  /// The complete page, already bundled and bridged.
  final String html;

  final List<String> notes;
}

class RunSessionController extends Notifier<RunSession?> {
  @override
  RunSession? build() => null;

  void start(RunSession session) => state = session;

  void stop() => state = null;
}

final NotifierProvider<RunSessionController, RunSession?> runSessionProvider =
    NotifierProvider<RunSessionController, RunSession?>(
  RunSessionController.new,
);
