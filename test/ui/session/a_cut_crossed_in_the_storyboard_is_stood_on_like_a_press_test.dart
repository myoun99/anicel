import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart'
    show PlaybackScope;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/conte_track_fixture.dart';

/// 🗣️storyboard-flip-crosses-cut (유저 2026-09-27 답): 「따라간다 — 컷을
/// 넘는 이동도 누를 때와 같은 답」.
///
/// F-187 made a stand in the storyboard seat the timeline, and crossing
/// into another cut while working there — the ruler, a flip, playback —
/// lands the timeline where that press would.
///
/// ↩️I-73 (유저 2026-10-08): 「컷에 설때는 예전처럼 마지막에 섯던 행에
/// 서있는채로 그대로. 콘티행에 서야 콘티행에 서도록」. A press on the V row
/// stands on the CUT, and a cut seats no row of its own — it comes back on
/// the row it was left on. The press that stands on a cut's conte layer is
/// the CONTE row's. (09-26's 「컷에서면 콘티레이어가 있다면 콘티레이어에
/// 서도록」 was the V row's answer while the cut block was its conte
/// blocks.)
///
/// [conteTrackProject]: cut-1 (0..12) has a conte row under its cel row,
/// cut-2 (15..25) has none, and S1 is the track's.
void main() {
  const conteId = LayerId('cut-1-conte');
  const cut1 = CutId('cut-1');
  const cut2 = CutId('cut-2');
  const vRow = TrackRowAddress(conteTrackId);
  final conteRow = LayerRowAddress(trackConteRowId(conteTrackId));

  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: conteTrackProject());
    // The timeline has stood on cut-1's CEL row, so that is the row the
    // cut would come back on by its own memory.
    session.selectCut(cut1);
    session.selectLayer(conteCelId);
  });
  tearDown(() => session.dispose());

  void workInTheStoryboard(TimelineRowAddress row, int globalFrame) {
    session.standOnRow(
      row,
      panel: WorkingPanel.storyboard,
      globalFrameIndex: globalFrame,
    );
    expect(session.workingPanel, WorkingPanel.storyboard, reason: 'premise');
    expect(session.activeCutId, cut2, reason: 'premise');
  }

  void play() {
    session.playbackRig.playback.play(
      scope: PlaybackScope.allCuts,
      startGlobalFrame: 2,
    );
    addTearDown(session.playbackRig.playback.stop);
  }

  // Whichever row cut-1 was left on: its first, the cel, or its conte row.
  // The pair tells the answer apart from both of its neighbours — "the
  // cut's first row" and 09-26's "its conte row".
  for (final left in const [conteCelId, conteId]) {
    group('on the V row a crossing brings the cut back on the row it was '
        'left on (${left.value})', () {
      setUp(() {
        session.selectLayer(left);
        workInTheStoryboard(vRow, 16);
      });

      test('the ruler', () {
        session.selectGlobalFrame(2);

        expect(session.activeCutId, cut1);
        expect(session.activeLayerId, left);
      });

      test('a flip — cut by cut', () {
        // The gap between the cuts (12..15) holds no cut, so the flip walks
        // it a frame at a time, and the fourth step lands on cut-1's start.
        for (final frame in [14, 13, 12]) {
          session.frameVerbs.flipRow(forward: false);
          expect(session.editingGlobalFrame, frame, reason: 'premise: the gap');
          expect(session.activeCutId, isNull, reason: 'premise: the gap');
        }
        session.frameVerbs.flipRow(forward: false);

        expect(session.activeCutId, cut1, reason: 'premise: the flip crossed');
        expect(session.editingGlobalFrame, 0);
        expect(session.activeLayerId, left);
      });

      test('playback', () {
        play();

        expect(session.activeCutId, cut1, reason: 'premise: playback crossed');
        expect(session.activeLayerId, left);
      });
    });
  }

  group('on the CONTE row a crossing stands on the cut\'s conte layer', () {
    setUp(() => workInTheStoryboard(conteRow, 16));

    test('the ruler', () {
      session.selectGlobalFrame(2);

      expect(session.activeCutId, cut1);
      expect(
        session.activeLayerId,
        conteId,
        reason: 'a press on cut-1\'s conte row stands on its conte layer, so '
            'the ruler does',
      );
    });

    test('a flip — panel by panel', () {
      // cut-2 has no conte layer and the gap has no cut: the row holds no
      // block from 12 on, so the flip walks it a frame at a time.
      for (final frame in [15, 14, 13, 12]) {
        session.frameVerbs.flipRow(forward: false);
        expect(session.editingGlobalFrame, frame, reason: 'premise: no block');
      }
      expect(session.activeCutId, isNull, reason: 'premise: the gap');
      session.frameVerbs.flipRow(forward: false);

      expect(session.activeCutId, cut1, reason: 'premise: the flip crossed');
      expect(session.editingGlobalFrame, 8, reason: 'cut-1\'s last panel');
      expect(session.activeLayerId, conteId);
    });

    test('playback', () {
      play();

      expect(session.activeCutId, cut1, reason: 'premise: playback crossed');
      expect(
        session.activeLayerId,
        conteId,
        reason: '↩️it took the new cut\'s first row, the cel',
      );
    });
  });

  test('on an S row the crossing keeps the S row — every cut shows it', () {
    session.standOnRow(
      const LayerRowAddress(conteSeId),
      panel: WorkingPanel.storyboard,
      globalFrameIndex: 2,
    );
    expect(session.activeLayerId, conteSeId, reason: 'premise: F-187');

    session.selectGlobalFrame(17);

    expect(session.activeCutId, cut2);
    expect(session.activeLayerId, conteSeId);
  });

  test('working in the TIMELINE, a cut still comes back on the row it was '
      'left on', () {
    session.selectGlobalFrame(16);
    expect(session.activeCutId, cut2, reason: 'premise');

    session.selectGlobalFrame(2);

    expect(session.workingPanel, WorkingPanel.timeline);
    expect(session.activeLayerId, conteCelId);
  });
}
