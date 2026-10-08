import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/cut_command_group.dart';
import 'package:anicel/src/ui/dialogs/cut_settings_window.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️유저 2026-10-08 (F-291-Q1): 「원화 작업자나 시아게는 컷마다 다름 …
/// 스태프는 콘티만 남겨둠. 나머진 삭제. 나머진 컷마다 스태프설정」. The cut
/// button's 「컷 설정…」 names every stage but the conte's — the work's — and
/// what is typed there is the cut's.
///
/// ↩️It showed the work's names faintly where the cut named nobody (09-25:
/// 「작품 설정에는 기본값, 컷 설정에는 컷별 이름」).
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

  testWidgets('컷 설정 names every stage but the conte\'s, and a name typed '
      'there is the cut\'s own — one undo takes it back', (tester) async {
    final session = await pumpCutButton(tester);
    expect(
      find.byKey(const ValueKey<String>('cut-settings-window')),
      findsOneWidget,
    );
    for (final mark in everyLayerMark()) {
      final process = mark.process;
      if (process == null) {
        continue;
      }
      expect(
        fieldOf(mark),
        staffHolderOf(process) == StaffHolder.cut
            ? findsOneWidget
            : findsNothing,
        reason: '${mark.keySlug}: the conte is the work\'s, 用紙 nobody\'s',
      );
    }
    final field = tester.widget<TextField>(fieldOf(key));
    expect(field.controller!.text, isEmpty, reason: 'the cut names nobody');

    await tester.enterText(fieldOf(key), 'Cut Genga');
    await tester.tap(
      find.byKey(const ValueKey<String>('cut-settings-save-button')),
    );
    await tester.pumpAndSettle();

    expect(session.activeCutOrNull!.metadata.staffNameFor(key), 'Cut Genga');
    expect(
      session.timesheetInfo.staffNameFor(key),
      isEmpty,
      reason: 'the work keeps no 原画',
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
                builder: (_) =>
                    CutSettingsWindow(cutStaff: {key.keySlug: 'Cut Genga'}),
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
      reason: 'the cut\'s own name',
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
