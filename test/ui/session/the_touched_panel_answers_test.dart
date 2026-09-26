import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pill_subject.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/track_transform_lane_carrier.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_nav.dart';
import 'package:anicel/src/ui/timeline/timeline_section_policy.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

import '../../helpers/conte_track_fixture.dart';

/// 🗣️유저 2026-09-24 — THE PANEL LAST TOUCHED ANSWERS, for every question
/// the flip, the arrows and the bound keys ask:
///
/// > 「콘티패널에서는 플립이 타임라인패널이랑 같은 규칙으로 설정한 상태로
/// > 블록/프레임별로 이동. 콘티레이어 있으면 콘티레이어 블록기준 … v행에
/// > 서있다가 위 키 누르면 S1행으로 … 마지막으로 만진 패널. 1번기준대로 하자
/// > … 입구같은거나 규칙/법 완벽하게 통일 … 위아래 이동이 타임라인 내부로
/// > 샌다거나 그런거 싹 다 해결」
///
/// The session half: which rows a flip counts, on which axis, from which
/// frame, and where each panel stands. The shell half (the walk, the window,
/// the X-sheet axis, the keys, the tab press) is
/// `the_touched_panel_answers_in_the_app_test.dart`.
void main() {
  const trackId = conteTrackId;
  const seId = conteSeId;
  const celA = conteCelId;

  /// [conteTrackProject]: a conte row of three panels in cut-1, a gap, a
  /// cut-2 without one, an S row sounding in each cut and a fade in each.
  EditorSessionManager session() {
    final manager = EditorSessionManager(initialProject: conteTrackProject());
    addTearDown(manager.dispose);
    manager.selectCut(const CutId('cut-1'));
    manager.selectLayer(celA);
    return manager;
  }

  LayerId transitionId(EditorSessionManager s) =>
      s.repository.requireProject().tracks.single.transitionLayer.id;

  List<int> flips(EditorSessionManager s, {required bool forward, int n = 1}) {
    final landings = <int>[];
    for (var step = 0; step < n; step += 1) {
      s.frameVerbs.flipRow(forward: forward);
      landings.add(s.editingGlobalFrame);
    }
    return landings;
  }

  group('the V row counts PANELS', () {
    test('a cut with a conte row is its panels, a cut without one is one '
        'block, and the gap between them is walked a frame at a time', () {
      final s = session();
      s.claimStoryboardRow();
      expect(s.currentRow, const TrackRowAddress(trackId));
      s.selectGlobalFrame(0);

      expect(
        flips(s, forward: true, n: 8),
        [4, 8, 12, 13, 14, 15, 25, 26],
        reason: '「콘티레이어 있으면 콘티레이어 블록기준」: 0→4→8 are the conte '
            'blocks, 12..14 the gap, 15 the next cut — one block, it has no '
            'conte row — and past the last cut the axis goes on',
      );
    });

    test('backwards too, and the start of the film is the floor', () {
      final s = session();
      s.claimStoryboardRow();
      s.selectGlobalFrame(15);

      expect(flips(s, forward: false, n: 7), [14, 13, 12, 8, 4, 0, 0]);
    });

    test('a V-row step lands IN the cut it reaches — the canvas follows', () {
      final s = session();
      s.claimStoryboardRow();
      s.selectGlobalFrame(8);
      s.frameVerbs.flipRow(forward: true);
      expect(s.activeCutOrNull, isNull, reason: 'the gap parks');
      flips(s, forward: true, n: 3);
      expect(s.activeCutId, const CutId('cut-2'));
      expect(
        s.workingPanel,
        WorkingPanel.storyboard,
        reason: 'a cut switch is not a touch — the storyboard is still worked',
      );
      expect(s.currentRow, const TrackRowAddress(trackId));
    });
  });

  group('the storyboard walks the TRACK\'s rows on the track\'s axis', () {
    test('an S row stood on in the storyboard crosses the cut\'s end, where '
        'the timeline\'s copy of it stays in the cut', () {
      final storyboard = session();
      storyboard.selectRow(const LayerRowAddress(seId));
      expect(storyboard.workingPanel, WorkingPanel.storyboard);
      storyboard.selectGlobalFrame(11);
      storyboard.frameVerbs.flipRow(forward: true);
      expect(storyboard.editingGlobalFrame, 12);
      expect(
        storyboard.activeCutOrNull,
        isNull,
        reason: 'the storyboard\'s S row runs on through the gap',
      );

      final timeline = session();
      timeline.standOnRow(const LayerRowAddress(seId));
      expect(timeline.workingPanel, WorkingPanel.timeline);
      timeline.selectFrameIndex(11);
      timeline.frameVerbs.flipRow(forward: true);
      expect(
        timeline.activeCutId,
        const CutId('cut-1'),
        reason: 'the timeline\'s S row is the cut\'s projection (#741): it '
            'walks on past the cut\'s end, in the same cut',
      );
      expect(timeline.currentFrameIndex, 12);
    });

    test('the storyboard\'s S row steps over its own sounds, in any cut', () {
      final s = session();
      s.selectRow(const LayerRowAddress(seId));
      s.selectGlobalFrame(16);
      expect(flips(s, forward: true, n: 2), [17, 19]);
      s.selectGlobalFrame(1);
      expect(flips(s, forward: true, n: 2), [2, 5]);
    });

    test('a one-frame step is a TRACK frame while the storyboard is worked '
        'in, and a cut frame in the timeline', () {
      final storyboard = session();
      storyboard.claimStoryboardRow();
      storyboard.selectFrameIndex(11);
      storyboard.frameVerbs.selectNextFrame();
      expect(storyboard.editingGlobalFrame, 12);
      expect(storyboard.activeCutOrNull, isNull);

      final timeline = session();
      timeline.claimTimelineRow();
      timeline.selectFrameIndex(11);
      timeline.frameVerbs.selectNextFrame();
      expect(timeline.activeCutId, const CutId('cut-1'));
      expect(timeline.currentFrameIndex, 12, reason: 'the cut\'s own runway');
    });

    test('the storyboard counts from the frame it SHOWS: a timeline stand '
        'past the cut\'s end is shown on the cut\'s last frame there', () {
      final s = session();
      // Local 20 of a 12-frame cut is global 20 — inside cut-2's range.
      s.selectFrameIndex(20);
      s.claimStoryboardRow();
      s.frameVerbs.flipRow(forward: true);
      expect(
        s.editingGlobalFrame,
        12,
        reason: 'the storyboard shows the playhead on frame 11, the last '
            'conte panel; the next column is the gap, not the block after '
            'the one the unclamped frame happened to name',
      );
    });
  });

  test('the TRANSITION row\'s blocks are its spans — on both panels', () {
    final storyboard = session();
    storyboard.selectRow(LayerRowAddress(transitionId(storyboard)));
    storyboard.selectGlobalFrame(5);
    expect(flips(storyboard, forward: true, n: 3), [6, 9, 10]);

    final timeline = session();
    timeline.standOnRow(LayerRowAddress(transitionId(timeline)));
    timeline.selectFrameIndex(5);
    timeline.frameVerbs.flipRow(forward: true);
    timeline.frameVerbs.flipRow(forward: true);
    expect(
      timeline.currentFrameIndex,
      9,
      reason: 'one span is one step (R10 #13: count THAT row\'s blocks) — '
          'it used to walk the span a frame at a time',
    );
  });

  group('each panel stands on its own row', () {
    test('a lane stood on in the timeline is not the row the storyboard '
        'comes back to', () {
      final s = session();
      const lane = LaneRowAddress(celA, 'opacity');
      s.standOnRow(lane);
      expect(s.currentRow, lane);

      s.claimStoryboardRow();
      expect(s.currentRow, const TrackRowAddress(trackId));
      s.claimTimelineRow();
      expect(s.currentRow, lane);
    });

    test('a lane stood on in the storyboard stays the storyboard\'s — the '
        'timeline comes back to its LAYER', () {
      final s = session();
      const lane = LaneRowAddress(seId, 'position');
      s.standOnRow(lane, panel: WorkingPanel.storyboard);
      expect(s.currentRow, lane);
      expect(
        s.activeLayerId,
        seId,
        reason: '↩️F-187 (was 유저 2026-07-27): 「se행에 선다 … 타임라인패널에 '
            '반영」',
      );

      s.claimTimelineRow();
      expect(s.currentRow, const LayerRowAddress(seId));
      s.claimStoryboardRow();
      expect(s.currentRow, lane);
    });

    test('a program re-seat of the drawing target leaves the storyboard\'s '
        'flip where it was', () {
      final s = session();
      s.claimStoryboardRow();
      // The drawing rows off the screen: a cut switch has to stand the
      // timeline somewhere else — an S row, the nearest row shown above.
      s.railView.hiddenSections.value = {TimelineSection.drawing};
      s.selectCut(const CutId('cut-2'));
      expect(s.activeLayerId, seId, reason: 'fixture premise: the stand-in');

      expect(s.workingPanel, WorkingPanel.storyboard);
      expect(
        s.currentRow,
        const TrackRowAddress(trackId),
        reason: 'the stand-in is the timeline\'s business; the storyboard '
            'was standing on its V row and still is',
      );
    });

    test('an undo\'s walk moves where the timeline stands, not which panel '
        'you are working in — an undo is a key, not a touch', () {
      final s = session();
      s.createDrawingAtCurrentFrame();
      s.claimStoryboardRow();
      s.selectGlobalFrame(20);
      expect(s.activeCutId, const CutId('cut-2'), reason: 'premise');

      s.undo();
      expect(
        s.activeCutId,
        const CutId('cut-1'),
        reason: 'LIVENESS: the undo walked back to where the edit was',
      );
      expect(s.workingPanel, WorkingPanel.storyboard);
      expect(s.currentRow, const TrackRowAddress(trackId));
    });

    test('a timeline fold hands the timeline\'s row on, and leaves the '
        'storyboard\'s flip where it was', () {
      final s = session();
      s.standOnRow(const LaneRowAddress(celA, 'opacity'));
      s.claimStoryboardRow();

      s.handOffCurrentRowOnFold(celA);
      expect(s.workingPanel, WorkingPanel.storyboard);
      expect(s.currentRow, const TrackRowAddress(trackId));
      s.claimTimelineRow();
      expect(
        s.currentRow,
        const LayerRowAddress(celA),
        reason: 'LIVENESS: the fold took the lane, and its layer swallowed it',
      );
    });

    test('dragging an S row\'s lane on the storyboard picks the rail\'s row, '
        'and the timeline stands there too', () {
      final s = session();
      s.updateLaneRangeSelectionDrag(
        layerId: seId,
        laneId: 'position',
        anchorIndex: 2,
        headIndex: 4,
        spanLaneIds: const ['position'],
        panel: WorkingPanel.storyboard,
      );
      expect(s.activeLayerId, seId, reason: '↩️F-187 (was 유저 2026-07-27)');
      expect(s.selectedRow, const LayerRowAddress(seId));
      expect(s.workingPanel, WorkingPanel.storyboard);
    });

    test('a row made while working in the storyboard is that rail\'s row',
        () {
      final s = session();
      s.claimStoryboardRow();
      StoryboardToolbarPanelContext(s).addLayer();
      final made = s.repository.requireProject().tracks.single.seLayers.last;
      expect(made.id, isNot(seId));
      expect(s.currentRow, LayerRowAddress(made.id));
      expect(s.selectedRow, LayerRowAddress(made.id));
    });
  });

  group('the panel still on the screen answers (유저 2026-09-25 「화면에 남은 '
      '쪽이 받는다」)', () {
    final timelineSurface = Object();
    final storyboardSurface = Object();

    void sight(
      EditorSessionManager s,
      WorkingPanel panel, {
      required bool inSight,
      Object? surface,
    }) => s.panelInSight(
      panel,
      surface:
          surface ??
          (panel == WorkingPanel.timeline ? timelineSurface : storyboardSurface),
      inSight: inSight,
    );

    EditorSessionManager bothInSight() {
      final s = session();
      sight(s, WorkingPanel.timeline, inSight: true);
      sight(s, WorkingPanel.storyboard, inSight: true);
      return s;
    }

    test('the storyboard put away hands the work to the timeline', () {
      final s = bothInSight();
      s.claimStoryboardRow();
      sight(s, WorkingPanel.storyboard, inSight: false);
      expect(s.workingPanel, WorkingPanel.timeline);
      expect(s.currentRow, const LayerRowAddress(celA));
    });

    test('… and the timeline put away hands it to the storyboard', () {
      final s = bothInSight();
      sight(s, WorkingPanel.timeline, inSight: false);
      expect(s.workingPanel, WorkingPanel.storyboard);
    });

    test('with the other off the screen too, nothing moves', () {
      final s = bothInSight();
      sight(s, WorkingPanel.timeline, inSight: false);
      s.claimStoryboardRow();
      sight(s, WorkingPanel.storyboard, inSight: false);
      expect(s.workingPanel, WorkingPanel.storyboard);
    });

    test('a panel that never said is not on the screen', () {
      final s = session();
      s.claimStoryboardRow();
      sight(s, WorkingPanel.storyboard, inSight: false);
      expect(s.workingPanel, WorkingPanel.storyboard);
    });

    test('a panel saying it IS on the screen keeps the work', () {
      final s = bothInSight();
      s.claimStoryboardRow();
      sight(s, WorkingPanel.storyboard, inSight: true);
      expect(s.workingPanel, WorkingPanel.storyboard);
    });

    test('coming back is no touch — the tab or a press claims it again', () {
      final s = bothInSight();
      s.claimStoryboardRow();
      sight(s, WorkingPanel.storyboard, inSight: false);
      sight(s, WorkingPanel.storyboard, inSight: true);
      expect(s.workingPanel, WorkingPanel.timeline);
    });

    test('a panel moving between docks is on the screen while either of its '
        'surfaces is — the new one mounts before the old one goes', () {
      final s = bothInSight();
      s.claimStoryboardRow();
      final moved = Object();
      sight(s, WorkingPanel.storyboard, inSight: true, surface: moved);
      sight(s, WorkingPanel.storyboard, inSight: false);
      expect(
        s.workingPanel,
        WorkingPanel.storyboard,
        reason: 'the old dock let go of a panel the new one shows',
      );
      sight(s, WorkingPanel.storyboard, inSight: false, surface: moved);
      expect(s.workingPanel, WorkingPanel.timeline);
    });
  });

  group('a fold hands on where ITS panel stands (R5 #11, both rails)', () {
    test('an S row\'s lanes folding in the storyboard hand the storyboard '
        'its row', () {
      final s = session();
      s.standOnRow(
        const LaneRowAddress(seId, 'position'),
        panel: WorkingPanel.storyboard,
      );
      final seated = s.activeLayerId;
      s.handOffCurrentRowOnFold(seId, panel: WorkingPanel.storyboard);
      expect(
        s.currentRow,
        const LayerRowAddress(seId),
        reason: 'the lane left the screen; the window drew its row while the '
            'flip still walked the lane a frame at a time',
      );
      expect(s.workingPanel, WorkingPanel.storyboard);
      expect(
        s.activeLayerId,
        seated,
        reason: 'the fold is the storyboard\'s hand-off — the layer you draw '
            'on stays where the stand seated it (F-187)',
      );
    });

    test('a V track\'s lanes folding hand the storyboard the TRACK row — '
        'their carrier is no layer', () {
      final s = session();
      final carrier = trackTransformLaneCarrierId(trackId);
      s.standOnRow(
        LaneRowAddress(carrier, 'opacity'),
        panel: WorkingPanel.storyboard,
      );
      expect(s.currentRow, LaneRowAddress(carrier, 'opacity'), reason: 'premise');
      s.rowSelectionVerbs.beginRowSelection(LaneRowAddress(carrier, 'opacity'));
      s.rowSelection.value = [LaneRowAddress(carrier, 'opacity')];

      s.handOffCurrentRowOnFold(carrier, panel: WorkingPanel.storyboard);
      expect(s.currentRow, const TrackRowAddress(trackId));
      expect(
        s.rowSelection.value,
        [const TrackRowAddress(trackId)],
        reason: 'H6 「행이 보이는 곳만 조작」: the band gives the lane up to the '
            'row on screen — the track, since the carrier is no row at all',
      );
    });

    test('a group folding in the storyboard hands its header', () {
      final s = session();
      s.standOnRow(
        const LaneRowAddress(seId, 'position'),
        panel: WorkingPanel.storyboard,
      );
      s.handOffCurrentRowOnFold(
        seId,
        laneId: 'transform-group',
        panel: WorkingPanel.storyboard,
      );
      expect(s.currentRow, const LaneRowAddress(seId, 'transform-group'));
    });

    test('the timeline\'s fold leaves the storyboard\'s lane, and the '
        'storyboard\'s leaves the timeline\'s', () {
      final s = session();
      // ↩️F-187: a storyboard stand seats the timeline too, so the timeline's
      // lane is stood on AFTER it — a timeline pick leaves the storyboard's
      // row alone (2026-07-27) — and the storyboard is touched again.
      s.standOnRow(
        const LaneRowAddress(seId, 'position'),
        panel: WorkingPanel.storyboard,
      );
      s.standOnRow(const LaneRowAddress(celA, 'opacity'));
      s.claimStoryboardRow();

      s.handOffCurrentRowOnFold(seId);
      expect(
        s.currentRow,
        const LaneRowAddress(seId, 'position'),
        reason: 'the timeline folded ITS copy of the row — the storyboard '
            'still shows the lane',
      );

      s.handOffCurrentRowOnFold(celA, panel: WorkingPanel.storyboard);
      s.claimTimelineRow();
      expect(s.currentRow, const LaneRowAddress(celA, 'opacity'));
    });
  });

  test('standing on an S row\'s LANE, the storyboard\'s pill no longer '
      'reaches for the cut', () {
    final s = session();
    s.standOnRow(
      const LaneRowAddress(seId, 'position'),
      panel: WorkingPanel.storyboard,
    );
    final pill = StoryboardToolbarPanelContext(s);
    expect(
      pill.deleteSubject,
      PillSubject.nothing,
      reason: 'the lane\'s row is no cut block — Delete here used to delete '
          'the CUT',
    );
    expect(pill.canSetComma, isFalse, reason: '… and a comma re-timed it');
    expect(
      pill.canCreateInstance,
      isTrue,
      reason: 'a lane answers with its row: the ＋ authors on the S row\'s '
          'empty cursor frame (C3-lane-move)',
    );
  });

  group('one step along a stack', () {
    const a = LayerRowAddress(LayerId('a'));
    const b = LayerRowAddress(LayerId('b'));
    const c = TrackRowAddress(TrackId('c'));

    test('moves one row and clamps at the ends', () {
      expect(stepAlongRows([a, b, c], fromIndex: 1, direction: -1), a);
      expect(stepAlongRows([a, b, c], fromIndex: 1, direction: 1), c);
      expect(stepAlongRows([a, b, c], fromIndex: 2, direction: 1), isNull);
      expect(stepAlongRows([a, b, c], fromIndex: 0, direction: -1), isNull);
    });

    test('a row that is not in the stack enters from the matching end', () {
      expect(stepAlongRows([a, b, c], fromIndex: -1, direction: 1), a);
      expect(stepAlongRows([a, b, c], fromIndex: -1, direction: -1), c);
    });
  });
}
