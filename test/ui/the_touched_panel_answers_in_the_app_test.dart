import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart';
import 'package:anicel/src/ui/canvas/flip_hud_model.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';

import '../helpers/conte_track_fixture.dart';
import '../helpers/home_page_probes.dart';

/// 🗣️유저 2026-09-24 — THE PANEL LAST TOUCHED ANSWERS, through the app:
///
/// > 「마지막으로 만진 패널. 1번기준대로 하자. 그리고 탭 버튼 눌러 콘티로
/// > 바꾸는것도 콘티를 만진것으로. 콘티패널내부의 어느 공간 클릭하던. 그렇게
/// > 하고 입구같은거나 규칙/법 완벽하게 통일 … 위아래 이동이 타임라인 내부로
/// > 샌다거나 그런거 싹 다 해결」
///
/// The shell half — the doors (a tab, any press inside), the ↑/↓ walk, the
/// flip window, the X-sheet's axis and the bound keys. The session half is
/// `session/the_touched_panel_answers_test.dart`.
void main() {
  EditorWorkspace workspaceOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace));
  EditorSessionManager sessionOf(WidgetTester tester) =>
      workspaceOf(tester).session;

  Future<void> pumpHome(WidgetTester tester, {Project? project}) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('a panel brought forward by its tab button is the panel being '
      'worked in — both tabs, both ways', (tester) async {
    await pumpHome(tester);
    final session = sessionOf(tester);
    expect(session.workingPanel, WorkingPanel.timeline, reason: 'premise');

    await showStoryboardPanel(tester);
    expect(
      session.workingPanel,
      WorkingPanel.storyboard,
      reason: '「탭 버튼 눌러 콘티로 바꾸는것도 콘티를 만진것으로」',
    );
    expect(session.currentRow, isA<TrackRowAddress>());

    await showTimelinePanel(tester);
    expect(session.workingPanel, WorkingPanel.timeline);
  });

  testWidgets('the floor switch that brings the storyboard forward is its '
      'button too', (tester) async {
    await pumpHome(tester);
    final session = sessionOf(tester);
    expect(session.workingPanel, WorkingPanel.timeline, reason: 'premise');

    // The top strip's floor switch presses exactly this.
    workspaceOf(tester).panelsMenu!.selectFloorTab(
      EditorWorkspace.storyboardTabId,
    );
    await tester.pumpAndSettle();
    expect(session.workingPanel, WorkingPanel.storyboard);
  });

  testWidgets('any press inside the storyboard is a touch', (tester) async {
    await pumpHome(tester);
    final session = sessionOf(tester);
    await showStoryboardPanel(tester);
    session.claimTimelineRow();
    expect(session.workingPanel, WorkingPanel.timeline, reason: 'premise');

    await tester.tapAt(tester.getCenter(find.byType(StoryboardPanel)));
    await tester.pumpAndSettle();
    expect(
      session.workingPanel,
      WorkingPanel.storyboard,
      reason: '「콘티패널내부의 어느 공간 클릭하던」',
    );
  });

  testWidgets('the storyboard\'s tab dropped on a rail button is the panel in '
      'hand, and the rail button that opens its group is its button', (
    tester,
  ) async {
    await pumpHome(tester);
    final session = sessionOf(tester);
    expect(session.workingPanel, WorkingPanel.timeline, reason: 'premise');

    // A rail wide enough for the storyboard's strip and its sill, widened
    // by the rail's own edge.
    await tester.drag(
      find.byKey(
        ValueKey<String>(
          'dock-resize-${EditorWorkspace.railGroupId(right: true, slot: 2)}',
        ),
      ),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    // A slot of its own, so the group's strip holds this one tab.
    final slot = find.byKey(
      ValueKey<String>(
        'rail-group-${EditorWorkspace.railGroupId(right: true, slot: 6)}',
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey<String>('panel-grip-storyboard')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(slot, findsOneWidget, reason: 'premise: the free slot is on offer');
    await gesture.moveTo(tester.getCenter(slot) + const Offset(0, -5));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(slot));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(StoryboardPanel), findsOneWidget, reason: 'premise');
    expect(
      session.workingPanel,
      WorkingPanel.storyboard,
      reason: 'it landed in front of its new group, and it was in the hand',
    );

    await tester.tap(slot);
    await tester.pumpAndSettle();
    session.claimTimelineRow();
    await tester.tap(slot);
    await tester.pumpAndSettle();
    expect(
      session.workingPanel,
      WorkingPanel.storyboard,
      reason: '「입구같은거나 규칙/법 완벽하게 통일」 — the rail button brings its '
          'group forward the way the tab brings its panel',
    );
  });

  testWidgets('the Panels list touches the panel it shows only when it lands '
      'in front', (tester) async {
    await pumpHome(tester);
    final session = sessionOf(tester);
    final panels = workspaceOf(tester).panelsMenu!;

    panels.toggle(EditorWorkspace.storyboardTabId);
    await tester.pumpAndSettle();
    panels.toggle(EditorWorkspace.storyboardTabId);
    await tester.pumpAndSettle();
    expect(
      session.workingPanel,
      WorkingPanel.timeline,
      reason: 'shown BEHIND the timeline\'s tab: nothing was brought forward',
    );

    panels.toggle(EditorWorkspace.storyboardTabId);
    panels.toggle(EditorWorkspace.timelineTabId);
    await tester.pumpAndSettle();
    session.claimTimelineRow();
    panels.toggle(EditorWorkspace.storyboardTabId);
    await tester.pumpAndSettle();
    expect(find.byType(StoryboardPanel), findsOneWidget, reason: 'premise');
    expect(
      session.workingPanel,
      WorkingPanel.storyboard,
      reason: 'the only tab of its group: shown, and in front',
    );
  });

  testWidgets('folding an S row\'s lanes on the storyboard\'s rail hands the '
      'storyboard its row', (tester) async {
    await pumpHome(tester, project: conteTrackProject());
    final session = sessionOf(tester);
    await showStoryboardPanel(tester);
    final twirl = find.byKey(
      ValueKey<String>('storyboard-se-lane-toggle-${conteTrackId.value}-1'),
    );
    await tester.ensureVisible(twirl);
    await tester.pumpAndSettle();
    await tester.tap(twirl);
    await tester.pumpAndSettle();
    const lane = LaneRowAddress(conteSeId, 'transform-group');
    session.standOnRow(lane, panel: WorkingPanel.storyboard);
    expect(session.currentRow, lane, reason: 'premise');

    await tester.tap(twirl);
    await tester.pumpAndSettle();
    expect(session.currentRow, const LayerRowAddress(conteSeId));
  });

  testWidgets('↑ from the V row is the S1 row, and the storyboard\'s walk '
      'stays on its own rows — never inside the cut', (tester) async {
    await pumpHome(tester);
    final session = sessionOf(tester);
    await showStoryboardPanel(tester);
    final track = session.repository.requireProject().tracks.single;
    session.standOnRow(TrackRowAddress(track.id));
    final drawingTarget = session.activeLayerId;

    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(
      session.currentRow,
      LayerRowAddress(track.seLayers.first.id),
      reason: '「v행에 서있다가 위 키 누르면 S1행으로」 — it used to step to the '
          'layer above the active one, inside the cut',
    );
    expect(session.activeLayerId, drawingTarget, reason: '유저 2026-07-27');

    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(session.currentRow, LayerRowAddress(track.seLayers[1].id));
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(session.currentRow, LayerRowAddress(track.transitionLayer.id));
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(
      session.currentRow,
      LayerRowAddress(track.transitionLayer.id),
      reason: 'clamped at the top of the storyboard\'s rows',
    );

    for (var step = 0; step < 3; step += 1) {
      await key(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(session.currentRow, TrackRowAddress(track.id));
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(
      session.currentRow,
      TrackRowAddress(track.id),
      reason: 'the V row is the bottom of the storyboard\'s rows',
    );
    expect(session.workingPanel, WorkingPanel.storyboard);
  });

  testWidgets('the flip window draws the rows of the panel being worked in',
      (tester) async {
    await pumpHome(tester);
    final session = sessionOf(tester);
    final hud = workspaceOf(tester).flipHud!;
    await showStoryboardPanel(tester);
    session.standOnRow(TrackRowAddress(session.selectedTrackId));

    final storyboard = hud.debugSnapshotFor(FlipHudAxis.row)!;
    expect(
      [for (final row in storyboard.rows.skip(1)) row.name],
      ['S2', 'S1', 'V1'],
      reason: 'the storyboard\'s own stack under its transition row',
    );
    expect(storyboard.currentRow!.name, 'V1');

    session.claimTimelineRow();
    final timeline = hud.debugSnapshotFor(FlipHudAxis.row)!;
    expect(timeline.rows.length, isNot(storyboard.rows.length));
    expect(
      timeline.currentRow!.name,
      session.activeLayer!.name,
      reason: 'the timeline\'s window stands on its own row',
    );
  });

  testWidgets('a lane stood on in the timeline is drawn as its lane — its '
      'keys, not its layer\'s blocks', (tester) async {
    await pumpHome(tester);
    final session = sessionOf(tester);
    final hud = workspaceOf(tester).flipHud!;
    final layerId = session.activeLayerId!;
    await tester.tap(
      find.byKey(ValueKey<String>('timeline-lane-toggle-${layerId.value}')),
    );
    await tester.pumpAndSettle();
    session.standOnRow(LaneRowAddress(layerId, 'transform-group'));

    final row = hud.debugSnapshotFor(FlipHudAxis.row)!.currentRow!;
    expect(row.name, isNot(session.activeLayer!.name), reason: 'premise');
    expect(row.isLane, isTrue);
  });

  testWidgets('the window draws the blocks the flip steps through: the V '
      'row\'s PANELS, the transition row\'s SPANS — and the gap\'s window the '
      'same panels', (tester) async {
    List<(int, int)> runsOf(FlipHudSnapshot snapshot) => [
      for (final run in snapshot.currentRow!.runs) (run.startIndex, run.length),
    ];
    await pumpHome(tester, project: conteTrackProject());
    final session = sessionOf(tester);
    final hud = workspaceOf(tester).flipHud!;
    await showStoryboardPanel(tester);

    session.standOnRow(const TrackRowAddress(conteTrackId));
    expect(
      runsOf(hud.debugSnapshotFor(FlipHudAxis.frame)!),
      [(0, 4), (4, 4), (8, 4), (15, 10)],
      reason: 'cut-1\'s three conte panels, then cut-2 whole',
    );

    final track = session.repository.requireProject().tracks.single;
    session.standOnRow(
      LayerRowAddress(track.transitionLayer.id),
      panel: WorkingPanel.storyboard,
    );
    expect(
      runsOf(hud.debugSnapshotFor(FlipHudAxis.frame)!),
      [(6, 3), (18, 2)],
      reason: 'the transition row\'s blocks are its spans',
    );

    // The TIMELINE, parked in the gap: no cut, so no rows — the track is
    // the row, and it is drawn in the V row's own panels.
    session.claimTimelineRow();
    session.selectGlobalFrame(13);
    expect(session.activeCutOrNull, isNull, reason: 'premise: the gap');
    expect(
      runsOf(hud.debugSnapshotFor(FlipHudAxis.frame)!),
      [(0, 4), (4, 4), (8, 4), (15, 10)],
    );
  });

  testWidgets('the X-sheet runs frames down the page for the TIMELINE only',
      (tester) async {
    await pumpHome(tester);
    final hud = workspaceOf(tester).flipHud!;
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
    expect(hud.framesRunVertically, isTrue, reason: 'premise: an X-sheet');

    await showStoryboardPanel(tester);
    expect(
      hud.framesRunVertically,
      isFalse,
      reason: 'the storyboard\'s frames always run sideways — the flip over '
          'it walked its rows sideways while the timeline was an X-sheet',
    );

    await showTimelinePanel(tester);
    expect(hud.framesRunVertically, isTrue);
  });

  group('a bound key presses the button of the panel being worked in', () {
    const trackId = TrackId('t');
    const drawingId = LayerId('a');
    const seId = LayerId('se-1');

    Project project() => Project(
      id: const ProjectId('keys'),
      name: 'keys',
      createdAt: DateTime.utc(2026, 9, 24),
      tracks: [
        Track(
          id: trackId,
          name: 'V',
          cuts: [
            Cut(
              id: const CutId('cut-1'),
              name: '1',
              duration: 12,
              canvasSize: const CanvasSize(width: 32, height: 32),
              layers: [
                Layer(
                  id: drawingId,
                  name: 'A',
                  frames: [
                    Frame(
                      id: const FrameId('a1'),
                      duration: 1,
                      strokes: const [],
                    ),
                  ],
                  timeline: {
                    0: const TimelineExposure.drawing(FrameId('a1'), length: 12),
                  },
                ),
              ],
            ),
          ],
          seLayers: [
            Layer(
              id: seId,
              name: 'S1',
              kind: LayerKind.se,
              frames: [
                Frame(id: const FrameId('s1'), duration: 1, strokes: const []),
              ],
              timeline: {
                3: const TimelineExposure.drawing(FrameId('s1'), length: 3),
              },
            ),
          ],
        ),
      ],
    );

    bool drawingStands(EditorSessionManager session) => session
        .repository
        .requireProject()
        .tracks
        .single
        .cuts
        .single
        .layers
        .firstWhere((layer) => layer.id == drawingId)
        .timeline
        .values
        .any((exposure) => exposure.isDrawing);
    bool soundStands(EditorSessionManager session) => session
        .repository
        .requireProject()
        .tracks
        .single
        .seLayers
        .single
        .timeline
        .values
        .any((exposure) => exposure.isDrawing);

    testWidgets('Delete in the storyboard takes the storyboard\'s block',
        (tester) async {
      await pumpHome(tester, project: project());
      final session = sessionOf(tester);
      await showStoryboardPanel(tester);
      session.standOnRow(
        const LayerRowAddress(seId),
        panel: WorkingPanel.storyboard,
      );
      session.selectGlobalFrame(4);

      await key(tester, LogicalKeyboardKey.delete);
      expect(soundStands(session), isFalse, reason: 'the S row\'s sound went');
      expect(
        drawingStands(session),
        isTrue,
        reason: 'the timeline\'s drawing under the same playhead stays — the '
            'key used to press the TIMELINE\'s delete from anywhere',
      );
    });

    testWidgets('… and Delete in the timeline takes the timeline\'s',
        (tester) async {
      await pumpHome(tester, project: project());
      final session = sessionOf(tester);
      session.standOnRow(const LayerRowAddress(drawingId), frameIndex: 4);

      await key(tester, LogicalKeyboardKey.delete);
      expect(drawingStands(session), isFalse);
      expect(soundStands(session), isTrue);
    });
  });
}
