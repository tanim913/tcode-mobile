/// Pasting a token: checked with the host before it is kept.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/data/repositories/credentials_repository.dart';
import 'package:pocket_code/features/accounts/application/accounts_controller.dart';
import 'package:pocket_code/features/accounts/presentation/accounts_screen.dart';

import '../../data/credentials_repository_test.dart' show MapStore;
import '../../support/fake_transport.dart';
import '../../support/harness.dart';

Future<MapStore> pumpAccounts(WidgetTester tester, FakeTransport net) async {
  final MapStore store = MapStore();
  await pumpInApp(
    tester,
    const AccountsScreen(),
    overrides: <Override>[
      httpTransportProvider.overrideWithValue(net),
      credentialsRepositoryProvider
          .overrideWithValue(CredentialsRepository(store)),
    ],
  );
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('a valid token is stored and shows who it belongs to',
      (tester) async {
    final FakeTransport net = FakeTransport()
      ..onJson('GET', 'api.github.com/user', <String, Object?>{'login': 'me'});
    final MapStore store = await pumpAccounts(tester, net);

    await tester.enterText(find.byType(TextField).first, '  ghp_sekrit \n');
    await tester.tap(find.text('Sign in').first);
    await tester.pumpAndSettle();

    expect(find.text('Signed in as @me'), findsOneWidget);
    expect(store.values['token.github'], 'ghp_sekrit',
        reason: 'pasted whitespace is trimmed before storing');
    expect(net.requests.single.headers['Authorization'], 'Bearer ghp_sekrit');
  });

  testWidgets('a refused token is not stored, and the reason is shown',
      (tester) async {
    final FakeTransport net = FakeTransport()
      ..onJson('GET', 'api.github.com/user',
          <String, Object?>{'message': 'Bad credentials'}, status: 401);
    final MapStore store = await pumpAccounts(tester, net);

    await tester.enterText(find.byType(TextField).first, 'wrong');
    await tester.tap(find.text('Sign in').first);
    await tester.pumpAndSettle();

    expect(find.text('The host refused this token'), findsOneWidget);
    expect(store.values, isEmpty);
    expect(find.textContaining('sekrit'), findsNothing);
  });

  testWidgets('removing asks first, then forgets the token', (tester) async {
    final FakeTransport net = FakeTransport()
      ..onJson('GET', 'gitlab.com/api/v4/user',
          <String, Object?>{'username': 'gl'});
    final MapStore store = await pumpAccounts(tester, net);

    await tester.enterText(find.byType(TextField).last, 'glpat-x');
    await tester.tap(find.text('Sign in').last);
    await tester.pumpAndSettle();
    expect(find.text('Signed in as @gl'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove the GitLab token?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Signed in as @gl'), findsNothing);
    expect(store.values, isEmpty);
  });

  testWidgets('each host names the permissions its token needs',
      (tester) async {
    await pumpAccounts(tester, FakeTransport());
    expect(find.textContaining('"Pull requests"'), findsOneWidget);
    expect(find.textContaining('"api" scope'), findsOneWidget);
  });
}
