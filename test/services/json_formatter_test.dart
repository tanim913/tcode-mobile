/// The JSON formatter.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/services/format/json_formatter.dart';

void main() {
  group('formatJson', () {
    test('re-indents a compact document', () {
      final FormatResult r = formatJson('{"a":1,"b":[2,3]}');

      expect(r, isA<FormatSuccess>());
      expect(
        (r as FormatSuccess).text,
        '{\n  "a": 1,\n  "b": [\n    2,\n    3\n  ]\n}',
      );
      expect(r.changed, isTrue);
    });

    test('honours the document indent unit, including tabs', () {
      final FormatSuccess r =
          formatJson('{"a":1}', indent: '\t') as FormatSuccess;
      expect(r.text, '{\n\t"a": 1\n}',
          reason: 'formatting must not convert a tab-indented file to spaces');
    });

    test('reports an already-formatted document as unchanged', () {
      const String pretty = '{\n  "a": 1\n}';
      final FormatSuccess r = formatJson(pretty) as FormatSuccess;

      expect(r.changed, isFalse,
          reason: 'dirtying a clean buffer would start an auto-save for nothing');
      expect(r.text, pretty);
    });

    test('preserves a trailing newline, and its absence', () {
      expect((formatJson('{"a":1}\n') as FormatSuccess).text, endsWith('}\n'));
      expect((formatJson('{"a":1}') as FormatSuccess).text, endsWith('}'));
    });

    test('invalid JSON changes nothing and reports where', () {
      final FormatResult r = formatJson('{"a": 1,\n"b": }');

      expect(r, isA<FormatFailure>());
      final FormatFailure failure = r as FormatFailure;
      expect(failure.message, isNotEmpty);
      expect(failure.line, 2,
          reason: 'the caller offers to jump to the problem');
    });

    test('an empty document is refused, not turned into null', () {
      expect(formatJson('   '), isA<FormatFailure>());
    });

    test('handles a top-level array and a bare value', () {
      expect((formatJson('[1,2]') as FormatSuccess).text, '[\n  1,\n  2\n]');
      expect((formatJson('"hello"') as FormatSuccess).text, '"hello"');
    });

    test('does not reorder keys', () {
      final FormatSuccess r = formatJson('{"z":1,"a":2}') as FormatSuccess;
      expect(r.text.indexOf('"z"'), lessThan(r.text.indexOf('"a"')),
          reason: 'reordering a config file is a change nobody asked for');
    });

    test('preserves unicode rather than escaping it', () {
      final FormatSuccess r = formatJson('{"a":"café ☕"}') as FormatSuccess;
      expect(r.text, contains('café ☕'));
    });
  });

  group('isValidJson', () {
    test('accepts valid documents and rejects the rest', () {
      expect(isValidJson('{"a":1}'), isTrue);
      expect(isValidJson('[1,2]'), isTrue);
      expect(isValidJson('{a:1}'), isFalse);
      expect(isValidJson(''), isFalse);
      expect(isValidJson('   '), isFalse);
    });
  });
}
