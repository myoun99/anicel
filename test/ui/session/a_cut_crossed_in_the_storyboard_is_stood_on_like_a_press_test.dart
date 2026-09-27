import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart'
    show PlaybackScope;
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/conte_track_fixture.dart';

/// 🗣️storyboard-flip-crosses-cut (유저 2026-09-27 답): 「따라간다 — 컷을
/// 넘는 이동도 누를 때와 같은 답」.
///
/// F-187 made a stand in the storyboard seat the timeline: a press on the
/// V row stands on the cut's conte row, a press on an S row on that row.
/// Crossing into another cut while working there — the ruler, a flip,
/// playback — now lands the timeline where that press would.
/// [conteTrackProject]: cut-1 (0..12) has a conte row under its cel row,
/// cut-2 (15..25) has none, and S1 is the track's.
void main() {
  const conteId = LayerId('cut-1-conte');
  const cut1 = CutId('cut-1');
  const cut2 = CutId('cut-2');
  const vRow = TrackRowAddress(conteTrackId);

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
  }

  test('the ruler back into a cut with a conte row stands on it', () {
    workInTheStoryboard(vRow, 16);
    expect(session.activeCutId, cut2, reason: 'premise');

    session.selectGlobalFrame(2);

    expect(session.activeCutId, cut1);
    expect(
      session.activeLayerId,
      conteId,
      reason: 'a press on cut-1 stands on its conte row, so the ruler does',
    );
  });

  test('a flip back into a cut with a conte row stands on it', () {
    workInTheStoryboard(vRow, 16);
    // The V row's panels are the cuts AND the gap between them (12..15):
    // the first flip back parks in the gap, the second crosses into cut-1.
    session.frameVerbs.flipRow(forward: false);
    expect(session.activeCutId, isNull, reason: 'premise: the gap between');
    session.frameVerbs.flipRow(forward: false);

    expect(session.activeCutId, cut1, reason: 'premise: the flip crossed');
    expect(session.activeLayerId, conteId);
  });

  test('playback crossing a cut stands where a press would', () {
    workInTheStoryboard(vRow, 16);
    session.playbackRig.playback.play(
      scope: PlaybackScope.allCuts,
      startGlobalFrame: 2,
    );
    addTearDown(session.playbackRig.playback.stop);

    expect(session.activeCutId, cut1, reason: 'premise: playback crossed');
    expect(
      session.activeLayerId,
      conteId,
      reason: '↩️it took the new cut\'s first row, the cel',
    );
  });

  test('on an S row the crossing keeps the S row — every cut shows it', () {
    workInTheStoryboard(const LayerRowAddress(conteSeId), 2);
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
