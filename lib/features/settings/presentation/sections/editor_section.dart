/// The Editor group: everything about how code is drawn and typed.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/features/settings/application/settings_catalog.dart';
import 'package:pocket_code/features/settings/presentation/widgets/editor_preview.dart';
import 'package:pocket_code/features/settings/presentation/widgets/setting_entries.dart';
import 'package:pocket_code/features/settings/presentation/widgets/setting_tiles.dart';
import 'package:pocket_code/features/snippets/presentation/snippets_editor.dart';

/// Sizes that cover almost every real choice, so the slider is the exception
/// rather than the only way in. Both write the same field.
const List<double> fontSizePresets = <double>[
  12,
  13,
  14,
  15,
  16,
  18,
  20,
  22,
  24,
];

const List<int> _autoSaveDelays = <int>[250, 500, 1000, 2000, 5000];

SettingsGroup buildEditorGroup(WidgetRef ref, EditorSettings editor) {
  void set(EditorSettings Function(EditorSettings) change) {
    unawaited(ref.read(settingsProvider.notifier).updateEditor(change));
  }

  return SettingsGroup(
    id: 'editor',
    title: 'Editor',
    description: 'Code font, indentation, saving and typing helpers.',
    header: const EditorPreview(),
    onReset: () => ref
        .read(settingsProvider.notifier)
        .updateEditor((EditorSettings _) => const EditorSettings()),
    entries: <SettingEntry>[
      sliderEntry(
        id: 'editor.fontSize',
        title: 'Font size',
        // Do not promise pinch zoom here until it exists: the brief is
        // explicit that the UI must not claim a feature it does not have.
        // When M8 lands, this is the line to update.
        description: 'How large code is drawn, in points.',
        keywords: const <String>['zoom', 'text size', 'bigger', 'smaller'],
        value: editor.fontSize,
        min: AppLimits.minFontSize,
        max: AppLimits.maxFontSize,
        divisions: (AppLimits.maxFontSize - AppLimits.minFontSize).round(),
        valueLabel: '${editor.fontSize.round()} pt',
        onChanged: (double value) => set(
          (EditorSettings e) => e.copyWith(fontSize: _clampFont(value)),
        ),
        below: SettingChoiceRow<double>(
          groupLabel: 'Font size presets',
          // Rounded so a size dragged off a preset still highlights the preset
          // it landed on: the chips and the slider are one value, not two.
          value: editor.fontSize.roundToDouble(),
          choices: <SettingChoice<double>>[
            for (final double size in fontSizePresets)
              SettingChoice<double>(size, '${size.round()}'),
          ],
          onChanged: (double value) =>
              set((EditorSettings e) => e.copyWith(fontSize: value)),
        ),
      ),
      choiceEntry<EditorFontFamily>(
        id: 'editor.fontFamily',
        title: 'Font family',
        description: 'Which monospace typeface code is drawn in. All three are '
            'bundled and work offline.',
        keywords: const <String>['typeface', 'jetbrains', 'fira', 'monospace'],
        value: editor.fontFamily,
        choices: <SettingChoice<EditorFontFamily>>[
          for (final EditorFontFamily family in EditorFontFamily.values)
            SettingChoice<EditorFontFamily>(family, family.label),
        ],
        onChanged: (EditorFontFamily value) =>
            set((EditorSettings e) => e.copyWith(fontFamily: value)),
      ),
      toggleEntry(
        id: 'editor.ligatures',
        title: 'Ligatures',
        description:
            'Draw glyph pairs such as arrow and not-equal as a single symbol.',
        keywords: const <String>['calt', 'arrows', 'symbols'],
        value: editor.ligatures,
        onChanged: (bool value) =>
            set((EditorSettings e) => e.copyWith(ligatures: value)),
      ),
      sliderEntry(
        id: 'editor.lineHeight',
        title: 'Line height',
        description: 'Vertical spacing between lines, as a multiple of the '
            'font size. Higher is airier and fits less on screen.',
        keywords: const <String>['leading', 'spacing', 'density'],
        value: editor.lineHeight,
        min: 1,
        max: 2.2,
        divisions: 12,
        valueLabel: '${editor.lineHeight.toStringAsFixed(1)}×',
        onChanged: (double value) => set(
          (EditorSettings e) =>
              e.copyWith(lineHeight: (value * 10).roundToDouble() / 10),
        ),
      ),
      toggleEntry(
        id: 'editor.wordWrap',
        title: 'Word wrap',
        description: 'Fold long lines to the width of the screen instead of '
            'scrolling sideways.',
        keywords: const <String>['soft wrap', 'horizontal scroll'],
        value: editor.wordWrap,
        onChanged: (bool value) =>
            set((EditorSettings e) => e.copyWith(wordWrap: value)),
      ),
      sliderEntry(
        id: 'editor.tabSize',
        title: 'Tab size',
        description: 'How many columns one indent level occupies.',
        keywords: const <String>['indent', 'width', 'spaces'],
        value: editor.tabSize.toDouble(),
        min: 1,
        max: 8,
        divisions: 7,
        valueLabel: '${editor.tabSize} columns',
        onChanged: (double value) =>
            set((EditorSettings e) => e.copyWith(tabSize: value.round())),
      ),
      toggleEntry(
        id: 'editor.insertSpaces',
        title: 'Insert spaces',
        description: 'Indent with spaces rather than tab characters.',
        keywords: const <String>['tabs', 'indentation'],
        value: editor.insertSpaces,
        onChanged: (bool value) =>
            set((EditorSettings e) => e.copyWith(insertSpaces: value)),
      ),
      toggleEntry(
        id: 'editor.detectIndentation',
        title: 'Detect indentation',
        description: 'Match the indentation a file already uses, overriding '
            'tab size and insert spaces for that file.',
        keywords: const <String>['guess', 'existing file'],
        value: editor.detectIndentation,
        onChanged: (bool value) =>
            set((EditorSettings e) => e.copyWith(detectIndentation: value)),
      ),
      toggleEntry(
        id: 'editor.showLineNumbers',
        title: 'Show line numbers',
        description: 'Draw the line number gutter down the left edge.',
        keywords: const <String>['gutter'],
        value: editor.showLineNumbers,
        onChanged: (bool value) =>
            set((EditorSettings e) => e.copyWith(showLineNumbers: value)),
      ),
      toggleEntry(
        id: 'editor.highlightCurrentLine',
        title: 'Highlight current line',
        description: 'Tint the line the cursor is on so it is easy to find.',
        keywords: const <String>['cursor line', 'caret'],
        value: editor.highlightCurrentLine,
        onChanged: (bool value) =>
            set((EditorSettings e) => e.copyWith(highlightCurrentLine: value)),
      ),
      // "Render whitespace" deliberately has no entry here. re_editor draws no
      // whitespace markers, and the only workaround — substituting glyphs via
      // its spanBuilder — rewrites the spans the editor measures and can break
      // cursor and selection offsets. A toggle that does nothing is worse than
      // an absent one, so it is skipped and recorded in the final report.
      toggleEntry(
        id: 'editor.autoClosingPairs',
        title: 'Auto closing pairs',
        description: 'Insert the matching bracket or quote as soon as you type '
            'the opening one.',
        keywords: const <String>['brackets', 'quotes', 'pairs'],
        value: editor.autoClosingPairs,
        onChanged: (bool value) =>
            set((EditorSettings e) => e.copyWith(autoClosingPairs: value)),
      ),
      toggleEntry(
        id: 'editor.fileHistory',
        title: 'Keep local file history',
        description: 'Saves a copy of a file before each time it is '
            'overwritten, so you can look back or restore. Kept on this '
            'device only, and removed if the app is uninstalled. It is not '
            'version control.',
        keywords: const <String>['history', 'versions', 'backup', 'restore'],
        value: editor.fileHistory,
        onChanged: (bool value) =>
            set((EditorSettings e) => e.copyWith(fileHistory: value)),
      ),
      sliderEntry(
        id: 'editor.historyMaxVersions',
        title: 'Versions kept per file',
        description: 'Older versions are dropped once there are more than '
            'this many.',
        keywords: const <String>['history', 'versions', 'retention'],
        value: editor.historyMaxVersions.toDouble(),
        min: 5,
        max: 200,
        divisions: 39,
        valueLabel: '${editor.historyMaxVersions}',
        onChanged: (double value) => set(
          (EditorSettings e) => e.copyWith(historyMaxVersions: value.round()),
        ),
      ),
      sliderEntry(
        id: 'editor.historyMaxAgeDays',
        title: 'Days of history kept',
        description: 'Versions older than this are removed, whichever limit '
            'is reached first.',
        keywords: const <String>['history', 'days', 'retention'],
        value: editor.historyMaxAgeDays.toDouble(),
        min: 1,
        max: 180,
        divisions: 179,
        valueLabel: '${editor.historyMaxAgeDays} days',
        onChanged: (double value) => set(
          (EditorSettings e) => e.copyWith(historyMaxAgeDays: value.round()),
        ),
      ),
      customEntry(
        id: 'editor.snippets',
        title: 'Snippets',
        description: 'Pieces of text you insert by name, from the command '
            'palette. Each one can apply to every language or just a few.',
        keywords: const <String>['snippet', 'template', 'abbreviation'],
        child: const SnippetsSummary(),
      ),
      toggleEntry(
        id: 'editor.wordCompletion',
        title: 'Suggest words while typing',
        description: 'Offers words already in this file, plus the language\'s '
            'keywords. Tap a suggestion to use it. It reads only the open '
            'file, so it will not know a name defined somewhere else.',
        keywords: const <String>[
          'autocomplete',
          'completion',
          'suggestions',
          'intellisense',
        ],
        value: editor.wordCompletion,
        onChanged: (bool value) =>
            set((EditorSettings e) => e.copyWith(wordCompletion: value)),
      ),
      toggleEntry(
        id: 'editor.codeFolding',
        title: 'Code folding',
        description: 'Show fold markers in the gutter. Folding follows '
            'brackets, and indentation in Python and YAML, which have none.',
        keywords: const <String>['fold', 'collapse', 'chunk', 'gutter'],
        value: editor.codeFolding,
        onChanged: (bool value) =>
            set((EditorSettings e) => e.copyWith(codeFolding: value)),
      ),
      choiceEntry<AutoSaveMode>(
        id: 'editor.autoSaveMode',
        title: 'Auto save',
        description: 'When unsaved changes are written back to the file.',
        keywords: const <String>['save', 'automatic', 'focus'],
        value: editor.autoSaveMode,
        choices: <SettingChoice<AutoSaveMode>>[
          for (final AutoSaveMode mode in AutoSaveMode.values)
            SettingChoice<AutoSaveMode>(mode, mode.label),
        ],
        onChanged: (AutoSaveMode value) =>
            set((EditorSettings e) => e.copyWith(autoSaveMode: value)),
      ),
      choiceEntry<int>(
        id: 'editor.autoSaveDelay',
        title: 'Auto save delay',
        description: 'How long typing must pause before an automatic save '
            'runs. Used only by the after a delay mode.',
        keywords: const <String>['debounce', 'wait', 'seconds'],
        value: editor.autoSaveDelayMs,
        choices: <SettingChoice<int>>[
          for (final int ms in _autoSaveDelays)
            SettingChoice<int>(ms, _delayLabel(ms)),
        ],
        onChanged: (int value) =>
            set((EditorSettings e) => e.copyWith(autoSaveDelayMs: value)),
      ),
    ],
  );
}

double _clampFont(double value) => value
    .roundToDouble()
    .clamp(AppLimits.minFontSize, AppLimits.maxFontSize);

String _delayLabel(int ms) => ms < 1000
    ? '$ms ms'
    : '${(ms / 1000).toStringAsFixed(ms % 1000 == 0 ? 0 : 1)} s';
