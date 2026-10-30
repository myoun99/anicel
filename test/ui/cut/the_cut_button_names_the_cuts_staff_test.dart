import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/cut_command_group.dart';
import 'package:anicel/src/ui/dialogs/cut_settings_window.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🗣️유저 2026-10-08 (F-291-Q1): 「원화 작업자나 시아게는 컷마다 다름 …
/// 스태프는 콘티만 남겨둠. 나머진 삭제. 나머진 컷마다 스태프설정」. The cut
/// button's 「컷 설정」 names every stage but the conte's — the work's — and
/// what is typed there is the cut's.
///
/// 🗣️유저 2026-10-28 (F-291): 「컷 설정의 미술 항목 전부 삭제 … 항목들
/// 기본적으로 접힌상태이도록. 디폴트가. 러프원화만 열린상태로. 이런
/// 접힘/펼침상태는 컷별로 기억」 · F-291-Q4 「파일에, 저장 버튼을 누를 때만」.
///
/// ↩️It showed the work's names faintly where the cut named nobody (09-25:
/// 「작품 설정에는 기본값, 컷 설정에는 컷별 이름」).
void main() {
  const key = LayerMark(process: LayerProcess.key);
  const keyDirector = LayerMark(
    process: LayerProcess.key,
    revise: LayerRevise.animationDirector,
  );
  const roughKey = LayerMark(process: LayerProcess.roughKey);

  Future<void> openCutSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('cut-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('cut-settings-button')));
    await tester.pumpAndSettle();
  }

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
    await openCutSettings(tester);
    return session;
  }

  Finder fieldOf(LayerMark mark) =>
      find.byKey(ValueKey<String>('cut-settings-staff-${mark.keySlug}'));

  Finder foldOf(LayerProcess process) =>
      find.byKey(ValueKey<String>('cut-settings-process-${process.jsonValue}'));

  /// Taps [target] once the window has scrolled it into view.
  Future<void> tapInView(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Opens or shuts [process]'s fold, by its head.
  Future<void> toggleFold(WidgetTester tester, LayerProcess process) =>
      tapInView(
        tester,
        find
            .descendant(of: foldOf(process), matching: find.byType(InkWell))
            .first,
      );

  Future<void> save(WidgetTester tester) => tapInView(
    tester,
    find.byKey(const ValueKey<String>('cut-settings-save-button')),
  );

  Future<void> cancel(WidgetTester tester) => tapInView(
    tester,
    find.byKey(const ValueKey<String>('cut-settings-cancel-button')),
  );

  testWidgets('컷 설정 folds every stage but the conte\'s, 美術\'s and '
      '用紙\'s, and a name typed there is the cut\'s own — one undo takes it '
      'back', (tester) async {
    final session = await pumpCutButton(tester);
    expect(
      find.byKey(const ValueKey<String>('cut-settings-window')),
      findsOneWidget,
    );
    for (final process in LayerProcess.values) {
      expect(
        foldOf(process),
        switch (process) {
          LayerProcess.conte || LayerProcess.art || LayerProcess.paper =>
            findsNothing,
          _ => findsOneWidget,
        },
        reason:
            '${process.jsonValue}: the conte is the work\'s, 美術 and 用紙 '
            'nobody\'s',
      );
    }
    // Every fold opened: each holds its worker and the corrections it takes.
    for (final process in LayerProcess.values) {
      if (process != LayerProcess.roughKey &&
          foldOf(process).evaluate().isNotEmpty) {
        await toggleFold(tester, process);
      }
    }
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
        reason: mark.keySlug,
      );
    }
    final field = tester.widget<TextField>(fieldOf(key));
    expect(field.controller!.text, isEmpty, reason: 'the cut names nobody');

    await tester.ensureVisible(fieldOf(key));
    await tester.enterText(fieldOf(key), 'Cut Genga');
    await save(tester);

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

  testWidgets('its folds open on the rough key\'s alone at first — every '
      'other shut', (tester) async {
    await pumpCutButton(tester);
    expect(fieldOf(roughKey), findsOneWidget);
    for (final process in [
      LayerProcess.layout,
      LayerProcess.key,
      LayerProcess.inbetween,
      LayerProcess.finish,
    ]) {
      expect(foldOf(process), findsOneWidget, reason: 'fixture');
      expect(
        fieldOf(LayerMark(process: process)),
        findsNothing,
        reason: '${process.jsonValue} shut',
      );
    }
  });

  testWidgets('the folds are the cut\'s as 저장 last left them; a cancel '
      'keeps what was saved', (tester) async {
    final session = await pumpCutButton(tester);
    await toggleFold(tester, LayerProcess.key);
    await toggleFold(tester, LayerProcess.roughKey);
    await save(tester);
    expect(session.activeCutOrNull!.metadata.openStaffFolds, {
      LayerProcess.key,
    });

    await openCutSettings(tester);
    expect(fieldOf(key), findsOneWidget, reason: 'opens as it was saved');
    expect(fieldOf(roughKey), findsNothing);

    await toggleFold(tester, LayerProcess.layout);
    await cancel(tester);
    expect(session.activeCutOrNull!.metadata.openStaffFolds, {
      LayerProcess.key,
    }, reason: 'a cancel remembers nothing');

    await openCutSettings(tester);
    expect(
      fieldOf(const LayerMark(process: LayerProcess.layout)),
      findsNothing,
    );
  });

  testWidgets('saving gives back only the stages whose names changed, with '
      'the folds; a cancel gives back nothing', (tester) async {
    CutSettingsSave? answer;
    var answered = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              answer = await showDialog<CutSettingsSave>(
                context: context,
                builder: (_) => CutSettingsWindow(
                  cut: const CutMetadata().withStaffName(key, 'Cut Genga'),
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
    await toggleFold(tester, LayerProcess.key);
    expect(
      tester.widget<TextField>(fieldOf(key)).controller!.text,
      'Cut Genga',
      reason: 'the cut\'s own name',
    );
    await tester.ensureVisible(fieldOf(keyDirector));
    await tester.enterText(fieldOf(keyDirector), 'Sakkan');
    await save(tester);
    expect(answered, isTrue);
    expect(answer?.names, {keyDirector: 'Sakkan'});
    expect(answer?.openFolds, {LayerProcess.roughKey, LayerProcess.key});

    answered = false;
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldOf(roughKey), '');
    await cancel(tester);
    expect(answered, isTrue);
    expect(answer, isNull);
  });

  testWidgets('I-82 (10-31): a cut\'s camera room moved to the conte format '
      'window — 컷 설정 keeps no row of it', (tester) async {
    await pumpCutButton(tester);
    expect(
      find.byKey(const ValueKey<String>('cut-settings-window')),
      findsOneWidget,
    );
    expect(find.text(AppText.strings.conteCameraRoom), findsNothing);
  });
}
