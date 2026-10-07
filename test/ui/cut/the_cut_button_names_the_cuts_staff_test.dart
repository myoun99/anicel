import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/cut_command_group.dart';
import 'package:anicel/src/ui/dialogs/cut_settings_window.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️유저 09-25 (project-settings-window): the work's settings carry each
/// stage's name, a cut's settings the cut's own — 「작품 설정에는 기본값,
/// 컷 설정에는 컷별 이름」. The cut button's 「컷 설정…」 shows the work's
/// names faintly where the cut names nobody, and what is typed there is the
/// cut's.
void main() {
  const key = LayerMark(process: LayerProcess.key);
  const keyDirector = LayerMark(
    process: LayerProcess.key,
    revise: LayerRevise.animationDirector,
  );

  Future<EditorSessionManager> pumpCutButton(WidgetTester tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.updateTimesheetInfo(
      session.timesheetInfo.withStaffName(key, 'Work Genga'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: CutCommandGroup(session: session)),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('cut-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('cut-settings-button')));
    await tester.pumpAndSettle();
    return session;
  }

  Finder fieldOf(LayerMark mark) =>
      find.byKey(ValueKey<String>('cut-settings-staff-${mark.keySlug}'));

  testWidgets('컷 설정 shows the work\'s name faintly in an empty field, and a '
      'name typed there is the cut\'s own — one undo takes it back', (
    tester,
  ) async {
    final session = await pumpCutButton(tester);
    expect(
      find.byKey(const ValueKey<String>('cut-settings-window')),
      findsOneWidget,
    );
    expect(
      fieldOf(const LayerMark(process: LayerProcess.paper)),
      findsNothing,
      reason: '용지라는 스태프는 없음 (유저 2026-10-05, F-291)',
    );
    final field = tester.widget<TextField>(fieldOf(key));
    expect(field.controller!.text, isEmpty, reason: 'the cut names nobody');
    expect(field.decoration!.hintText, 'Work Genga');

    await tester.enterText(fieldOf(key), 'Cut Genga');
    await tester.tap(
      find.byKey(const ValueKey<String>('cut-settings-save-button')),
    );
    await tester.pumpAndSettle();

    final cut = session.activeCutOrNull!;
    expect(cut.metadata.staffNameFor(key), 'Cut Genga');
    expect(
      session.timesheetInfo.staffNameForCut(cut.metadata, key),
      'Cut Genga',
      reason: 'the forms print the cut\'s name over the work\'s',
    );
    expect(
      session.timesheetInfo.staffNameFor(key),
      'Work Genga',
      reason: 'the work keeps its own',
    );

    session.undo();
    // The playback warm-up the edit woke yields a frame at a time.
    await tester.pumpAndSettle();
    expect(session.activeCutOrNull!.metadata.staffNameFor(key), isEmpty);
  });

  testWidgets('saving gives back only the stages whose names changed; a '
      'cancel gives back nothing', (tester) async {
    Map<LayerMark, String>? answer;
    var answered = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              answer = await showDialog<Map<LayerMark, String>>(
                context: context,
                builder: (_) => CutSettingsWindow(
                  cutStaff: {key.keySlug: 'Cut Genga'},
                  workStaff: {key.keySlug: 'Work Genga'},
                ),
              );
              answered = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(fieldOf(key)).controller!.text,
      'Cut Genga',
      reason: 'the cut\'s own name, not the work\'s',
    );
    await tester.enterText(fieldOf(keyDirector), 'Sakkan');
    await tester.tap(
      find.byKey(const ValueKey<String>('cut-settings-save-button')),
    );
    await tester.pumpAndSettle();
    expect(answered, isTrue);
    expect(answer, {keyDirector: 'Sakkan'});

    answered = false;
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldOf(key), '');
    await tester.tap(
      find.byKey(const ValueKey<String>('cut-settings-cancel-button')),
    );
    await tester.pumpAndSettle();
    expect(answered, isTrue);
    expect(answer, isNull);
  });
}
