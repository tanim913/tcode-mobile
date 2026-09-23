# Tcode Mobile — architecture and conventions

A touch-first code editor for Android, built with Flutter. Offline and no
telemetry. The Play build has no network at all. The `full` build reaches
GitHub and GitLab only when the user downloads a repository or opens a pull
request. This is the working reference for anyone changing the code. The
Dart package is still called `pocket_code`, the project's working name.

## Commands

```bash
flutter analyze                   # must report zero errors AND zero warnings
flutter test                      # must be fully green
flutter test test/services/       # one area
dart fix --apply lib/             # auto-fix mechanical lints

flutter run -d chrome --web-port=8899   # fastest iteration loop
flutter build apk --debug --flavor play # Play Store build
flutter build apk --debug --flavor full # direct-APK build
```

There is no `ios/` folder yet. iOS is deferred, with the platform seams left in
place (every platform call goes through a service interface).

## Releasing

Versions are `MAJOR.MINOR.PATCH+BUILD` in `pubspec.yaml`. The build number only
ever goes up (Android refuses an update with a lower version code) and must stay
under 1000, because split APKs add `1000 × ABI` to it. Every user-visible change
gets a line under `## [Unreleased]` in `CHANGELOG.md` when it is made.

`tool/build_release.sh` builds both editions for arm64-v8a and armeabi-v7a into
`dist/vX.Y.Z/`, named by version, with `SHA256SUMS.txt`. Release builds are
signed by the key in `~/.tcode-release/key.properties` (or `$TCODE_SIGNING`),
and fall back to the debug key when it is absent. A debug-signed APK cannot
update an official release, so the script warns.

## Architecture

Layered, feature-first. One rule holds it together:

> **No code under `features/` imports `dart:io`, a `MethodChannel`, or
> `dart:js_interop`.** Platform access is reached only through a service
> interface.

```
lib/
  main.dart          entry point; must stay trivial
  app/               app widget, bootstrap, Riverpod providers
  core/              constants, theme, typed errors, utils
  data/              models and repositories
  services/          filesystem, language, commands, search, clipboard
  features/          one folder per feature
  shared/widgets/    reusable components
```

Each feature folder splits `presentation/` (widgets) from `application/`
(Riverpod notifiers) so UI and logic never blur together.

## The file system abstraction

`FileSystemProvider` (`services/filesystem/file_system_provider.dart`) is the
only way to touch a file. Three implementations:

| Provider | Where it runs | Ids are |
|---|---|---|
| `IoFileSystemProvider` | Android app storage, and all unit tests | absolute paths |
| `WebFileSystemProvider` | Chrome, via the File System Access API | paths relative to the picked root |
| `SafFileSystemProvider` | Android external folders, via the SAF channel | `content://` document URIs |

The right one is selected by the conditional export in
`services/filesystem/provider_factory.dart`. Never import a concrete provider
outside that file.

`ProviderCapabilities` tells the UI what a provider genuinely cannot do (SAF has
no file watcher; the browser hides absolute paths). Disable actions honestly
rather than offering a button that fails.

## Conventions

- **Errors**: throw `AppFailure` subtypes from `core/errors/failures.dart`, never
  raw `FileSystemException`. Each one carries a `message` (what happened) and a
  `hint` (what to do). The sealed hierarchy means a new failure forces every
  `switch` over failures to be updated.
- **Colours**: never write a `Color(0xFF…)` in a widget. Read
  `Theme.of(context).extension<AppColorTokens>()`. The only files with colour
  literals are `core/theme/app_palettes.dart` and `core/theme/editor_themes/*`.
- **Durations and curves**: from `core/constants/durations.dart` only.
- **Commands**: every user action is a `Command` in the `CommandRegistry`.
  Toolbars, context menus, shortcuts and the palette all invoke commands, so an
  action behaves identically wherever it is triggered.
