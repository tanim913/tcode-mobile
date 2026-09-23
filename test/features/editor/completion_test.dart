/// Word completion: what is indexed, what is offered, and in what order.
///
/// Everything here is pure. That the popup *appears* cannot be tested — it
/// needs a laid-out, focused `CodeEditor`, which is the combination this repo
/// already records as unreliable under `flutter_test` — so it is verified on a
/// device instead.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/features/editor/application/completion_prompts.dart';
import 'package:pocket_code/features/editor/application/word_index.dart';
import 'package:pocket_code/features/editor/presentation/completion_popup.dart';
import 'package:re_editor/re_editor.dart';

/// The builder never touches its context — it only reads text and the index —
/// so a real element is not needed to exercise it.
final BuildContext _fakeContext = _NoContext();

Set<String> wordsOf(List<String> lines) =>
    extractWords(lines.length, (int i) => lines[i]);

List<String> ranked({
  required String input,
  Set<String> buffer = const <String>{},
  List<String> keywords = const <String>[],
  int max = 12,
}) =>
    rankCompletions(
      input: input,
      bufferWords: buffer,
      keywords: keywords,
      max: max,
    ).map((Completion c) => c.word).toList();

void main() {
  group('extractWords', () {
    test('collects identifiers, including digits and underscores', () {
      expect(
        wordsOf(<String>['final sha256 = compute_hash(userName);']),
        containsAll(<String>['final', 'sha256', 'compute_hash', 'userName']),
      );
    });

    test('a digit inside a word does not split it', () {
      // re_editor's own extractor stops at the digit, which would index `sha`
      // and never match `sha256` as it is typed.
      expect(wordsOf(<String>['sha256']), contains('sha256'));
      expect(wordsOf(<String>['sha256']), isNot(contains('sha')));
    });

    test('words shorter than the floor are skipped', () {
      expect(wordsOf(<String>['a bc def']), <String>{'def'});
    });

    test('punctuation and numbers are not words', () {
      expect(wordsOf(<String>['x = 12345 + (y);']), isEmpty,
          reason: 'nothing here is a 3-character identifier');
    });

    test('the cap is honoured', () {
      final List<String> lines = <String>[
        for (int i = 0; i < 500; i++) 'name$i value$i',
      ];
      expect(
        extractWords(lines.length, (int i) => lines[i], maxWords: 50),
        hasLength(50),
      );
    });

    test('an empty buffer yields nothing', () {
      expect(wordsOf(<String>[]), isEmpty);
      expect(wordsOf(<String>['', '   ']), isEmpty);
    });
  });

  group('identifierBefore', () {
    test('reads the run ending at the cursor', () {
      expect(identifierBefore('final user', 10)?.input, 'user');
      expect(identifierBefore('final user', 10)?.start, 6);
    });

    test('null below the minimum prefix', () {
      expect(identifierBefore('final u', 7), isNull);
      expect(identifierBefore('final us', 8)?.input, 'us');
    });

    test('a number is not an identifier being typed', () {
      expect(identifierBefore('x = 1234', 8), isNull);
    });

    test('stops at a dot rather than reading through it', () {
      expect(identifierBefore('user.name', 9)?.input, 'name');
    });

    test('the start of a line and an empty line are handled', () {
      expect(identifierBefore('', 0), isNull);
      expect(identifierBefore('ab', 0), isNull);
    });
  });

  group('insideStringOrComment', () {
    test('inside a double-quoted string', () {
      expect(insideStringOrComment('x = "hello', 9), isTrue);
    });

    test('after a closed string it is code again', () {
      expect(insideStringOrComment('x = "hi" + na', 13), isFalse);
    });

    test('an escaped quote does not close the string', () {
      expect(insideStringOrComment(r'x = "a\" still', 14), isTrue);
    });

    test('after a line comment marker', () {
      expect(insideStringOrComment('x = 1 // note', 13, lineComment: '//'),
          isTrue);
      expect(insideStringOrComment('x = 1 // note', 3, lineComment: '//'),
          isFalse);
    });

    test('a language with no line comment is unaffected', () {
      expect(insideStringOrComment('a // b', 6), isFalse);
    });
  });

  group('rankCompletions', () {
    test('buffer words come before keywords', () {
      expect(
        ranked(
          input: 'co',
          buffer: <String>{'counter'},
          keywords: <String>['const'],
        ),
        <String>['counter', 'const'],
        reason: 'the name about to be typed is usually already in the file',
      );
    });

    test('shorter matches first, then alphabetical', () {
      expect(
        ranked(input: 'va', buffer: <String>{'validate', 'value', 'valid'}),
        <String>['valid', 'value', 'validate'],
      );
    });

    test('the word already typed is not offered back', () {
      expect(ranked(input: 'value', buffer: <String>{'value'}), isEmpty);
    });

    test('a keyword already in the buffer is not listed twice', () {
      expect(
        ranked(
          input: 'cla',
          buffer: <String>{'class'},
          keywords: <String>['class'],
        ),
        <String>['class'],
      );
    });

    test('matching ignores case but the suggestion keeps its own', () {
      expect(ranked(input: 'us', buffer: <String>{'userName'}),
          <String>['userName']);
    });

    test('non-matches are excluded', () {
      expect(ranked(input: 'zz', buffer: <String>{'alpha', 'beta'}), isEmpty);
    });

    test('empty input offers nothing', () {
      expect(ranked(input: '', buffer: <String>{'anything'}), isEmpty);
    });

    test('the cap is honoured', () {
      expect(
        ranked(
          input: 'n',
          buffer: <String>{for (int i = 0; i < 40; i++) 'name$i'},
          max: 5,
        ),
        hasLength(5),
      );
    });
  });

  group('promptsFor', () {
    test('labels where each suggestion came from', () {
      final List<Completion> completions = <Completion>[
        const Completion('counter', CompletionKind.buffer),
        const Completion('const', CompletionKind.keyword),
      ];
      final prompts = promptsFor(completions);
      expect(prompts.map((p) => p.word), <String>['counter', 'const']);
      expect(labelFor(CompletionKind.buffer), 'in file');
      expect(labelFor(CompletionKind.keyword), 'keyword');
    });
  });

  group('the prompts builder', () {
    WordPromptsBuilder builderFor({
      bool enabled = true,
      Set<String> buffer = const <String>{'counter', 'container'},
      String? lineComment = '//',
    }) =>
        WordPromptsBuilder(
          enabled: () => enabled,
          bufferWords: () => buffer,
          keywords: () => const <String>['const'],
          lineComment: () => lineComment,
        );

    CodeLineSelection at(int offset) =>
        CodeLineSelection.collapsed(index: 0, offset: offset);

    test('offers matches for the word being typed', () {
      final CodeAutocompleteEditingValue? value = builderFor()
          .build(_fakeContext, const CodeLine('final co'), at(8));
      expect(value, isNotNull);
      expect(value!.input, 'co');
      expect(value.prompts.map((CodePrompt p) => p.word),
          containsAll(<String>['const', 'counter']));
    });

    test('offers nothing when switched off', () {
      // Switching off must not change the shape of the widget tree, so it is
      // done here rather than by unmounting the wrapper.
      expect(
        builderFor(enabled: false)
            .build(_fakeContext, const CodeLine('final co'), at(8)),
        isNull,
      );
    });

    test('offers nothing inside a comment', () {
      expect(
        builderFor().build(_fakeContext, const CodeLine('// co'), at(5)),
        isNull,
      );
    });

    test('offers nothing inside a string', () {
      expect(
        builderFor().build(_fakeContext, const CodeLine('x = "co'), at(7)),
        isNull,
      );
    });

    test('offers nothing for a selection, only a caret', () {
      expect(
        builderFor().build(
          _fakeContext,
          const CodeLine('final co'),
          const CodeLineSelection(
            baseIndex: 0,
            baseOffset: 0,
            extentIndex: 0,
            extentOffset: 8,
          ),
        ),
        isNull,
      );
    });

    test('offers nothing when nothing matches', () {
      expect(
        builderFor().build(_fakeContext, const CodeLine('final zz'), at(8)),
        isNull,
      );
    });
  });

  group('popup size', () {
    test('grows with the number of rows, then stops', () {
      expect(completionPopupHeight(0), lessThan(completionPopupHeight(1)));
      expect(completionPopupHeight(1), lessThan(completionPopupHeight(5)));
      expect(completionPopupHeight(12), completionPopupHeight(5),
          reason: 'beyond the visible rows the list scrolls instead');
    });

    test('a row is a full touch target, because tapping is the only way to '
        'accept on a soft keyboard', () {
      expect(kCompletionRowHeight, greaterThanOrEqualTo(44));
    });
  });
}

/// Stands in for a `BuildContext` the prompts builder never uses.
class _NoContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
