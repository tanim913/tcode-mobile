/// The Markdown preview and the toggle that reaches it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/core/theme/app_theme.dart';
import 'package:pocket_code/features/viewers/application/preview_mode.dart';
import 'package:pocket_code/features/viewers/presentation/markdown_preview.dart';
import 'package:pocket_code/services/language/language_registry.dart';

Widget wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );

void main() {
  group('canPreview', () {
    test('is Markdown only, and says so by being false elsewhere', () {
      expect(canPreview(LanguageRegistry.byId('markdown')!), isTrue);
      expect(canPreview(LanguageRegistry.byId('dart')!), isFalse);
      expect(canPreview(LanguageRegistry.byId('json')!), isFalse);
      expect(canPreview(LanguageRegistry.plainText), isFalse,
          reason: 'a toggle that renders nothing must be disabled, not offered');
    });
  });

  group('PreviewMode', () {
    test('toggles per tab, independently', () {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      final PreviewMode mode = c.read(previewModeProvider.notifier);

      expect(mode.isPreviewing('0:a.md'), isFalse);
      mode.toggle('0:a.md');
      expect(mode.isPreviewing('0:a.md'), isTrue);
      expect(mode.isPreviewing('0:b.md'), isFalse,
          reason: 'one file in preview must not put every file in preview');

      mode.toggle('0:a.md');
      expect(mode.isPreviewing('0:a.md'), isFalse);
    });

    test('toggling the same key twice returns to the source view', () {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      final PreviewMode mode = c.read(previewModeProvider.notifier);

      mode.toggle('0:a.md');
      mode.toggle('0:a.md');
      expect(mode.isPreviewing('0:a.md'), isFalse);
    });
  });

  group('MarkdownPreview', () {
    testWidgets('renders headings and text from the source', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MarkdownPreview(
            source: '# Title\n\nSome body text.',
            onLinkTapped: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Title'), findsOneWidget);
      expect(find.textContaining('Some body text.'), findsOneWidget);
    });

    testWidgets('an empty document says so rather than rendering blank', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(MarkdownPreview(source: '   \n', onLinkTapped: (_) {})),
      );

      expect(find.text('Nothing to preview yet'), findsOneWidget);
    });

    testWidgets('does not render the raw markup', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(MarkdownPreview(source: '# Heading', onLinkTapped: (_) {})),
      );
      await tester.pumpAndSettle();

      expect(find.text('# Heading'), findsNothing,
          reason: 'this is the rendered view; the source view is the editor');
    });
  });
}