- **Heavy work**: recursive copy, delete, size counting, search and ZIP run off
  the UI isolate (`services/filesystem/io/io_bulk_worker.dart` is the pattern).
  Web cannot use isolates for this — it yields to the event loop instead, which
  is documented in `WebFileSystemProvider`.
- **File size**: keep files under ~400 lines.
- **Adding a language**: one import plus one entry in
  `services/language/language_registry.dart`.
- **Adding an editor theme**: one file in `core/theme/editor_themes/`, one line
  in `editor_theme_registry.dart`.

## Analyzer

`analysis_options.yaml` is stricter than `flutter_lints`: `strict-casts`,
`strict-raw-types`, `strict-inference`, and `unawaited_futures` promoted to an
error (an unawaited future in file code is a write that may not have landed).

`avoid_slow_async_io` is deliberately **off**. It recommends synchronous file
I/O, which blocks the isolate; on the UI isolate that is a dropped frame.

## Known upstream issue

`re_editor` 0.10.0's `_CodeCursorBlinkController.startBlink()` schedules a
100 ms `Future.delayed` on Android and iOS that `stopBlink()` does not cancel.
Disposing an editor inside that window writes to a disposed `ValueNotifier`.
Widget tests work around it in `test/features/editor_integration_test.dart`
(`disposeEditor`).

## Where things live now

