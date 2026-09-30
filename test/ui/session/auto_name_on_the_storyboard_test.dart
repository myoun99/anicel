import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_lookup.dart' show requireLayer;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/block_naming.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

import '../../helpers/conte_track_fixture.dart';

/// 🗣️I-18 — 자동 이름 지정 on the STORYBOARD, whose noun is the cut: 「첫번째는
/// 블록의 이름(프레임이름, 컷이름) 을 순서대로 지정」 — and a cut numbers by
/// the drawings' own law (I-18-Q1: 「이 로직은 컷번호 바꿀때도 그대로 적용」),
/// each cut its own number (targets-Q4 「컷마다 따로 연번」).
void main() {
  const track = TrackId('v');

  /// Four cuts of four frames each, named 10 11 12 13.
  Project fourCuts() => Project(
    id: const ProjectId('auto-name-cuts'),
    name: 'Cuts',
    createdAt: DateTime.utc(2026, 10, 1),
    tracks: [
      Track(
        id: track,
        name: 'V',
        cuts: [
          for (final name in ['10', '11', '12', '13'])
            Cut(
              id: CutId('cut-$name'),
              name: name,
              duration: 4,
              canvasSize: const CanvasSize(width: 32, height: 32),
              layers: [
                Layer(
                  id: LayerId('cut-$name-a'),
                  name: 'A',
                  frames: const [],
                ),
              ],
            ),
        ],
      ),
    ],
  );

  EditorSessionManager session(Project project) {
    final s = EditorSessionManager(initialProject: project);
    addTearDown(s.dispose);
    return s;
  }

  List<String> cutNames(EditorSessionManager s) => [
    for (final cut in s.repository.requireProject().tracks.single.cuts)
      cut.name,
  ];

  /// What the storyboard's window writes when its number is [from].
  void press(EditorSessionManager s, int from) {
    final naming = s.blockNaming;
    final targets = StoryboardToolbarPanelContext(s).autoNameTargets!;
    naming.apply(naming.plan(targets, from: from));
  }

  test('the selected cuts, and only they, count up from the number: '
      '10 11 12 13 with the middle two from 5 reads 10 5 6 13 — ONE undo', () {
    final s = session(fourCuts());
    s.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: 5,
      headGlobalFrame: 9,
    );
    expect(
      s.storyboardRows.storyboardSelectedCutIds,
      [const CutId('cut-11'), const CutId('cut-12')],
      reason: '⛔전제',
    );
    final entries = s.historyManager.undoCount;

    press(s, 5);

    expect(cutNames(s), ['10', '5', '6', '13']);
    expect(s.historyManager.undoCount, entries + 1, reason: 'ONE step');
    s.undo();
    expect(cutNames(s), ['10', '11', '12', '13']);
  });

  test('nothing selected on the V row: from the cut under the playhead to '
      'the track\'s last', () {
    final s = session(fourCuts());
    s.selectGlobalFrame(9);
    s.selectTrackRow(track);

    press(s, 5);

    expect(cutNames(s), ['10', '11', '5', '6']);
  });

  test('⛔in a gap no cut stands, and a band over the S row names none: the '
      'button dims', () {
    final s = session(conteTrackProject());
    final storyboard = StoryboardToolbarPanelContext(s);
    s.selectGlobalFrame(5);
    s.selectTrackRow(conteTrackId);
    expect(storyboard.canAutoName, isTrue, reason: '⛔전제: inside cut 1');

    s.updateTrackRowRangeSelectionByFrame(
      layerId: conteSeId,
      anchorGlobalFrame: 2,
      headGlobalFrame: 4,
    );
    expect(s.trackFrameRangeSelection.value, isNotNull, reason: '⛔전제');
    expect(
      s.storyboardRows.storyboardSelectedCutIds,
      isEmpty,
      reason: '⛔전제: the band names no cut',
    );
    expect(storyboard.canAutoName, isFalse, reason: 'the band claims it');

    s.trackFrameRangeSelection.value = null;
    s.selectGlobalFrame(13);
    s.selectTrackRow(conteTrackId);
    expect(storyboard.canAutoName, isFalse, reason: 'a gap');
  });

  test('a conte-block band numbers the storyboard layer\'s drawings — the '
      'timeline\'s answer to its own band (F-186)', () {
    final s = session(conteTrackProject());
    const conte = LayerId('cut-1-conte');
    s.selectCut(const CutId('cut-1'));
    s.frameRangeSelection.value = const TimelineFrameRangeSelection(
      layerId: conte,
      startIndex: 4,
      endIndexExclusive: 12,
    );

    final targets = StoryboardToolbarPanelContext(s).autoNameTargets;
    expect(targets, isA<AutoNameFrames>(), reason: 'drawings, not cuts');
    press(s, 5);

    expect(
      [
        for (final frame in requireLayer(
          s.repository.requireProject(),
          cutId: const CutId('cut-1'),
          layerId: conte,
        ).frames)
          frame.name,
      ],
      [null, '5', '6'],
      reason: 'the band\'s two panels, and not the one before it',
    );
  });

  test('⛔the TIMELINE does not reach for cuts: a cut band leaves its press '
      'on the drawings', () {
    final s = session(createDefaultProject());
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    s.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: 0,
      headGlobalFrame: 1,
    );
    expect(
      s.storyboardRows.storyboardSelectedCutIds,
      isNotEmpty,
      reason: '⛔전제: the band names the cut',
    );
    expect(
      TimelineToolbarPanelContext(s).autoNameTargets,
      isA<AutoNameFrames>(),
      reason: 'R5q1: the timeline\'s press is the drawing at its playhead',
    );
  });
}
