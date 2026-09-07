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
/// live there could not see what was there already.
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

    // ⚠️By KEY, not by text: the recovery row deliberately repeats the
    // heading above it (the block accounts for the whole container, so
    // leaving a tenant out would make the total wrong), and two widgets
    // with the same words cannot be told apart by their words.
    for (final id in [
      'settings',
      'brush-tips',
      'recovery',
      // 🪦`conformed` was here. Nothing writes that folder any more — a
      // conform waits in the run's room and moves into the project at the
      // next save — so its row would report 0 for ever, which reads as
      // 「no conforms are kept」 rather than 「that folder is retired」.
      'session-scratch',
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
