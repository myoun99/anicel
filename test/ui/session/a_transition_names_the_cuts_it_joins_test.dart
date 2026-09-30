import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart'
    show createTrackTransitionLayer;
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/dialogs/instruction_event_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart'
    show FlipHudAxis;
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/instance_editor_commands.dart';
import 'package:anicel/src/ui/timeline/timeline_block_word.dart'
    show TimelineBlockText;
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

/// 🗣️F-229 (유저 2026-09-29): 「트랜지션 레이어는 대상이 확실해서 시작이름
/// 끝이름 기호이름 이런거 정할 필요가 없으니 이쪽에서 등록. OL의 경우
/// 시작이름은 대상인 이전컷, 끝이름은 대상의 다음컷임. … c301 … 이름부분은
/// 그냥 컷O.L. 일본어론 カットO.L 이렇게. 타임시트패널에도 기존 디렉션 표기
/// 규칙 통일해서 따라서 적용」.
///
/// Two 24-frame cuts, 301 and 302, and an O.L over frames 18..29.
void main() {
  Cut cut(String name) => Cut(
    id: CutId(name),
    name: name,
    duration: 24,
    canvasSize: const CanvasSize(width: 64, height: 36),
    layers: const [],
  );

  EditorSessionManager session() {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'T',
            cuts: [cut('301'), cut('302')],
          ),
        ],
      ),
    );
    s.transitions.updateTransitionInstructions({
      18: const InstructionEvent(instructionId: 'ol', length: 12),
    });
    s.selectCut(const CutId('301'));
    return s;
  }

  /// A span's writing as the rows draw it — a block word, not a Text.
  Finder blockWord(String text) => find.byWidgetPredicate(
    (widget) => widget is TimelineBlockText && widget.text == text,
  );

  InstructionEvent shownInTheCut(EditorSessionManager s) =>
      s.transitions.trackTransitionDisplayLayer.instructions.values.single;

  test('the cut\'s row shows the O.L from c301 to c302, named in the '
      'program\'s word — and nothing of it is written into the project', () {
    final s = session();
    addTearDown(s.dispose);
    final event = shownInTheCut(s);
    expect(event.valueA, 'c301');
    expect(event.valueB, 'c302');
    expect(event.text, AppText.strings.tlTransitionCutOl);

    final stored = s.activeTrack.transitionLayer.instructions[18]!;
    expect(stored.text, isNull);
    expect(stored.valueA, isNull);
    expect(stored.valueB, isNull);
  });

  test('the row is the same instance while nothing under it changes; a '
      'rename next door is read at once', () {
    final s = session();
    addTearDown(s.dispose);
    final first = s.transitions.trackTransitionDisplayLayer;
    expect(
      identical(s.transitions.trackTransitionDisplayLayer, first),
      isTrue,
      reason: 'the identity-keyed row memos downstream hold',
    );

    s.selectCut(const CutId('302'));
    s.cutVerbs.renameActiveCut('305');
    s.selectCut(const CutId('301'));
    expect(shownInTheCut(s).valueB, 'c305');
  });

  group('the sheet', () {
    TimesheetDocument printed(WidgetTester tester) {
      final paint = tester.widget<CustomPaint>(
        find.byKey(const ValueKey<String>('timesheet-playhead-overlay')),
      );
      return (paint.painter! as TimesheetPlayheadPainter).document;
    }

    /// The printed transition column's first span: its start cell and its
    /// end cell.
    ({TimesheetCell start, TimesheetCell end}) olCells(
      TimesheetDocument document,
      EditorSessionManager s,
    ) {
      final column = document.columns.firstWhere(
        (column) => column.layerId == s.activeTrack.transitionLayer.id,
      );
      final start = column.cells.indexWhere(
        (cell) => cell.kind == TimesheetCellKind.instructionStart,
      );
      final cell = column.cells[start];
      return (start: cell, end: column.cells[start + cell.spanLength! - 1]);
    }

    testWidgets('prints the O.L the direction way — c301 at its start, c302 '
        'at its end — in the NOTATION language\'s word', (tester) async {
      final s = session();
      addTearDown(s.dispose);
      s.setLanguageSettings(
        s.languageSettings.value.copyWith(
          programLanguage: AppLanguage.en,
          notationLanguage: AppLanguage.ja,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimesheetTabHost(
              session: s,
              continuous: false,
              onContinuousChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cells = olCells(printed(tester), s);
      expect(cells.start.label, 'カットO.L');
      expect(cells.start.valueA, 'c301');
      expect(cells.end.valueB, 'c302');

      s.selectCut(const CutId('302'));
      s.cutVerbs.renameActiveCut('305');
      s.selectCut(const CutId('301'));
      await tester.pumpAndSettle();
      expect(
        olCells(printed(tester), s).end.valueB,
        'c305',
        reason: 'a rename next door reprints the sheet of the cut it joins',
      );
    });
  });

  testWidgets('the term window of an O.L asks for no names — it previews the '
      'cuts\' and writes none', (tester) async {
    final s = session();
    addTearDown(s.dispose);
    // Writing typed into it before the names were the cuts' — the window
    // hands none of it back, so the first edit leaves the span clean.
    s.transitions.updateTransitionInstructions({
      18: const InstructionEvent(
        instructionId: 'ol',
        length: 12,
        text: 'typed',
        valueA: 'A',
        valueB: 'B',
      ),
    });
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (inner) {
              context = inner;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    final editing = editTransitionSpanInstance(context, s, globalFrame: 20);
    await tester.pumpAndSettle();

    for (final field in [
      'instruction-text-field',
      'instruction-value-a-field',
      'instruction-value-b-field',
    ]) {
      expect(find.byKey(ValueKey<String>(field)), findsNothing);
    }
    expect(
      find.byKey(const ValueKey<String>('instruction-memo-field')),
      findsOneWidget,
    );
    expect(blockWord('c301'), findsWidgets, reason: 'the preview names it');

    await tester.enterText(
      find.byKey(const ValueKey<String>('instruction-memo-field')),
      'slow',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-ok-button')),
    );
    await tester.pumpAndSettle();
    await editing;

    final stored = s.activeTrack.transitionLayer.instructions[18]!;
    expect(stored.memo, 'slow');
    expect(stored.text, isNull);
    expect(stored.valueA, isNull);
    expect(stored.valueB, isNull);
  });

  testWidgets('the storyboard\'s transition strip writes the same names', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const trackId = TrackId('t');
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          initialProject: Project(
            id: const ProjectId('p'),
            name: 'P',
            createdAt: DateTime.utc(2026),
            tracks: [
              Track(
                id: trackId,
                name: 'T',
                cuts: [cut('301'), cut('302')],
                transitionLayer: createTrackTransitionLayer(trackId).copyWith(
                  instructions: {
                    18: const InstructionEvent(instructionId: 'ol', length: 12),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();

    final strip = find.byKey(
      ValueKey<String>('storyboard-transition-row-${trackId.value}'),
    );
    for (final end in ['c301', 'c302']) {
      expect(
        find.descendant(of: strip, matching: blockWord(end)),
        findsOneWidget,
      );
    }

    // The flip window reads the storyboard's rows: the span carries the
    // same name there.
    final snapshot = tester
        .widget<StoryboardPanel>(find.byType(StoryboardPanel))
        .rowsChannel!
        .snapshotFor(FlipHudAxis.row)!;
    expect(
      snapshot.rows
          .firstWhere((row) => row.kind == LayerKind.transition)
          .runs
          .single
          .label,
      AppText.strings.tlTransitionCutOl,
    );
  });

  test('a drag of the row shows its form in the cut named too — the hand '
      'never sees the names drop out', () {
    final s = session();
    addTearDown(s.dispose);
    final dragged = s.activeTrack.transitionLayer.copyWith(
      instructions: {
        17: const InstructionEvent(instructionId: 'ol', length: 12),
      },
    );
    final shown = s.transitions
        .previewFormsOf(dragged)
        .shown
        .instructions
        .values
        .single;
    expect(shown.valueA, 'c301');
    expect(shown.valueB, 'c302');
  });

  testWidgets('a direction\'s window still asks for its names — its ends are '
      'what the camera does, which nothing on the track can know', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InstructionEventDialog(
            instructionSet: CameraInstructionSet.standard,
            initialInstructionId: 'pan',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final field in [
      'instruction-text-field',
      'instruction-value-a-field',
      'instruction-value-b-field',
    ]) {
      expect(find.byKey(ValueKey<String>(field)), findsOneWidget);
    }
  });
}
