/// Turns an HTML file plus its neighbours into one self-contained page.
///
/// The preview loads through `loadHtmlString`, which gives the page no origin
/// and therefore no way to resolve `style.css` next to it. Rather than run a
/// local server — binding a socket needs the `INTERNET` permission this app
/// deliberately does not have — the sibling files are read through the
/// [FileSystemProvider] and inlined before the page is handed over.
///
/// That also means the preview works identically on a SAF folder and in the
/// browser, neither of which has a real path to serve from.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/share/share_service.dart';

/// A page ready to hand to the WebView, plus what could not be included.
class BundledPage {
  const BundledPage({required this.html, required this.notes});

  final String html;

  /// Human-readable notes about anything left out — a missing file, or a
  /// remote URL this app cannot fetch. Shown to the user rather than swallowed,
  /// because a preview missing its stylesheet otherwise looks like broken CSS.
  final List<String> notes;
}

/// Largest asset that will be inlined.
///
/// Beyond this the page is better off missing one image than being a 40 MB
/// string the WebView has to parse.
const int kMaxInlinedAssetBytes = 4 * 1024 * 1024;

class HtmlBundler {
  const HtmlBundler();

  /// Inlines relative stylesheets, scripts and images referenced by [html].
  ///
  /// [fileId] is the page's own id, used to resolve its siblings through
  /// [provider]. Remote URLs are left exactly as written and reported.
  Future<BundledPage> bundle({
    required String html,
    required String fileId,
    required FileSystemProvider provider,
  }) async {
    final List<String> notes = <String>[];
    final String? parent = provider.parentOf(fileId);
    if (parent == null) {
      return BundledPage(html: html, notes: notes);
    }

    String out = html;
    out = await _inlineStylesheets(out, parent, provider, notes);
    out = await _inlineScripts(out, parent, provider, notes);
    out = await _inlineImages(out, parent, provider, notes);
    return BundledPage(html: out, notes: notes);
  }

  Future<String> _inlineStylesheets(
    String html,
    String parent,
    FileSystemProvider provider,
    List<String> notes,
  ) async {
    final RegExp link = RegExp(
      r'''<link\b[^>]*\brel\s*=\s*["']?stylesheet["']?[^>]*>''',
      caseSensitive: false,
    );
    return _replaceAllAsync(html, link, (Match match) async {
      final String tag = match[0]!;
      final String? href = _attribute(tag, 'href');
      if (href == null || isRemote(href)) {
        if (href != null) {
          notes.add('Did not load $href — previews never fetch remote files.');
        }
        return tag;
      }
      final String? css =
          await _readText(provider, parent, href, notes);
      return css == null ? tag : '<style>\n$css\n</style>';
    });
  }

  Future<String> _inlineScripts(
    String html,
    String parent,
    FileSystemProvider provider,
    List<String> notes,
  ) async {
    final RegExp script = RegExp(
      r'''<script\b[^>]*\bsrc\s*=\s*["'][^"']+["'][^>]*>\s*</script>''',
      caseSensitive: false,
    );
    return _replaceAllAsync(html, script, (Match match) async {
      final String tag = match[0]!;
      final String? src = _attribute(tag, 'src');
      if (src == null || isRemote(src)) {
        if (src != null) {
          notes.add('Did not load $src — previews never fetch remote files.');
        }
        return tag;
      }
      final String? js = await _readText(provider, parent, src, notes);
      if (js == null) {
        return tag;
      }
      // The script is inlined verbatim, so a literal `</script>` inside a
      // string would end the block early and break the page.
      return '<script>\n${js.replaceAll('</script>', r'<\/script>')}\n</script>';
    });
  }

  Future<String> _inlineImages(
    String html,
    String parent,
    FileSystemProvider provider,
    List<String> notes,
  ) async {
    final RegExp img = RegExp(
      r'''<img\b[^>]*\bsrc\s*=\s*["'][^"']+["'][^>]*>''',
      caseSensitive: false,
    );
    return _replaceAllAsync(html, img, (Match match) async {
      final String tag = match[0]!;
      final String? src = _attribute(tag, 'src');
      if (src == null || isRemote(src) || src.startsWith('data:')) {
        if (src != null && isRemote(src)) {
          notes.add('Did not load $src — previews never fetch remote files.');
        }
        return tag;
      }
      final Uint8List? bytes = await _readBytes(provider, parent, src, notes);
      if (bytes == null) {
        return tag;
      }
      final String encoded =
          'data:${mimeTypeFor(src)};base64,${base64Encode(bytes)}';
      return tag.replaceFirst(RegExp(RegExp.escape(src)), encoded);
    });
  }

  Future<String?> _readText(
    FileSystemProvider provider,
    String parent,
    String reference,
    List<String> notes,
  ) async {
    final Uint8List? bytes =
        await _readBytes(provider, parent, reference, notes);
    if (bytes == null) {
      return null;
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      notes.add('Skipped $reference — it is not valid UTF-8 text.');
      return null;
    }
  }

  Future<Uint8List?> _readBytes(
    FileSystemProvider provider,
    String parent,
    String reference,
    List<String> notes,
  ) async {
    final String? id = resolveReference(provider, parent, reference);
    if (id == null) {
      notes.add('Skipped $reference — it points outside this folder.');
      return null;
    }
    try {
      final Uint8List bytes = await provider.readBytes(id);
      if (bytes.length > kMaxInlinedAssetBytes) {
        notes.add('Skipped $reference — larger than 4 MB.');
        return null;
      }
      return bytes;
    } on AppFailure {
      notes.add('Could not read $reference — it may have been moved.');
      return null;
    }
  }
}

/// Whether [reference] points somewhere this app cannot reach.
bool isRemote(String reference) {
  final String value = reference.trim().toLowerCase();
  return value.startsWith('http://') ||
      value.startsWith('https://') ||
      value.startsWith('//') ||
      value.startsWith('ftp:');
}

/// Resolves a relative [reference] against [parent] using the provider's own
/// id arithmetic, or null if it escapes the folder.
///
/// Never string-splits an id: a SAF id is a percent-encoded URI, so `childId`
/// and `parentOf` are the only safe way to walk. A reference that climbs above
/// the page's own folder is refused rather than resolved — the same rule the
/// ZIP importer applies.
String? resolveReference(
  FileSystemProvider provider,
  String parent,
  String reference,
) {
  final String cleaned = reference.split('#').first.split('?').first.trim();
  if (cleaned.isEmpty || cleaned.startsWith('/')) {
    return null;
  }
  String current = parent;
  final List<String> segments = cleaned.replaceAll('\\', '/').split('/');
  for (int i = 0; i < segments.length; i++) {
    final String segment = segments[i];
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      return null;
    }
    current = provider.childId(current, segment);
  }
  return current == parent ? null : current;
}

/// `String.replaceAllMapped`, but the replacement may be asynchronous.
Future<String> _replaceAllAsync(
  String input,
  RegExp pattern,
  Future<String> Function(Match) replace,
) async {
  final StringBuffer out = StringBuffer();
  int last = 0;
  for (final Match match in pattern.allMatches(input)) {
    out.write(input.substring(last, match.start));
    out.write(await replace(match));
    last = match.end;
  }
  out.write(input.substring(last));
  return out.toString();
}

/// Reads one attribute out of a tag.
String? _attribute(String tag, String name) {
  final RegExpMatch? match = RegExp(
    '''\\b$name\\s*=\\s*["']([^"']*)["']''',
    caseSensitive: false,
  ).firstMatch(tag);
  return match?.group(1);
}
