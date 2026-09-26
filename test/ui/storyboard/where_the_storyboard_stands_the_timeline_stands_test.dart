import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';

import '../../helpers/conte_track_fixture.dart';
import '../../helpers/device_viewport.dart';
import '../../helpers/home_page_probes.dart';

/// 🗣️F-187 (유저 2026-09-26) — WHERE THE STORYBOARD STANDS, THE TIMELINE
/// STANDS:
///
/// > 「se행에 선다던가 컷에 선다던가. 다 로컬인 타임라인패널에 반영?
/// > 통일되도록. 컷에서면 콘티레이어가 있다면 콘티레이어에 서도록」 ·
/// > 「컷에설때 콘티레이어가 없다면 마지막에 선 레이어 그냥 그대로둠. 아무것도
/// > 안하고. 콘티패널에서 s1행선택하고 컷선택하면 마지막선택한행인 s1행에만
/// > 서있으면됨」
///
/// Through the app: the storyboard's doors that change where it stands — a
/// cell's press, a label's, the ↑/↓ walk — and where the TIMELINE stands
/// after each (its row, and the layer it draws on). [conteTrackProject]:
/// cut-1 (0..12) has a conte row, cut-2 (15..25) has none, a gap between
/// them, and S1 is the track's.
void main() {
  const conteId = LayerId('cut-1-conte');
  const cut1 = CutId('cut-1');
  const cut2 = CutId('cut-2');

  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  /// The storyboard in front, and the TIMELINE standing on cut-1's cel.
  Future<EditorSessionManager> pumpStoryboard(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: conteTrackProject())),
    );
    await tester.pumpAndSettle();
    await showStoryboardPanel(tester);
    final session = sessionOf(tester);
    session.selectCut(cut1);
    session.selectLayer(conteCelId);
    await tester.pumpAndSettle();
    return session;
  }

  /// A point on S1's cells over [globalFrame].
  Offset sRowPoint(WidgetTester tester, int globalFrame) {
    final row = find.byKey(const ValueKey<String>('storyboard-se-row-0-1'));
    final pixelsPerFrame = tester
        .widget<StoryboardPanel>(find.byType(StoryboardPanel))
        .pixelsPerFrame;
    return tester.getTopLeft(row) +
        Offset(
          (globalFrame + 0.5) * pixelsPerFrame,
          tester.getSize(row).height / 2,
        );
  }

  Future<void> press(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.pumpAndSettle();
  }

  Future<void> tapKeyed(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pumpAndSettle();
  }

  Future<void> standOnS1ByItsLabel(WidgetTester tester) =>
      tapKeyed(tester, 'storyboard-se-label-${conteTrackId.value}-1');

  /// Where the TIMELINE stands: the layer it draws on, and its row.
  void expectTimelineOn(
    EditorSessionManager session,
    LayerId layerId, {
    required String reason,
  }) {
    expect(session.activeLayerId, layerId, reason: reason);
    expect(
      session.standing.timelineStandingRow,
      LayerRowAddress(layerId),
      reason: reason,
    );
  }

  group('an S row', () {
    testWidgets('stood on by its label is the timeline\'s row too', (
      tester,
    ) async {
      final session = await pumpStoryboard(tester);

      await standOnS1ByItsLabel(tester);

      expect(session.storyboardStandingRow, const LayerRowAddress(conteSeId));
      expectTimelineOn(
        session,
        conteSeId,
        reason: '「se행에 선다 … 다 로컬인 타임라인패널에 반영」',
      );
      expect(
        session.workingPanel,
        WorkingPanel.storyboard,
        reason: 'the seat is the program\'s: the storyboard is still the '
            'panel being worked in',
      );
    });

    testWidgets('pressed in ANOTHER cut keeps the timeline on it, in the cut '
        'the press landed in', (tester) async {
      final session = await pumpStoryboard(tester);

      await press(tester, sRowPoint(tester, 21));

      expect(session.activeCutId, cut2, reason: 'premise: into cut-2');
      expectTimelineOn(
        session,
        conteSeId,
        reason: 'the cut switch would have landed on cut-2\'s own row',
      );
    });

    testWidgets('pressed in the GAP parks, and seats nothing — no cut shows '
        'a row there', (tester) async {
      final session = await pumpStoryboard(tester);
      final parked = EditorSessionManager(initialProject: conteTrackProject());
      addTearDown(parked.dispose);
      parked
        ..selectCut(cut1)
        ..selectLayer(conteCelId)
        ..selectGlobalFrame(13);

      await press(tester, sRowPoint(tester, 13));

      expect(session.activeCutOrNull, isNull, reason: 'the gap parks');
      expect(session.storyboardStandingRow, const LayerRowAddress(conteSeId));
      expect(
        session.activeLayerId,
        parked.activeLayerId,
        reason: 'where a plain park leaves the layer',
      );
    });
  });

  group('a cut', () {
    testWidgets('with a conte row, pressed, stands the timeline on its conte '
        'row', (tester) async {
      final session = await pumpStoryboard(tester);
      await standOnS1ByItsLabel(tester);

      await tapStoryboardCutBlock(tester, 'cut-1');

      expect(
        session.storyboardStandingRow,
        const TrackRowAddress(conteTrackId),
      );
      expectTimelineOn(
        session,
        conteId,
        reason: '「컷에서면 콘티레이어가 있다면 콘티레이어에 서도록」',
      );
    });

    testWidgets('with NO conte row, pressed, keeps the layer you stood on — '
        'S1, which it shows too', (tester) async {
      final session = await pumpStoryboard(tester);
      await standOnS1ByItsLabel(tester);

      await tapStoryboardCutBlock(tester, 'cut-2');

      expect(session.activeCutId, cut2, reason: 'premise');
      expectTimelineOn(
        session,
        conteSeId,
        reason: '「s1행선택하고 컷선택하면 마지막선택한행인 s1행에만 '
            '서있으면됨」',
      );
    });

    testWidgets('with NO conte row and not the layer you stood on — nothing '
        'is done, and the cut lands where a cut switch lands', (tester) async {
      final session = await pumpStoryboard(tester);
      final reference = EditorSessionManager(
        initialProject: conteTrackProject(),
      );
      addTearDown(reference.dispose);
      reference
        ..selectCut(cut1)
        ..selectLayer(conteCelId)
        ..selectCut(cut2);

      await tapStoryboardCutBlock(tester, 'cut-2');

      expect(session.activeCutId, cut2, reason: 'premise');
      expect(
        session.activeLayerId,
        reference.activeLayerId,
        reason: '「아무것도 안하고」 — cut-1\'s cel is not a row of cut-2',
      );
    });

    testWidgets('stood on by the V row\'s label is the same stand', (
      tester,
    ) async {
      final session = await pumpStoryboard(tester);
      await standOnS1ByItsLabel(tester);

      await tapKeyed(tester, 'storyboard-track-select-${conteTrackId.value}');

      expect(
        session.storyboardStandingRow,
        const TrackRowAddress(conteTrackId),
      );
      expectTimelineOn(
        session,
        conteId,
        reason: 'the V label names the cut the playhead is in',
      );
    });
  });

  testWidgets('the ↑/↓ walk is standing too', (tester) async {
    final session = await pumpStoryboard(tester);
    await tapStoryboardCutBlock(tester, 'cut-1');
    expectTimelineOn(session, conteId, reason: 'premise');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(session.storyboardStandingRow, const LayerRowAddress(conteSeId));
    expectTimelineOn(session, conteSeId, reason: 'up from the V row: S1');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      session.storyboardStandingRow,
      const TrackRowAddress(conteTrackId),
    );
    expectTimelineOn(session, conteId, reason: 'back on the cut: its conte row');
  });

  group('the conte preview\'s cells stand on a cut by the same answer', () {
    Future<EditorSessionManager> pumpConte(WidgetTester tester) async {
      final session = EditorSessionManager(
        initialProject: conteTrackProject(),
      );
      addTearDown(session.dispose);
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConteTabHost(
              session: session,
              thumbnails: null,
              // Document space = screen space, one for one (the conte
              // panel's own tests do the same).
              viewport: seedFromRender(tester, CanvasViewport()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return session;
    }

    Future<void> pressCellOf(
      WidgetTester tester,
      EditorSessionManager session,
      CutId cut,
    ) async {
      final pages = layoutConteSheet(
        buildConteSheetSource(session.repository.requireProject()),
        metrics: ConteSheetMetrics(
          cameraAspect: session.camera.cameraFrameAspect,
        ),
      );
      final cell = pages.first.cells.firstWhere(
        (cell) => cell.cutId == cut.value,
      );
      final pageTopLeft = tester.getTopLeft(
        find.byKey(const ValueKey<String>('conte-form-paint')),
      );
      await press(tester, pageTopLeft + cell.pictureRect.center);
    }

    testWidgets('a cut with no conte row keeps the S row you stood on', (
      tester,
    ) async {
      final session = await pumpConte(tester);
      session.standOnRow(const LayerRowAddress(conteSeId));

      await pressCellOf(tester, session, cut2);

      expect(session.activeCutId, cut2, reason: 'premise');
      expectTimelineOn(
        session,
        conteSeId,
        reason: 'the storyboard\'s V row answers so, and this is the same '
            'stand on a cut',
      );
    });

    testWidgets('a cut with a conte row stands on it', (tester) async {
      final session = await pumpConte(tester);
      session.standOnRow(const LayerRowAddress(conteSeId));

      await pressCellOf(tester, session, cut1);

      expectTimelineOn(session, conteId, reason: 'its conte row');
    });
  });
}
