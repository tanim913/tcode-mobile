/// Runs an HTML page or a JavaScript file, and shows what it printed.
///
/// Everything happens inside the system WebView. Nothing is compiled, nothing
/// is sent anywhere, and no socket is opened — the page is handed over as a
/// string, so the app keeps its promise of having no network permission at all.
///
/// JavaScript is run by wrapping it in a harness page that forwards `console`
/// and uncaught errors to Dart over a JS channel. That is also what makes an
/// HTML page's own `console.log` visible, since both go through the same host.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// One line of output.
class ConsoleLine {
  const ConsoleLine({required this.level, required this.text});

  /// `log`, `warn`, `error`, or `info`.
  final String level;
  final String text;

  bool get isError => level == 'error';
  bool get isWarning => level == 'warn';
}

/// Wraps [source] in a page that runs it and reports what it printed.
///
/// The overrides are installed *before* the user's code so an error thrown on
/// its first line is still captured. `JSON.stringify` is used for objects
/// because the default string conversion turns every one of them into
/// "[object Object]", which is useless in a log.
String javascriptHarness(String source) {
  // The prelude is measured rather than guessed, so a reported line number
  // matches the user's file. Without this the WebView reports the line inside
  // this wrapper — "line 38" for an error on line 4 — which sends people
  // hunting through a file only ten lines long.
  const String prelude = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  /* The app is dark; an unstyled page is a white slab in the middle of it. */
  html, body { background: #101418; color: #e3e6ec;
               font-family: system-ui, sans-serif; margin: 0; padding: 12px; }
</style>
</head>
<body>
<script>
(function () {
  function format(value) {
    if (typeof value === 'string') return value;
    if (value instanceof Error) return value.stack || (value.name + ': ' + value.message);
    try { return JSON.stringify(value); } catch (e) { return String(value); }
  }
  function send(level, args) {
    TcodeConsole.postMessage(JSON.stringify({
      level: level,
      text: Array.prototype.map.call(args, format).join(' ')
    }));
  }
  window.__tcodeSend = send;
  ['log', 'info', 'warn', 'error', 'debug'].forEach(function (level) {
    var original = console[level];
    console[level] = function () {
      send(level === 'debug' ? 'log' : level, arguments);
      if (original) original.apply(console, arguments);
    };
  });
  window.addEventListener('unhandledrejection', function (event) {
    send('error', ['Unhandled promise rejection: ' + format(event.reason)]);
  });
})();
</script>
''';

  // `onerror` reports a line in the whole document, so everything this
  // wrapper adds has to be subtracted. The offset is measured from the real
  // document rather than counted by hand — the header is built once with a
  // placeholder to count its lines, then again with the true value, which is
  // safe because the placeholder occupies exactly one line either way.
  String header(int offset) {
    return (StringBuffer(prelude)
          ..writeln('<script>')
          ..writeln('window.onerror = function (message, src, line, column) {')
          ..writeln('  window.__tcodeSend("error", [message + "  (line " + '
              '(line - $offset) + ":" + column + ")"]);')
          ..writeln('  return true;')
          ..writeln('};')
          ..writeln('</script>')
          ..writeln('<script>'))
        .toString();
  }

  final int offset = '\n'.allMatches(header(0)).length;

  final StringBuffer out = StringBuffer(header(offset))
    // A literal `</script>` inside a string would end the block early.
    ..writeln(source.replaceAll('</script>', r'<\/script>'))
    ..writeln('</script>')
    ..writeln('</body>')
    ..writeln('</html>');
  return out.toString();
}

/// Injected into a previewed HTML page so its own logging is visible too.
const String kConsoleBridge = '''
<script>
(function () {
  if (window.__tcodeBridge) return;
  window.__tcodeBridge = true;
  function format(v) {
    if (typeof v === 'string') return v;
    if (v instanceof Error) return v.stack || (v.name + ': ' + v.message);
    try { return JSON.stringify(v); } catch (e) { return String(v); }
  }
  function send(level, args) {
    TcodeConsole.postMessage(JSON.stringify({
      level: level,
      text: Array.prototype.map.call(args, format).join(' ')
    }));
  }
  ['log', 'info', 'warn', 'error', 'debug'].forEach(function (level) {
    var original = console[level];
    console[level] = function () {
      send(level === 'debug' ? 'log' : level, arguments);
      if (original) original.apply(console, arguments);
    };
  });
  window.onerror = function (m, s, l, c) {
    send('error', [m + '  (line ' + l + ':' + c + ')']);
    return true;
  };
})();
</script>
''';

/// Puts the console bridge into [html], as early as the document allows.
///
/// Before `</head>` when there is one, so a script in the body is already
/// covered; otherwise prepended, because a page with no head still logs.
String withConsoleBridge(String html) {
  final int head = html.toLowerCase().indexOf('</head>');
  if (head >= 0) {
    return html.substring(0, head) + kConsoleBridge + html.substring(head);
  }
  return kConsoleBridge + html;
}

class RunPane extends StatefulWidget {
  const RunPane({
    required this.html,
    required this.title,
    required this.notes,
    required this.onClose,
    required this.onRerun,
    super.key,
  });

  /// The complete page to load — already bundled and bridged.
  final String html;

  final String title;

  /// Anything the bundler could not include, shown above the output.
  final List<String> notes;

  final VoidCallback onClose;
  final VoidCallback onRerun;

  @override
  State<RunPane> createState() => _RunPaneState();
}

class _RunPaneState extends State<RunPane> {
  late final WebViewController _controller;
  final List<ConsoleLine> _lines = <ConsoleLine>[];
  bool _consoleOpen = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('TcodeConsole', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          // The app has no network permission, so a navigation to http(s)
          // would fail with an opaque WebView error page. Blocking it and
          // saying so is the honest outcome.
          onNavigationRequest: (NavigationRequest request) {
            if (request.url.startsWith('http')) {
              setState(() {
                _lines.add(
                  ConsoleLine(
                    level: 'warn',
                    text: 'Blocked navigation to ${request.url} — '
                        'a preview never loads from the internet.',
                  ),
                );
              });
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(widget.html);
  }

  @override
  void didUpdateWidget(RunPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) {
      _lines.clear();
      _controller.loadHtmlString(widget.html);
    }
  }

  void _onMessage(JavaScriptMessage message) {
    String level = 'log';
    String text = message.message;
    try {
      final Object? decoded = jsonDecode(message.message);
      if (decoded is Map<String, Object?>) {
        level = decoded['level'] as String? ?? 'log';
        text = decoded['text'] as String? ?? '';
      }
    } on FormatException {
      // A message that is not our JSON is still output; dropping it would
      // silently lose whatever the page was trying to say.
    }
    if (mounted) {
      setState(() => _lines.add(ConsoleLine(level: level, text: text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    final int errors = _lines.where((ConsoleLine l) => l.isError).length;

    return Column(
      children: <Widget>[
        _RunHeader(
          title: widget.title,
          errors: errors,
          onRerun: widget.onRerun,
          onClose: widget.onClose,
          tokens: tokens,
        ),
        if (widget.notes.isNotEmpty) _Notes(notes: widget.notes, tokens: tokens),
        Expanded(
          flex: _consoleOpen && _lines.isNotEmpty ? 3 : 1,
          child: WebViewWidget(controller: _controller),
        ),
        if (_lines.isNotEmpty)
          _Console(
            lines: _lines,
            open: _consoleOpen,
            tokens: tokens,
            onToggle: () => setState(() => _consoleOpen = !_consoleOpen),
            onClear: () => setState(_lines.clear),
          ),
      ],
    );
  }
}

class _RunHeader extends StatelessWidget {
  const _RunHeader({
    required this.title,
    required this.errors,
    required this.onRerun,
    required this.onClose,
    required this.tokens,
  });

  final String title;
  final int errors;
  final VoidCallback onRerun;
  final VoidCallback onClose;
  final AppColorTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSizes.toolbarHeight,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: tokens.sidebar,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.play_arrow, size: 16, color: tokens.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (errors > 0) ...<Widget>[
            Text(
              errors == 1 ? '1 error' : '$errors errors',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: tokens.danger),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            tooltip: 'Run again',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: onRerun,
          ),
          IconButton(
            tooltip: 'Close preview',
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _Notes extends StatelessWidget {
  const _Notes({required this.notes, required this.tokens});

  final List<String> notes;
  final AppColorTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      color: tokens.warning.withValues(alpha: 0.12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final String note in notes)
            Text(
              note,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.warning),
            ),
        ],
      ),
    );
  }
}

class _Console extends StatelessWidget {
  const _Console({
    required this.lines,
    required this.open,
    required this.tokens,
    required this.onToggle,
    required this.onClear,
  });

  final List<ConsoleLine> lines;
  final bool open;
  final AppColorTokens tokens;
  final VoidCallback onToggle;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          InkWell(
            onTap: onToggle,
            child: SizedBox(
              height: AppSizes.minTouchTarget,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 12),
                  Icon(
                    open ? Icons.expand_more : Icons.expand_less,
                    size: 16,
                    color: tokens.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      lines.length == 1
                          ? 'Console · 1 line'
                          : 'Console · ${lines.length} lines',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                  TextButton(onPressed: onClear, child: const Text('Clear')),
                ],
              ),
            ),
          ),
          if (open)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                itemCount: lines.length,
                itemBuilder: (BuildContext context, int i) {
                  final ConsoleLine line = lines[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: SelectableText(
                      line.text,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'JetBrains Mono',
                        color: line.isError
                            ? tokens.danger
                            : line.isWarning
                            ? tokens.warning
                            : tokens.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
