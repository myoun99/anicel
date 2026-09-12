// THE STORYBOARD'S FRONT EDGE IS THE SAME EDGE (I-21 ②).
//
// 🗣️유저 2026-09-12: 「스토리보드패널의 컷블록 내 콘티블록이 다르게
// 작동함 … 앞 컷이 그냥 컷블록이면 컷이 1코마될때까지 미는거지.
// 프레임블록이랑 똑같은 하나의 법으로. 근데 그 컷 블록에 콘티블록있으면
// 그 블록의 헤드까지. 이것도 똑같은 법인거지.」
//
// ⚠️THE SESSION PATH IS WHAT THIS PINS. The model's flattening is pinned in
// `test/models/storyboard_panel_slots_test.dart`; a mutant that flattened
// every cut to ONE panel left those red and this file's ancestor green,
// which is exactly the gap a drag-level test has to close: a cut with a
// conte row must trade with the PANEL in front, not with the cut.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/services/editing/default_layer_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';

void main() {
  /// Two cuts, the FIRST one carrying a conte row divided into two panels.
  ///
  /// The row is built through the app's own helper and then split by the
  /// timeline verb, so the fixture speaks the grammar the drag reads back.
  (EditorSessionManager, CutId, CutId) twoCutsWithConteInFront() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.cutVerbs.createCut();
    final project = s.repository.requireProject();
    final track = project.tracks.first;
    final first = track.cuts[0];
    final second = track.cuts[1];

    // Give the first cut a conte row covering it, then divide it in two.
    final row = createStoryboardLayer(
      layerId: const LayerId('conte-1'),
      frameId: const FrameId('conte-1-a'),
      cut: first,
    );
    final half = first.duration ~/ 2;
    s.repository.updateProject(
      (p) => _withLayer(p, cutId: first.id, layer: row),
    );
    s.selectCut(first.id);
    s.selectLayer(const LayerId('conte-1'));
    s.selectFrameIndex(half);
    s.createDrawingAtCurrentFrame();

    return (s, first.id, second.id);
  }

  int durationOf(EditorSessionManager s, CutId id) => s.cutById(id)!.duration;

  List<int> panelLengthsOf(EditorSessionManager s, CutId id) {
    final cut = s.cutById(id)!;
    final row = storyboardLayerForCut(cut)!;
    return [
      for (final entry in row.timeline.entries) entry.value.length!,
    ];
  }

  int layoutStart(EditorSessionManager s, CutId cutId) =>
      buildStoryboardTimelineLayout(
        s.repository.requireProject(),
      ).firstWhere((entry) => entry.cutId == cutId).startFrame;

  test('the cut behind trades with the PANEL in front, not with the cut — '
      'only the last panel gives, and the film keeps its length', () {
    final (s, first, second) = twoCutsWithConteInFront();
    addTearDown(s.dispose);

    final panelsBefore = panelLengthsOf(s, first);
    expect(
      panelsBefore,
      hasLength(2),
      reason: 'LIVENESS — the fixture must really be two panels',
    );
    final totalBefore = durationOf(s, first) + durationOf(s, second);
    final secondEnd = layoutStart(s, second) + durationOf(s, second);

    // Grow the SECOND cut's front by 3. The block it touches is the first
    // cut's LAST panel: that panel shortens, the panel before it is not
    // asked, and the first cut is shorter by exactly what it gave.
    s.edgeDrag.beginCutEdgeDrag(cutId: second, edge: TimelineBlockEdge.start);
    s.edgeDrag.updateCutEdgeDrag(-3);
    s.edgeDrag.endCutEdgeDrag();

    final panelsAfter = panelLengthsOf(s, first);
    expect(
      panelsAfter.first,
      panelsBefore.first,
      reason: 'the panel further in front was never asked',
    );
    expect(
      panelsAfter.last,
      panelsBefore.last - 3,
      reason: 'the panel it touches is the one that gave',
    );
    expect(durationOf(s, second), isNot(0));
    expect(
      durationOf(s, first) + durationOf(s, second),
      totalBefore,
      reason: 'a trade moves ONE boundary — the film keeps its length',
    );
    expect(
      layoutStart(s, second) + durationOf(s, second),
      secondEnd,
      reason: 'the dragged end is pinned',
    );
    expect(
      layoutStart(s, first),
      0,
      reason: 'nothing in front moved: heads are pinned',
    );
  });

  test('it stops when the panel in front is down to one frame', () {
    final (s, first, second) = twoCutsWithConteInFront();
    addTearDown(s.dispose);

    final panelsBefore = panelLengthsOf(s, first);
    final lastPanel = panelsBefore.last;

    s.edgeDrag.beginCutEdgeDrag(cutId: second, edge: TimelineBlockEdge.start);
    s.edgeDrag.updateCutEdgeDrag(-999);
    s.edgeDrag.endCutEdgeDrag();

    final panelsAfter = panelLengthsOf(s, first);
    expect(
      panelsAfter.last,
      1,
      reason: 'the panel it touches keeps a single frame and no more',
    );
    expect(
      panelsAfter.first,
      panelsBefore.first,
      reason: 'and the drag stops there — the panel BEFORE it is outside '
          'the reach of a plain grip',
    );
    expect(
      durationOf(s, first),
      panelsBefore.first + 1,
      reason: 'the cut is its panels',
    );
    expect(
      durationOf(s, second),
      greaterThan(lastPanel),
      reason: 'everything the panel gave up went across',
    );
  });
}

/// [project] with [layer] added to [cutId] — the one bit of assembly the
/// session verbs do not offer, kept local to this fixture.
Project _withLayer(
  Project project, {
  required CutId cutId,
  required Layer layer,
}) {
  return project.copyWith(
    tracks: [
      for (final track in project.tracks)
        track.copyWith(
          cuts: [
            for (final cut in track.cuts)
              if (cut.id == cutId)
                cut.copyWith(layers: [...cut.layers, layer])
              else
                cut,
          ],
        ),
    ],
  );
}
