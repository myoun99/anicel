import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/dialogs/autosave_settings_section.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🚨★★★**WHAT THE APP KEEPS OUTSIDE YOUR PROJECT FILE, VISIBLE.**
///
/// 유저 2026-08-30 believed this already existed — 「설정에서 어차피 앱
/// 컨테이너 파일 볼수있게 되있으니까 **안되있으면 되있도록**하고 그거
/// 유념」 — and it was half true. Recovery snapshots had a list; the
/// settings files, the brush tips, the conformed audio and the media
/// staged by 품기 had none, so a person deciding whether to let imports
/// live there could not see what was there already. The list is gone with
/// the snapshots and this block is the whole answer now.
void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
  });

  // ⚠️A closure, not `session.dispose` — a tear-off is evaluated when the
  // tear-down is REGISTERED, which is before setUp has made the session.
  tearDown(() => session.dispose());

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AutosaveSettingsSection(session: session),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('every tenant of the container has a row, not just the one '
      'that had a list', (tester) async {
    await pumpSection(tester);

    // ⚠️By KEY, not by text: a row's label is localized, and a test that
    // matched words would be pinning the English rather than the row.
    for (final id in [
      // 🪦`brush-tips` was a row of its own while it was a folder sitting
      // beside the loose settings files at the container root. Both are
      // under `Settings/` now, and the settings row measures that tree —
      // two rows over one tree would double-count the total this block
      // exists to be trusted for.
      'settings',
      // 🪦`recovery` and `conformed` were here. Nothing writes either folder
      // any more — the tick saves the project file, and a conform waits in
      // the run's room until the next save absorbs it — so their rows would
      // report 0 for ever, which reads as 「none are kept」 rather than
      // 「that folder is retired」.
      'session-scratch',
      // 🚨Kilobytes, and a row anyway: the total below claims to be the
      // WHOLE container, and this is the last thing in it that is not one
      // of the two rooms.
      'diagnostics',
    ]) {
      expect(
        find.byKey(ValueKey<String>('settings-container-$id')),
        findsOneWidget,
        reason: '"$id" is part of the container and must be shown',
      );
    }
  });

  testWidgets('and a total, so the answer to「how much」is one number', (
    tester,
  ) async {
    await pumpSection(tester);
    expect(find.text(AppText.strings.containerTotal), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('settings-container-total')),
      findsOneWidget,
    );
  });

  testWidgets('⛔the rows are always there, empty folders included', (
    tester,
  ) async {
    // 없다가 생기는 UI 금지: a folder the app has never written to must
    // still have its row, or the block would grow and shrink between runs
    // and a person could not tell「nothing there」from「not shown」.
    await pumpSection(tester);
    expect(
      find.byKey(const ValueKey<String>('settings-container-session-scratch')),
      findsOneWidget,
      reason:
          'the session room may well be empty on a fresh install — that is '
          'a state to show, not a reason to hide the row',
    );
    expect(
      find.text(AppText.strings.containerAreaSessionScratch),
      findsOneWidget,
      reason: 'and it is named in the reader\'s language',
    );
  });
}
