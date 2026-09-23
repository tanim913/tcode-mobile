/// Search — and replace — across the whole workspace, or one folder of it.
///
/// "Find in Folder" is this same screen opened with a [SearchScope]. The scope
/// is shown as a chip for as long as it applies, and widening it to the whole
/// workspace is one tap on the chip's close button.
///
/// A full screen rather than a sheet: results are grouped by file and there is
/// a second input for the replacement, which a bottom sheet cannot hold on a
/// phone without burying one of them behind the keyboard.
///
/// Replace-all is deliberately gated behind a confirmation naming the exact
/// number of files and matches. It is the one action here that rewrites files
/// the user cannot see, and the undo for it is "restore from a backup you did
/// not make".
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/features/search/presentation/search_inputs.dart';
import 'package:pocket_code/features/search/presentation/search_results.dart';
import 'package:pocket_code/services/search/search_scope.dart';
import 'package:pocket_code/services/search/workspace_search.dart';

class SearchPanel extends StatefulWidget {
  const SearchPanel({
    required this.onSearch,
    required this.onReplaceAll,
    required this.onOpenHit,
    this.initialScope,
    super.key,
  });

  /// Runs a search, within [SearchScope] when one is given. The panel owns no
  /// I/O itself.
  final Future<SearchResults> Function(SearchQuery, SearchScope?) onSearch;

  /// Applies the replacement. Returns how many files were rewritten.
  ///
  /// Receives the scope too, and must honour it: replacing across the whole
  /// workspace after the user narrowed the search to one folder would rewrite
  /// files they never saw in the results.
  final Future<int> Function(SearchQuery, String, SearchScope?) onReplaceAll;

  /// Where the search starts out confined, for Find in Folder.
  final SearchScope? initialScope;

  final SearchHitCallback onOpenHit;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  final TextEditingController _pattern = TextEditingController();
  final TextEditingController _replacement = TextEditingController();

  bool _caseSensitive = false;
  bool _wholeWord = false;
  bool _regex = false;
  bool _showReplace = false;
  bool _running = false;
  SearchResults? _results;
  late SearchScope? _scope = widget.initialScope;

  @override
  void dispose() {
    _pattern.dispose();
    _replacement.dispose();
    super.dispose();
  }

  SearchQuery get _query => SearchQuery(
        pattern: _pattern.text,
        caseSensitive: _caseSensitive,
        wholeWord: _wholeWord,
        regex: _regex,
      );

  /// True when the user asked for a regex and it does not compile.
  bool get _badRegex =>
      _regex && _pattern.text.isNotEmpty && _query.compile() == null;

  Future<void> _run() async {
    if (_query.isEmpty || _badRegex) {
      return;
    }
    setState(() => _running = true);
    final SearchResults results = await widget.onSearch(_query, _scope);
    if (mounted) {
      setState(() {
        _results = results;
        _running = false;
      });
    }
  }

  Future<void> _replaceAll() async {
    final SearchResults? results = _results;
    if (results == null || results.files.isEmpty) {
      return;
    }
    final int fileCount = results.files.length;
    final int matchCount = results.matchCount;
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text(
              _scope == null
                  ? 'Replace across the workspace?'
                  : 'Replace in ${_scope!.label}?',
            ),
            content: Text(
              'This replaces $matchCount '
              '${matchCount == 1 ? 'match' : 'matches'} in $fileCount '
              '${fileCount == 1 ? 'file' : 'files'}'
              '${_scope == null ? '' : ' inside ${_scope!.label}'}.\n\n'
              'Files that are not open will be changed on disk, and this '
              'cannot be undone from inside the app.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Replace all'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _running = true);
    final int changed =
        await widget.onReplaceAll(_query, _replacement.text, _scope);
    if (!mounted) {
      return;
    }
    setState(() => _running = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          changed == 1 ? 'Replaced in 1 file' : 'Replaced in $changed files',
        ),
      ),
    );
    await _run();
  }

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: Text(_scope == null ? 'Search in workspace' : 'Find in folder'),
        actions: <Widget>[
          IconButton(
            tooltip: _showReplace ? 'Hide replace' : 'Show replace',
            icon: Icon(_showReplace ? Icons.find_in_page : Icons.find_replace),
            onPressed: () => setState(() => _showReplace = !_showReplace),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          SearchInputs(
            pattern: _pattern,
            replacement: _replacement,
            showReplace: _showReplace,
            badRegex: _badRegex,
            caseSensitive: _caseSensitive,
            wholeWord: _wholeWord,
            regex: _regex,
            onToggleCase: () =>
                setState(() => _caseSensitive = !_caseSensitive),
            onToggleWord: () => setState(() => _wholeWord = !_wholeWord),
            onToggleRegex: () => setState(() => _regex = !_regex),
            onSubmit: _run,
            onChanged: () => setState(() {}),
          ),
          if (_scope != null)
            SearchScopeChip(scope: _scope!, onClear: _widenScope),
          if (_showReplace)
            SearchReplaceBar(
              enabled: !_running &&
                  (_results?.files.isNotEmpty ?? false),
              onReplaceAll: _replaceAll,
            ),
          const Divider(height: 1),
          if (_running) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _body(tokens)),
        ],
      ),
    );
  }

  /// Drops the folder scope and, if a query is already there, searches again
  /// so the results on screen always match the chip.
  Future<void> _widenScope() async {
    setState(() {
      _scope = null;
      _results = null;
    });
    await _run();
  }

  Widget _body(AppColorTokens tokens) {
    final SearchResults? results = _results;
    if (results == null) {
      return SearchHint(
        icon: Icons.search,
        text: _running
            ? 'Searching…'
            : _scope == null
                ? 'Type something and press search to look through every file '
                    'in the workspace.'
                : 'Type something and press search to look through every file '
                    'in ${_scope!.label}',
        tokens: tokens,
      );
    }
    if (results.files.isEmpty) {
      return SearchHint(
        icon: Icons.search_off,
        // Distinguishes "looked and found nothing" from "could not look".
        text: 'No matches in ${results.filesSearched} '
            '${results.filesSearched == 1 ? 'file' : 'files'}.'
            '${results.filesSkipped > 0 ? '\n${results.filesSkipped} skipped as too large or not text.' : ''}',
        tokens: tokens,
      );
    }

    return Column(
      children: <Widget>[
        SearchSummary(results: results, tokens: tokens),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: results.files.length,
            itemBuilder: (BuildContext context, int i) => SearchFileGroup(
              group: results.files[i],
              onOpenHit: widget.onOpenHit,
            ),
          ),
        ),
      ],
    );
  }
}
