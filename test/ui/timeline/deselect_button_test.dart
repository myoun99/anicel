import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/session/range_selections.dart';
import '../../helpers/app_icon_button_probe.dart';
import 'timeline_cell_probe.dart';

/// deselect-button — **the tablet's Esc.** 유저: 「선택해제 버튼 (태블릿엔
/// 키보드가 없다)」.
///
/// 🗣️IT LETS GO OF THE SELECTION TOOL'S SELECTION AND NOTHING ELSE (유저
/// 2026-10-14, I-40): 「선택해제 버튼/기능은 대상은 오직 선택도구의
/// 선택한것만이야. 프레임이나 레이어 선택범위 작동한건 대상이아니야」 — the
/// button, and the key it wears. A tap on the timeline lets go of the
/// timeline's selections (T10), and of nothing on the artwork (F-86).
///
/// 🚨THERE IS ONE OF IT (유저 2026-08-27: 「선택해제 타임라인에 중복으로
/// 존재하는거」). For one round there were two — this rail button letting go of
/// the marquee, a `shared-deselect-button` on the timeline pill letting go of
/// the timeline's selections — both called 선택 해제, both wearing
/// `Icons.deselect`. ↩️The pill's went and, until 10-14, its half was poured
/// into this one: it let go of all five kinds, and so did every tap on the
/// timeline.
/// The collaborator whose `clearTimelineSelections` the timeline's tap runs —
/// named so `tool/mutation_run.dart` has a suite to run for it.
RangeSelections rangeSelectionsOf(EditorSessionManager session) =>
    session.rangeSelections;

void main() {
  const button = ValueKey<String>('rail-deselect-button');

  Future<EditorSessionManager> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
  }

  CanvasSelectionCommands marqueeOf(WidgetTester tester) => tester
      .widget<EditorWorkspace>(find.byType(EditorWorkspace))
      .canvasSelectionCommands!;

  /// A marquee on the artwork. ⚠️Pumped, not settled, from here on: a
  /// marquee's ants never settle.
  ///
  /// ⚠️`idle` before the pump: the selection's news is microtask-deferred
  /// (`notifySessionChanged`), and with no frame already due a pump alone
  /// delivers it without building what it changed.
  Future<void> drawMarquee(WidgetTester tester) async {
    marqueeOf(tester).setRegion(
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 0, top: 0, right: 8, bottom: 8),
      ),
    );
    await tester.idle();
    await tester.pump();
    expect(marqueeOf(tester).region, isNotNull, reason: '⛔premise');
  }

  /// Frames 0–2 of the first row, swept.
  Future<void> sweepFrames(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    session.updateFrameRangeSelectionDrag(
      layerId: session.layers.first.id,
      anchorIndex: 0,
      headIndex: 2,
    );
    await tester.pump();
    expect(session.frameRangeSelection.value, isNotNull, reason: '⛔premise');
  }

  Future<void> pressCtrlD(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('it is there and DIM with nothing selected', (tester) async {
    await pump(tester);

    final finder = find.byKey(button);
    expect(
      finder,
      findsOneWidget,
      reason: '⛔없다가 생기는 UI 금지 — it is dimmed, never absent',
    );
    expect(
      tester.appIconButton(finder).onPressed,
      isNull,
      reason: 'nothing to let go of',
    );
  });

  testWidgets('a marquee lights it, and pressing it lets go of the marquee '
      'and nothing else — the playhead stays', (tester) async {
    final session = await pump(tester);
    await drawMarquee(tester);
    expect(
      tester.appIconButton(find.byKey(button)).onPressed,
      isNotNull,
      reason: 'T25: it lights on the same question its press runs',
    );

    await tester.tap(find.byKey(button));
    await tester.pump();

    expect(marqueeOf(tester).region, isNull);
    expect(
      session.currentFrameIndex,
      0,
      reason: 'and it ONLY lets go — the playhead is where it was, which is '
          'the whole reason a button exists instead of a tap somewhere',
    );
  });

  testWidgets('🎯a timeline selection does not light it, and the press that '
      'lets go of a marquee leaves the timeline\'s selection where it is', (
    tester,
  ) async {
    final session = await pump(tester);
    await sweepFrames(tester, session);
    expect(
      tester.appIconButton(find.byKey(button)).onPressed,
      isNull,
      reason: '⛔a frame selection is not its to let go of',
    );

    session.rowSelectionVerbs.beginRowSelection(session.currentRow);
    await tester.pump();
    expect(session.rowSelection.value, isNotEmpty, reason: '⛔premise');
    expect(
      tester.appIconButton(find.byKey(button)).onPressed,
      isNull,
      reason: '⛔nor a row selection',
    );

    await sweepFrames(tester, session);
    await drawMarquee(tester);
    await tester.tap(find.byKey(button));
    await tester.pump();
    expect(marqueeOf(tester).region, isNull);
    expect(session.frameRangeSelection.value, isNotNull);
  });

  testWidgets('🎯its key is the same: Ctrl+D lets go of the marquee and '
      'leaves the timeline\'s selection', (tester) async {
    final session = await pump(tester);
    await sweepFrames(tester, session);
    await drawMarquee(tester);

    await pressCtrlD(tester);

    expect(marqueeOf(tester).region, isNull);
    expect(session.frameRangeSelection.value, isNotNull);
  });

  testWidgets('🎯a tap on the timeline lets go of the timeline\'s selection '
      'and leaves the marquee (T10 · F-86)', (tester) async {
    final session = await pump(tester);
    await sweepFrames(tester, session);
    await drawMarquee(tester);

    // INSIDE the swept frames: the press keeps them — it could be the start
    // of a move — and it is the release, the press settling as a tap, that
    // lets them go.
    await tester.tapAt(
      timelineCellCenter(tester, session.layers.first.id.value, 1),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(session.frameRangeSelection.value, isNull);
    expect(marqueeOf(tester).region, isNotNull);
  });
}
