/// Accounts: tokens for GitHub and GitLab. Only in builds that can reach the
/// network — the Play build has no section at all rather than a dead one.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/features/accounts/application/accounts_controller.dart';
import 'package:pocket_code/features/accounts/presentation/accounts_screen.dart';
import 'package:pocket_code/features/settings/application/settings_catalog.dart';
import 'package:pocket_code/features/settings/presentation/widgets/setting_entries.dart';

SettingsGroup buildAccountsGroup(WidgetRef ref) {
  return SettingsGroup(
    id: 'accounts',
    title: 'Accounts',
    description: 'Tokens for private repositories and pull requests.',
    // "Reset" here means signing out everywhere. The screen's confirmation
    // names the group, which is enough warning for an action the user can
    // undo by pasting the token again.
    onReset: () => ref.read(accountsProvider.notifier).signOutAll(),
    entries: <SettingEntry>[
      customEntry(
        id: 'accounts.tokens',
        title: 'GitHub and GitLab',
        description: 'Paste a personal access token to download private '
            'repositories and open pull or merge requests from your changes.',
        keywords: const <String>[
          'sign in',
          'login',
          'token',
          'github',
          'gitlab',
          'private',
          'pull request',
          'merge request',
        ],
        child: const AccountsSummary(),
      ),
    ],
  );
}
