/// Quick Open: type a few letters, open any file in the workspace.
///
/// Ranks on the path but highlights the basename, because that is what people
/// are aiming at — `fsp` should find `services/filesystem/file_system_provider.dart`
/// and show you which letters earned it.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/core/utils/fuzzy_matcher.dart';
import 'package:pocket_code/features/commands/presentation/palette_scaffold.dart';
import 'package:pocket_code/features/explorer/presentation/file_icons.dart';
import 'package:pocket_code/services/search/file_indexer.dart';

/// One file plus the match that ranked it.
@immutable
class RankedFile {
  const RankedFile({
    required this.file,
    required this.score,
    required this.nameIndices,
  });

  final IndexedFile file;
  final int score;

  /// Indices into the *basename*, for the highlight.
  final List<int> nameIndices;
}

/// Filters and ranks [files] against [query], best first.
///
/// Scores the whole relative path — so `lib/main` works — but keeps the
/// basename's own match indices for display. `FuzzyMatcher` already rewards a
/// basename hit heavily, so ranking on the path costs nothing and lets people
/// narrow by folder.
List<RankedFile> rankFiles(
  List<IndexedFile> files,
  String query, {
  int limit = 200,
}) {
  final String pattern = query.trim();
  if (pattern.isEmpty) {
    // No query: show the shallowest files, which are the likeliest targets.
    final List<IndexedFile> shallow = List<IndexedFile>.of(files)
      ..sort((IndexedFile a, IndexedFile b) {
        final int byDepth = '/'.allMatches(a.relativePath).length
            .compareTo('/'.allMatches(b.relativePath).length);
        return byDepth != 0
            ? byDepth
            : a.relativePath.compareTo(b.relativePath);
      });
    return shallow
        .take(limit)
        .map((IndexedFile f) =>
            RankedFile(file: f, score: 0, nameIndices: const <int>[]))
        .toList();
  }

  final List<RankedFile> ranked = <RankedFile>[];
  for (final IndexedFile file in files) {
    final FuzzyMatch? onPath = FuzzyMatcher.match(pattern, file.relativePath);
    if (onPath == null) {
      continue;
    }
    final FuzzyMatch? onName = FuzzyMatcher.match(pattern, file.name);
    ranked.add(
      RankedFile(
        file: file,
        score: onPath.score,
        nameIndices: onName?.indices ?? const <int>[],
      ),
    );
  }
  ranked.sort((RankedFile a, RankedFile b) {
    final int byScore = b.score.compareTo(a.score);
    return byScore != 0
        ? byScore
        : a.file.relativePath.compareTo(b.file.relativePath);
  });
  return ranked.length > limit ? ranked.sublist(0, limit) : ranked;
}

/// Shows Quick Open over [index]. Returns the chosen file, or null.
Future<IndexedFile?> showQuickOpen(
  BuildContext context, {
  required Future<FileIndex> index,
}) {
  return showPaletteSheet<IndexedFile>(
    context: context,
    builder: (BuildContext context, ScrollController scrollController) =>
        _QuickOpen(index: index, scrollController: scrollController),
  );
}

class _QuickOpen extends StatefulWidget {
  const _QuickOpen({required this.index, required this.scrollController});

  final Future<FileIndex> index;
  final ScrollController scrollController;

  @override
  State<_QuickOpen> createState() => _QuickOpenState();
}

class _QuickOpenState extends State<_QuickOpen> {
  final TextEditingController _query = TextEditingController();
  FileIndex? _index;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final FileIndex index = await widget.index;
    if (mounted) {
      setState(() => _index = index);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _choose(IndexedFile file) => Navigator.of(context).pop(file);

  @override
  Widget build(BuildContext context) {
    final FileIndex? index = _index;
    // Indexing is the one thing here that can take a visible moment, so it gets
    // a real loading state rather than an empty list that looks like no results.
    if (index == null) {
      // The field stays live while the walk runs, so typing is never blocked
      // by indexing — whatever is typed is applied the moment results land.
      return PaletteScaffold(
        controller: _query,
        hintText: 'Searching the workspace…',
        semanticsLabel: 'Go to file',
        onChanged: (_) => setState(() {}),
        onSubmitted: () {},
        resultCount: 0,
        emptyMessage: '',
        loading: true,
        child: const SizedBox.shrink(),
      );
    }

    final List<RankedFile> results = rankFiles(index.files, _query.text);

    return PaletteScaffold(
      controller: _query,
      hintText: 'Search files by name',
      semanticsLabel: 'Go to file',
      onChanged: (_) => setState(() {}),
      onSubmitted: () {
        if (results.isNotEmpty) {
          _choose(results.first.file);
        }
      },
      resultCount: results.length,
      emptyMessage: index.files.isEmpty
          ? 'No files in this workspace yet'
          : 'No file matches "${_query.text.trim()}"',
      footer: index.truncated
          ? Text(
              'Showing the first ${index.files.length} files. This workspace '
              'has more than Quick Open indexes.',
            )
          : null,
      child: ListView.builder(
        controller: widget.scrollController,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: results.length,
        itemBuilder: (BuildContext context, int i) => _FileRow(
          ranked: results[i],
          onTap: () => _choose(results[i].file),
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.ranked, required this.onTap});

  final RankedFile ranked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppColorTokens tokens = theme.extension<AppColorTokens>()!;
    final IndexedFile file = ranked.file;
    final FileIcon icon = FileIcons.forNode(file.node);
    // The row already names the file; the second line is where it lives.
    final int cut = file.relativePath.lastIndexOf('/');
    final String folder = cut <= 0 ? '' : file.relativePath.substring(0, cut);

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: file.name,
      hint: folder.isEmpty ? 'In the workspace root' : 'In $folder',
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppSizes.primaryTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: <Widget>[
              Icon(icon.icon, size: 16, color: icon.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    HighlightedText(
                      text: file.name,
                      indices: ranked.nameIndices,
                      highlightColour: tokens.accent,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: tokens.textPrimary),
                    ),
                    if (folder.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        folder,
                        maxLines: 1,
                        // The tail of a path identifies it; the head repeats.
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: tokens.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
