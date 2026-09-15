import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/timeline_controller.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

import '../helpers/run_edge_fixtures.dart';

/// F-137 — a derived ghost is an EMPTY CELL to the koma: the comma buttons and
/// the comma edge drag lay the row out as if the ghosts were not there, and
/// the rederive puts them back.
///
/// 유저 2026-09-14: 「홀드나 리피트등 고스트프레임은 제대로 빈 칸 처리가
/// 되도록. 프레임1이 뒷성질 홀드이고 그 뒤에 프레임2가 존재할경우, 프레임 1의
/// 콤마를 조절하면 프레임 2가 밀려버림 … 리피트도 같은상황 발생」.
///
/// 「그렇다고 완전 빈칸 처리는 아님 … 플립으로 다음 블록이나 다음
/// 고스트프레임으로 건너뛸수 있게는 되야함」 — the flip's columns over ghosts
/// are pinned in `editor_session_manager_drawing_nav_test.dart`, and nothing
/// here reaches the flip.
void main() {
  test('a comma button on a run with an end HOLD leaves the next block where '
      'it is', () {
    final koma = _Koma({0: _d('a', 1, endEdge: holdMark), 4: _d('b', 1)});
    expect(
      koma.ghostCells(koma.layer),
      [1, 2, 3],
      reason: 'fixture premise: the hold fills up to b',
    );

    final after = koma.controller.retimedLayerForBlocks(
      layer: koma.layer,
      newLengthByStart: {0: 2},
    )!;

    expect(koma.realBlocks(after), {0: ('a', 2), 4: ('b', 1)});
    expect(koma.ghostCells(after), [2, 3]);
  });

  test("dragging that run's trailing comma edge leaves the next block where "
      'it is', () {
    final koma = _Koma({0: _d('a', 1, endEdge: holdMark), 4: _d('b', 1)});

    final after = koma.controller.shiftedLayerForEdge(
      layer: koma.layer,
      blockStartIndex: 0,
      edge: TimelineBlockEdge.end,
      delta: 1,
    )!;

    expect(koma.realBlocks(after), {0: ('a', 2), 4: ('b', 1)});
    expect(koma.ghostCells(after), [2, 3]);
  });

  test('a REPEAT does the same — a comma button inside the run leaves the '
      'block after its ghosts where it is', () {
    final koma = _Koma({
      0: _d('a', 1),
      1: _d('b', 1, endEdge: repeatMark),
      6: _d('c', 1),
    });
    expect(
      koma.ghostCells(koma.layer),
      [2, 3, 4, 5],
      reason: 'fixture premise: the repeat fills up to c',
    );

    final after = koma.controller.retimedLayerForBlocks(
      layer: koma.layer,
      newLengthByStart: {0: 2},
    )!;

    expect(koma.realBlocks(after), {0: ('a', 2), 2: ('b', 1), 6: ('c', 1)});
    expect(koma.ghostCells(after), [3, 4, 5]);
  });

  test("a lead edge grows into a start HOLD's ghosts as into empty cells", () {
    final koma = _Koma({0: _d('x', 1), 4: _d('y', 1, startEdge: holdMark)});
    expect(
      koma.ghostCells(koma.layer),
      [1, 2, 3],
      reason: 'fixture premise: the hold fills back to x',
    );

    expect(
      koma.controller.clampExposureEdgeDelta(
        layer: koma.layer,
        blockStartIndex: 4,
        edge: TimelineBlockEdge.start,
        delta: -10,
      ),
      -3,
      reason: 'the three cells in front are empty, and x is down to one',
    );
  });

  test("a SELECTION's lead edge grows into the same ghosts the same way", () {
    final koma = _Koma({0: _d('x', 1), 4: _d('y', 1, startEdge: holdMark)});

    final after = koma.controller.leadEdgeLayerForBlock(
      layer: koma.layer,
      blockStartIndex: 4,
      delta: -3,
    )!;

    expect(koma.realBlocks(after), {0: ('x', 1), 1: ('y', 4)});
    expect(koma.ghostCells(after), isEmpty, reason: 'no room is left for them');
  });

  test('⛔a ghost has no comma edge of its own', () {
    final koma = _Koma({0: _d('a', 1, endEdge: holdMark), 4: _d('b', 1)});

    expect(
      koma.controller.clampExposureEdgeDelta(
        layer: koma.layer,
        blockStartIndex: 1,
        edge: TimelineBlockEdge.end,
        delta: 1,
      ),
      0,
    );
  });
}

TimelineExposure _d(
  String id,
  int length, {
  TimelineRunEdgeMark startEdge = TimelineRunEdgeMark.none,
  TimelineRunEdgeMark endEdge = TimelineRunEdgeMark.none,
}) => TimelineExposure.drawing(
  FrameId(id),
  length: length,
  startEdge: startEdge,
  endEdge: endEdge,
);

/// One 24-frame cut holding one row, its ghosts derived before the test
/// reads it.
class _Koma {
  _Koma(Map<int, TimelineExposure> authored) {
    final layer = rederiveRunBehaviors(
      Layer(
        id: const LayerId('layer-1'),
        name: 'A',
        frames: [
          for (final entry in authored.values)
            Frame(id: entry.frameId!, duration: 1, strokes: const []),
        ],
        timeline: authored,
      ),
      cutFrameCount: 24,
    );
    final cut = Cut(
      id: const CutId('cut-1'),
      name: 'Cut 1',
      layers: [layer],
      duration: 24,
      canvasSize: const CanvasSize(width: 640, height: 360),
    );
    repository = ProjectRepository(
      initialProject: Project(
        id: const ProjectId('project-1'),
        name: 'P',
        createdAt: DateTime(2026),
        tracks: [
          Track(id: const TrackId('track-1'), name: 'T', cuts: [cut]),
        ],
      ),
    );
    controller = TimelineController(
      repository: repository,
      cutId: const CutId('cut-1'),
      historyManager: HistoryManager(),
    );
  }

  late final ProjectRepository repository;
  late final TimelineController controller;

  Layer get layer =>
      repository.currentProject!.tracks.first.cuts.first.layers.first;

  /// The authored blocks: start → (frame, length).
  Map<int, (String, int)> realBlocks(Layer layer) => {
    for (final entry in layer.timeline.entries)
      if (entry.value.isDrawing && !entry.value.ghost)
        entry.key: (entry.value.frameId!.value, entry.value.length!),
  };

  /// Every cell a derived ghost covers, in order.
  List<int> ghostCells(Layer layer) => [
    for (final entry in layer.timeline.entries)
      if (entry.value.isDrawing && entry.value.ghost)
        for (var i = entry.key; i < entry.key + entry.value.length!; i += 1) i,
  ];
}