| Area | Entry point |
|---|---|
| Tabs and their lifecycle | `features/tabs/application/tabs_controller.dart` |
| Saving, auto-save, hot exit | `features/tabs/application/tab_saver.dart` |
| The live editor controllers | `features/tabs/application/tab_editor_controllers.dart` |
| Closing and reopening tabs | `features/tabs/application/tab_closer.dart` |
| Opening a file (size/binary/image guards) | `features/tabs/application/document_loader.dart` |
| Explorer tree | `features/explorer/application/tree_controller.dart` |
| File operations (move/copy/trash/undo) | `features/explorer/application/file_operations.dart` |
| Context-menu behaviour | `features/explorer/presentation/explorer_actions.dart` |
| Session persistence and restore | `features/workspace/application/session_controller.dart` |
| Settings catalogue (searchable) | `features/settings/application/settings_catalog.dart` |
| Editing actions shared by toolbar/accessory bar/shortcuts | `features/editor/application/editor_actions.dart` |
| Bottom toolbar and accessory bar | `features/editor/presentation/toolbars/` |
| Accessory key layout (persisted as tokens) | `data/models/accessory_key.dart` |
| Find and replace panel | `features/editor/presentation/find_panel.dart` |
| Go to line (parser is a pure function) | `features/editor/presentation/go_to_line_dialog.dart` |
| Selection toolbar (cut/copy/paste) | `features/editor/presentation/selection_toolbar.dart` |
| Command catalogue the shell registers | `features/commands/application/shell_commands.dart` |
| Command palette and Quick Open | `features/commands/presentation/` |
| Workspace file walk behind Quick Open | `services/search/file_indexer.dart` |
| Launcher icon sources | `android/app/src/main/res/mipmap-*` (generated) |
| Outline / Go to Symbol | `features/outline/presentation/outline_sheet.dart` |
| Workspace search and replace, and Find in Folder | `features/search/presentation/search_panel.dart` (+ `search_inputs.dart`, `search_results.dart`), `services/search/workspace_search.dart`, `services/search/search_scope.dart` |
| Hardware shortcuts (generated from the registry) | `features/commands/presentation/command_shortcuts.dart` |
| Pinch to zoom the editor font | `features/editor/presentation/pinch_zoom.dart` |
| Which lines fold, per language | `features/editor/application/fold_analyzers.dart` |
| Word completion: index, ranking, popup | `features/editor/application/word_index.dart`, `completion_prompts.dart`, `presentation/completion_popup.dart` |
| Snippets (model, store, picker) | `data/models/snippet.dart`, `data/repositories/snippets_repository.dart`, `features/snippets/` |
| Recent workspaces and files | `features/workspace/application/recents_controller.dart` |
| Line diff (pure) and its view | `services/diff/line_diff.dart`, `features/diff/presentation/diff_view.dart` |
| File history: key, policy, store | `features/history/application/history_key.dart`, `history_policy.dart`, `data/repositories/history_repository.dart` |
| App-private state files | `data/repositories/support_storage.dart` |
| Stable hash, portable relative path | `core/utils/stable_hash.dart`, `core/utils/relative_path.dart` |
| Command-driven shell actions | `features/shell/presentation/shell_editor_actions.dart`, `shell_toolbar_actions.dart` |
| Keywords harvested from a grammar | `services/language/language_keywords.dart` |
| Matching-bracket search (pure) | `services/language/bracket_matcher.dart` |
| Android SAF channel (Kotlin) | `android/app/src/main/kotlin/dev/tcode/mobile/SafPlugin.kt` |
| Reduce-motion (`AppMotion`) | `core/constants/durations.dart` |
| Edit lock (the app bar's edit toggle) | `features/editor/application/edit_lock.dart` |
| Markdown preview and its toggle | `features/viewers/presentation/markdown_preview.dart`, `features/viewers/application/preview_mode.dart` |
| JSON formatter | `services/format/json_formatter.dart` |
| Share and Open with | `services/share/` (conditional export, like the file system) |
| ZIP import and export | `services/archive/zip_service.dart` |
| What can run, and why not | `services/runner/run_target.dart` |
| Inlining a page's siblings | `services/runner/html_bundler.dart` |
| Run pane, JS harness, console | `features/runner/presentation/run_pane.dart` |
| MicroPython harness | `services/runner/python_runtime.dart` |
| Bundled MicroPython runtime (MIT) | `assets/micropython/` |
| Repository URL parsing | `services/repo/repo_source.dart` |
| Archive download (conditional export) | `services/repo/` |
| Download + unpack a repository | `features/repo/application/download_repo.dart` |
| Tokens (Android Keystore) | `data/repositories/credentials_repository.dart`, `features/accounts/` |
| HTTP seam, redirect rule | `services/git_host/http_transport.dart` (+ `_io`, `_web`, `_factory`) |
| GitHub / GitLab REST clients | `services/git_host/github_client.dart`, `gitlab_client.dart`, base in `git_host_client.dart` |
| Where a folder came from (`.tcode/`) | `data/models/repo_link.dart`, `services/git_host/repo_link_store.dart` |
| Change detection (git blob ids) | `services/git_host/git_blob_sha.dart`, `change_set.dart`, `local_snapshot.dart` |
| Pull / merge request screen | `features/change_request/` |

**Read-only is one question, asked once.** `isTabEditable(tab, locked)` in
`features/editor/application/edit_lock.dart` is what the editor, its selection
toolbar, the bottom toolbar, the accessory bar and the command catalogue all
read. Never test `tab.isReadOnly` directly in a new editing surface, or the
app bar's lock and that surface will disagree. The lock only ever *adds*
read-only: a binary, image or too-large document stays read-only with the
toggle on, and the toggle is disabled for it.

Three rules worth restating because they are easy to break:

- **Dirtiness is derived**, by comparing a tab's buffer against its `savedText`.
  Never add an `isDirty` flag — typing a character and undoing it must leave the
  tab clean.
- **Commit state before deriving from it.** `copyWith` evaluates its arguments
  against the *old* state, so `copyWith(expanded: next, rows: _flatten())`
  silently flattens the old set. Assign, then derive.

## Gestures

`re_editor` installs its own pan and long-press recognisers for scrolling and
selection, and they are *deeper* in the hit-test path than anything wrapping the
editor — so they enter each gesture arena first and win any sweep. Two
consequences, both paid for on a device:

- A `Listener` wrapped around the editor is **passive**. It sees every pointer,
  but it takes nothing away, so a pinch zoomed *and* dragged a text selection at
  the same time. Anything that must stop the editor mid-gesture has to be a real
  recogniser that calls `resolve(GestureDisposition.accepted)`.
- `GestureBinding.cancelPointer()` is not a way out: the cancel event removes the
  pointer's cached hit-test result, so the canceller stops receiving that finger
  too. Win the arena instead of cancelling.

`TwoFingerZoomRecognizer` in `features/editor/presentation/pinch_zoom.dart` is
the pattern: stay undecided while one finger is down (so taps, scrolls and
selections resolve to the editor exactly as before), and claim the gesture the
moment a second finger lands.

**Injecting a real multi-touch gesture on the emulator** is the only way to test
this end to end — `flutter drive` and widget tests have no competing
recognisers, so they pass even when the device does not. Use `sendevent` on
`/dev/input/event2` (protocol B, `ABS_MT_SLOT` 0 and 1, range 0-32767 on both
axes, `adb root` first), aim well inside the editor — not near the status strip
and never under the soft keyboard — and read the result back from
`shared_prefs/FlutterSharedPreferences.xml` rather than from a screenshot.

### Folding

`re_editor` folds already — `CodeEditor` builds a `CodeChunkController` with
`DefaultCodeChunkAnalyzer` and the gutter indicator handles the tap. Two things
follow that are easy to get wrong:

- **`collapseChunk(start, end)` hides `start + 1 … end - 1`.** A brace language
  gets that for free, because `end` is the closing brace and stays visible. An
  indented block has no closing line, so `IndentCodeChunkAnalyzer` emits a range
  that runs **one line past** the body — otherwise the last line of every folded
  block stays on screen.
- **The analyser must be a `const` singleton.** `CodeEditor.didUpdateWidget`
  disposes and recreates the chunk controller whenever `chunkAnalyzer` changes
  *identity*, so a fresh instance per build re-runs the isolate analysis every
  frame and drops every collapsed region. `analyzerFor` returns canonical
  consts and a test asserts `identical(...)`, which turns an invisible
  performance bug into a red test.

`DefaultCodeChunkAnalyzer` folds on brackets only, which is why Python and YAML
get `IndentCodeChunkAnalyzer` instead. Neither can be unit-tested end to end —
analysis runs on a spawned isolate, the same trap as search — so the fold
*ranges* are tested as a pure function and the folding itself on a device.

### Completion

`CodeAutocomplete` is a **wrapper widget**, found by
`context.findAncestorStateOfType`, not a `CodeEditor` parameter. Three things
about it are not obvious:

- **The wrapper must be mounted unconditionally.** Switching completion off by
  returning a different tree shape destroys and recreates the `CodeEditor`
  underneath, and `_CodeEditorState.initState` notifies the shared editing
  controller — which marks the status bar's `ValueListenableBuilder` dirty in
  the middle of a build. Switch the feature off inside the prompts builder
  instead, so the tree shape never changes.
- **`build` is called synchronously** while the editor handles a code change,
  and receives only the current line. Any buffer-wide index has to be built
  outside and be ready before the call.
- **Enter cannot accept a suggestion on a phone.** `re_editor` accepts on a
  `CodeShortcutNewLineIntent`, which only a hardware Enter produces; the soft
  keyboard goes through `performAction(TextInputAction.newline)` and never
  dispatches it. Rows are full-height touch targets, and no text promises Enter.

`Mode.keywords` in `re_highlight` is `dynamic` and appears in three shapes — a
space-separated `String`, a map of `List<String>`, and a map of space-separated
`String`s. The package's own `DefaultCodeAutocompletePromptsBuilder` reads only
the second, at the top level, which is why CSS and several others would yield
nothing. `harvestKeywords` walks the whole graph and accepts all three; a test
asserts every registered language produces keywords except the four that are
genuinely structural (plain text, Markdown, YAML, TOML).

### Find in Folder

VS Code's folder-scoped search: long-press a folder, "Find in Folder…". It is
the workspace search screen opened with a `SearchScope`, and the scope is
applied **at the file walk** — `IndexRoot.startId` / `startPath` — rather than by
filtering results afterwards, so it is exact and only the subtree is listed.
`startPath` keeps every `relativePath` relative to the workspace root, so scoped
results display and open exactly like unscoped ones.

**Replace-all receives the scope and must honour it.** Losing it would rewrite
files the user never saw in the results. The confirmation names the folder, and
a widget test pins that the scope reaches `onReplaceAll`.

### App-private state

Everything the app stores for itself — session, snippets, recent items, file
history — goes through `SupportStorage`, which goes through a
`FileSystemProvider` rather than `dart:io` so the same code runs on web against
the Origin Private File System. All of it is null-tolerant: storage can fail to
open, and a feature that keeps its own file must degrade rather than stop the
app starting.

Two rules that are easy to get wrong:

- **`TextFormat()` appends a trailing newline by default.** That is right for a
  source file and wrong for the app's own data. A history snapshot written with
  the default would gain a line on every round trip, so `writeTextFile` passes
  `endsWithNewline: false`.
- **`stableHash` is 32-bit arithmetic on purpose.** On the web a Dart `int` is a
  JavaScript double: a 64-bit FNV constant cannot be written as a literal at
  all (the web build fails to compile), and a 64-bit multiply silently loses
  precision. It runs two 32-bit passes and concatenates them, and does the
  multiply as shifts and adds so no intermediate exceeds 53 bits.

### File history

Snapshots are taken **before** a write, of the content about to be lost. Two
consequences, both good: the newest state already exists on disk so it is never
stored twice, and coalescing becomes a *skip* rather than a *replace* — skipping
keeps the state from before a burst of typing, which is the thing worth having.
A version's timestamp is therefore when it stopped being current, which is why
the UI says "Before 14:32".

The key is `<scheme>|<path relative to the workspace root>`, never `tab.key`:
that embeds a positional `rootIndex`, so removing a root would rename every
file's history. `meta.json` stores the full key, so a hash collision is detected
rather than silently mixing two files together.

### Accounts, private repositories, pull requests

`full` flavour only. The user pastes a personal access token under
Settings → Accounts, and it is checked with `whoAmI` before it is stored in
the Android Keystore. There is **still no git**. Everything is REST:

- **Download**: with a token, `resolveBranch` gives a SHA and the archive is
  fetched *at that SHA* through the API. That is the only route that reaches a
  private repository. Without a token, the SHA is still resolved anonymously
  (best effort) and the codeload archive is pinned to it.
- **What changed**: `.tcode/repo.json` records host/owner/name/branch/baseSha,
  and `.tcode/files` lists what was unpacked. Local files are hashed to git
  blob ids (`sha1("blob <len>\0" + bytes)`) and compared with the host's tree
  at the base commit. No baseline copy is kept. The file list matters because
  archives honour `export-ignore`: without it, a file that was never
  downloaded would look deleted, and the pull request would delete it.
- **Proposing**:
  - GitHub: blobs → tree on `base_tree` (a null sha deletes a file) → commit
    whose parent is the base → ref → pull.
  - GitLab: one `repository/commits` call with actions and `start_sha`, then
    the merge request.
  - Either host forks first when the account cannot push.

Rules that are easy to break:

- **A token never follows a redirect to another host.** `api.github.com`
  answers an archive request with a redirect to codeload. Redirects are
  followed by hand in `sendFollowingRedirects`, and `Authorization` /
  `PRIVATE-TOKEN` are dropped whenever the host changes. A test pins this.
- **Never print a token.** `TransportRequest.toString` and
  `CredentialsRepository.toString` omit it, and failure text comes from the
  host's `message`, never from headers.
- **The PR is against the downloaded commit.** The app does not pull, merge or
  rebase. If the branch moved on, the host shows the conflicts.
- **No base SHA, no proposing.** Without the base, every remote change since
  the download would read as a local revert.
- **Checked against the real hosts**: resolve, tree, archive and blob reads on
  public GitHub and GitLab repositories produce zero spurious changes. The
  write path (commit, branch, PR/MR) is covered by fake-transport tests that
  pin the exact request sequence.

## Testing traps found the hard way

- **`re_editor`'s search never resolves under `flutter_test`.** Match finding
  runs on a spawned isolate via `isolate_manager`, and the callback does not
  fire in the test environment — not a timing issue, so no amount of waiting or
  `runAsync` fixes it. Test match-count logic as a pure function
  (`matchCountLabel`) and verify live searching on a device.
- **Editors leave timers pending.** A test that mounts `CodeEditor` must tear
  the tree down inside the test body (see `disposeEditor` / `disposeShell` in
  the test files); `addTearDown` runs *after* the framework's pending-timer
  check. Pump past 1200ms if the test made an edit, so the auto-save debounce
  drains too.
- **`Semantics` does not merge with child `Text` by default.** Wrapping a row
  or key in `Semantics(label: …)` leaves the inner `Text` contributing its own
  node, so a screen reader reads the raw glyph. Add
  `container: true, excludeSemantics: true`.
- **`INTERNET` lives only in the `full` source set.** The Play release declares
  **zero** permissions, and that is a property worth protecting: it is what
  lets the app tell the user it cannot reach the network and be telling the
  truth. Anything network-shaped must be gated on `RepoDownload.isAvailable`,
  never assumed. Wording in the UI describes *behaviour* ("previews never fetch
  remote files") rather than the permission, so it stays true in both builds.
- **A Kotlin method channel must never reply with `Unit`.** A `work` lambda
  that returns nothing yields `kotlin.Unit`, and
  `StandardMessageCodec` cannot encode it — it throws on the main thread and
  kills the process. Void results go back as `null`. This crashed the app on
  every save into a SAF folder, and because it is a *native* crash there is no
  Dart stack trace and no test that can catch it: check `adb logcat` for
  `FATAL EXCEPTION` whenever the app vanishes rather than showing an error.
- **The MicroPython glue ignores `wasmBinary`.** It asserts that the option is
  unsupported. It does honour a `url` option that becomes its `locateFile`, so
  the WebAssembly is handed over as a `data:` URL — which needs no origin, and
  is what makes it work inside `loadHtmlString` with no server and no socket.
- **Never call it "Python" in the UI.** It is MicroPython: real syntax, reduced
  standard library, no third-party packages, no pip. `kPythonRuntimeLabel` and
  `kPythonRuntimeLimits` exist so that wording lives in one place.
- **A WebView reports error lines against the whole document.** The JS harness
  measures its own prelude and subtracts it, so "line 4" means line 4 of the
  user's file rather than line 44 of a wrapper they never wrote.
- **An unstyled WebView page is white.** In a dark app that is a bright slab;
  the harness sets a background explicitly.
- **`Tooltip` eats long presses.** Its default `triggerMode` is `longPress`,
  so a tooltip around a row label silently swallows the row's context-menu
  gesture — on the file name, which is exactly where people press. Use
  `TooltipTriggerMode.manual` on anything inside a long-pressable row.
- **`ZipDecoder` does not throw on garbage.** Arbitrary bytes decode to an
  *empty* archive, which reads as "imported nothing, successfully". Check the
  `PK` signature first (`looksLikeZip`).
- **`replaceAllMapped` does no `$1` expansion.** The callback's return value is
  used verbatim, so regex replace has to expand capture groups itself.
- **Never split an id on `/`.** A SAF id is a `content://` URI whose document
  part is percent-encoded, so splitting one produced breadcrumbs reading
  "%2Fnote.txt". Walk `provider.parentOf` / `provider.nameOf` instead — which
  is what the "features never parse an id" rule was always for.
- **Round-tripping a SAF URI through `Uri.replace` corrupts it.** It re-encodes
  `primary%3ACode` as `primary:Code`, which Android treats as a different
  document. `SafFileSystemProvider` does string surgery on the raw URI instead.
- **`re_editor` ships no selection toolbar.** It draws the handles and exposes
  `CodeEditor(toolbarController:)`, but supplies nothing — so cut/copy/paste is
  absent until you pass one. Anything that "should be built in" on Android is
  worth checking against the package's actual defaults.
- **`\$` inside a single-quoted Dart string is a literal, not interpolation.**
  `restoreUnsavedBuffer` looked up `'\$rootIndex:\$fileId'` and so compared
  against the eight-character literal, never matching a tab: hot-exit restore
  silently did nothing for as long as it existed. Nothing caught it because the
  method had no test at all.
- **A controller built inside `build()` can only clean up after itself.**
  `re_editor`'s selection toolbar controller owns one `OverlayEntry` and hides
  it before showing another — but only its own. `toolbarController:` was calling
  the builder on every widget build, so each new controller started with an
  empty entry, had nothing to hide, and the previous pill stayed on screen:
  selecting a few times stacked up several "Cut Copy Paste" bars. Anything that
  owns an overlay, a timer or a subscription must be cached per tab, not rebuilt
  per frame. The same shape as the `chunkAnalyzer` identity rule above.
- **The `full` flavour is a different application id.** It installs as
  `dev.tcode.mobile.full` alongside the `play` build rather than replacing it,
  so `adb install -r` of a full APK followed by launching `dev.tcode.mobile`
  silently tests the *other* build. Launch the package that matches the flavour,
  and confirm with `adb shell dumpsys package <id>`.
- **A repository host will not tell you why it refused.** GitHub answers **404
  for a private repository exactly as for a missing one**, deliberately, so an
  unauthenticated client cannot discover that a private repository exists —
  which makes `RepositoryPrivateFailure` unreachable on GitHub. GitLab is the
  mirror image: it redirects anything it will not serve to its sign-in page,
  ending 403, for a private project *and* for a mistyped name. So neither
  message may claim a single cause; both name all of them.
- **Reusing a filesystem failure for an HTTP status is a lying message.** An
  HTTP 404 from a repository host was raised as `NotFoundFailure`, whose hint is
  "refresh the explorer to see the current contents" — advice about a file on
  this device, shown when the real cause was a branch named `main` that does not
  exist on the remote. `RepositoryNotFoundFailure` and
  `RepositoryPrivateFailure` exist so the wording matches what happened.
- **`showPaletteSheet` supplies the route, not the surface.** `PaletteScaffold`
  is what draws the sheet background; a sheet that returns a bare `Column`
  renders transparently over the editor underneath. Either use the scaffold or
  draw the surface yourself.
- **A widget test needs a real app theme.** The shell reads `AppColorTokens`
  off the theme and asserts it is present, so pass `AppTheme.dark()` rather
  than Material's default.

## Testing

- Unit tests run on the Dart VM, so `IoFileSystemProvider` is tested against a
  real temp directory — no emulator needed.
- Use `test/support/harness.dart` (`pumpInApp`, `TestSizes`, `fakeSettingsRepository`)
  rather than building a `MaterialApp` by hand.
- Prefer a `reason:` on any assertion whose failure would not be self-explaining.

## The app icon

The launcher icon is the same `< >` mark the welcome screen draws, in the dark
theme's `accent` (`#4D9FFF`) on the app's surface gradient. It is **generated,
not hand-drawn**: regenerating is how you change it, so the five density buckets
can never drift apart.

- `mipmap-*/ic_launcher.png` — legacy, full-bleed rounded square (48dp base).
- `mipmap-*/ic_launcher_foreground.png` — adaptive foreground (108dp base) with
  the glyph inside the 72dp safe zone, so no launcher mask clips it.
- `mipmap-anydpi-v26/ic_launcher.xml` — adaptive icon; its `<monochrome>` layer
  is what Android 13+ themed icons tint, and the system reads only its alpha.
- `drawable/ic_launcher_background.xml` — a gradient `<shape>`, not a PNG.
- `android/app/src/main/ic_launcher-playstore.png` — the 512px Play listing art.

No `flutter_launcher_icons` dependency: one script that already ran beats a
build-time dependency carried forever for a file that changes almost never.
