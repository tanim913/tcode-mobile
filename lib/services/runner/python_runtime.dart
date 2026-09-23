/// Builds the page that runs a Python script.
///
/// **This is MicroPython, not CPython**, and the UI says so everywhere it is
/// offered. It is a small implementation of the language: the syntax and the
/// built-ins are real, but the standard library is reduced and there are no
/// third-party packages — no `numpy`, no `pandas`, no `requests`, and no `pip`
/// to add them. Calling it "Python" would set an expectation the app cannot
/// meet on the first `import`.
///
/// The runtime ships as two assets (MIT licensed, ~550KB) rather than being
/// fetched, because running code offline is the whole point.
///
/// Delivery detail that took a spike to settle: the preview page is handed to
/// the WebView through `loadHtmlString`, so it has **no origin** and cannot
/// resolve a sibling `.wasm`. The MicroPython glue ignores `wasmBinary`, but it
/// honours a `url` option that becomes its `locateFile` — so the WebAssembly is
/// passed in as a `data:` URL, which needs no origin, no server and no socket.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show ByteData, rootBundle;

/// Human-readable name. Used wherever the feature is offered or refused, so
/// the app never calls it plain "Python".
const String kPythonRuntimeLabel = 'MicroPython';

/// What the runtime does not have, for the message shown on an import failure.
const String kPythonRuntimeLimits =
    'This is $kPythonRuntimeLabel: a small Python with a reduced standard '
    'library. There is no numpy, pandas or requests, and no pip to install '
    'them.';

class PythonRuntime {
  const PythonRuntime();

  /// Cached across runs: reading and base64-encoding 440KB on every Run would
  /// add a visible pause to a feature whose whole appeal is being instant.
  static Future<_RuntimeAssets>? _assets;

  static Future<_RuntimeAssets> _load() async {
    final String glue =
        await rootBundle.loadString('assets/micropython/micropython.mjs');
    final ByteData wasm =
        await rootBundle.load('assets/micropython/micropython.wasm');
    return _RuntimeAssets(
      glue: glue,
      wasmBase64: base64Encode(wasm.buffer.asUint8List()),
    );
  }

  /// Wraps [source] in a page that runs it and reports what it printed.
  Future<String> harness(String source) async {
    final _RuntimeAssets assets = await (_assets ??= _load());
    return buildPythonPage(
      glue: assets.glue,
      wasmBase64: assets.wasmBase64,
      source: source,
    );
  }
}

class _RuntimeAssets {
  const _RuntimeAssets({required this.glue, required this.wasmBase64});

  final String glue;
  final String wasmBase64;
}

/// Builds the runnable page. Separated from asset loading so it can be tested.
///
/// The source is passed to JavaScript as a JSON string rather than being
/// pasted into the script: Python is full of quotes, backslashes and newlines,
/// and inlining it directly would break the page on the first apostrophe.
String buildPythonPage({
  required String glue,
  required String wasmBase64,
  required String source,
}) {
  final String encoded = jsonEncode(source);

  return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  html, body { background: #101418; color: #e3e6ec;
               font-family: system-ui, sans-serif; margin: 0; padding: 12px; }
  #status { color: #5c6577; font-size: 13px; }
</style>
</head>
<body>
<div id="status">Starting $kPythonRuntimeLabel…</div>
<script type="module">
const status = document.getElementById('status');
function send(level, text) {
  TcodeConsole.postMessage(JSON.stringify({ level: level, text: String(text) }));
}

$glue

try {
  const mp = await loadMicroPython({
    // A data: URL needs no origin, which is what makes this work inside a
    // page loaded from a string.
    url: 'data:application/wasm;base64,$wasmBase64',
    stdout: (line) => send('log', line),
    stderr: (line) => send('error', line),
  });
  status.textContent = '$kPythonRuntimeLabel ready';
  try {
    mp.runPython($encoded);
  } catch (e) {
    // A Python-level error. The traceback already names the line in the user's
    // script, so it is passed through unchanged rather than reformatted.
    const text = (e && e.message) ? e.message : String(e);
    send('error', text);
    if (/No module named|ImportError|ModuleNotFoundError/.test(text)) {
      send('warn', ${jsonEncode(kPythonRuntimeLimits)});
    }
  }
  status.textContent = 'Finished';
} catch (e) {
  status.textContent = 'Could not start';
  send('error', 'The $kPythonRuntimeLabel runtime failed to start: ' +
    ((e && e.stack) ? e.stack : e));
}
</script>
</body>
</html>
''';
}
