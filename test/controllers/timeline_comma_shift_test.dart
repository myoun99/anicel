import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/timeline_controller.dart';
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
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

/// TVPaint-style comma edge shifts: glued chains ride along preserving
/// their commas; separated blocks absorb the empty ("X") gap first and move
/// only on contact; marks ride with their covering block.
void main() {
  group('end edge', () {
    test('growing into an empty gap consumes X cells and leaves the next '
        'block in place', () {
      // A[0,2) .. gap(2) .. B[4,6)
      final harness = _Harness({0: _drawing('a', 2), 4: _drawing('b', 2)});

      harness.shift(blockStart: 0, edge: TimelineBlockEdge.end, delta: 1);

      harness.expectTimeline({0: _drawing('a', 3), 4: _drawing('b', 2)});
    });

    test('growing past the gap pushes the separated block by the overlap '
        'only', () {
      final harness = _Harness({0: _drawing('a', 2), 4: _drawing('b', 2)});

      harness.shift(blockStart: 0, edge: TimelineBlockEdge.end, delta: 4);

      harness.expectTimeline({0: _drawing('a', 6), 6: _drawing('b', 2)});
    });

    test('growing pushes a glued chain rigidly, preserving commas and '
        'inner gaps beyond it absorb the push', () {
      // A[0,2) B[2,3) .. gap(1) .. C[4,5)
      final harness = _Harness({
        0: _drawing('a', 2),
        2: _drawing('b', 1),
        4: _drawing('c', 1),
      });

      harness.shift(blockStart: 0, edge: TimelineBlockEdge.end, delta: 2);

      // B glued to A follows +2; C's 1-frame gap absorbs one, then C moves.
      harness.expectTimeline({
        0: _drawing('a', 4),
        4: _drawing('b', 1),
        5: _drawing('c', 1),
      });
    });

    test('shrinking pulls the glued chain along but leaves separated '
        'blocks behind', () {
      // A[0,3) B[3,4) .. gap .. C[6,7)
      final harness = _Harness({
        0: _drawing('a', 3),
        3: _drawing('b', 1),
        6: _drawing('c', 1),
      });

      harness.shift(blockStart: 0, edge: TimelineBlockEdge.end, delta: -2);

      harness.expectTimeline({
        0: _drawing('a', 1),
        1: _drawing('b', 1),
        6: _drawing('c', 1),
      });
    });

    test('shrinking clamps at one frame', () {
      final harness = _Harness({0: _drawing('a', 2)});

      harness.shift(blockStart: 0, edge: TimelineBlockEdge.end, delta: -5);

      harness.expectTimeline({0: _drawing('a', 1)});
    });

    test('the last block grows freely (its end is the timeline extent)', () {
      final harness = _Harness({0: _drawing('a', 1)});

      harness.shift(blockStart: 0, edge: TimelineBlockEdge.end, delta: 3);

      harness.expectTimeline({0: _drawing('a', 4)});
    });
  });

  group('start edge', () {
    test('growing backward into empty space only changes its own comma', () {
      // gap(2) then A[2,4): the user's "앞이 비어있으면 자기 콤마만".
      final harness = _Harness({2: _drawing('a', 2)});

      harness.shift(blockStart: 2, edge: TimelineBlockEdge.start, delta: -2);

      harness.expectTimeline({0: _drawing('a', 4)});
    });

    test('growing backward pushes the glued preceding chain left through '
        'its own gap', () {
      // gap(1) A[1,2) B[2,4): grow B's front by 2 → A pushed to 0.
      final harness = _Harness({1: _drawing('a', 1), 2: _drawing('b', 2)});

      harness.shift(blockStart: 2, edge: TimelineBlockEdge.start, delta: -2);

      harness.expectTimeline({0: _drawing('a', 1), 1: _drawing('b', 3)});
    });

    test('growing backward is clamped by frame zero', () {
      final harness = _Harness({0: _drawing('a', 1), 1: _drawing('b', 2)});

      // Requested -3; no room at all (A already at 0 and glued).
      harness.shift(blockStart: 1, edge: TimelineBlockEdge.start, delta: -3);

      harness.expectTimeline({0: _drawing('a', 1), 1: _drawing('b', 2)});
    });

    test('shrinking from the front pulls the glued preceding chain right', () {
      // A[0,1) B[1,4): shrink B's front by 2 → A follows right, staying
      // glued; B's end stays put.
      final harness = _Harness({0: _drawing('a', 1), 1: _drawing('b', 3)});

      harness.shift(blockStart: 1, edge: TimelineBlockEdge.start, delta: 2);

      harness.expectTimeline({2: _drawing('a', 1), 3: _drawing('b', 1)});
    });

    test('shrinking from the front leaves a separated preceding block and '
        'opens X cells', () {
      // A[0,1) .. gap .. B[3,6)
      final harness = _Harness({0: _drawing('a', 1), 3: _drawing('b', 3)});

      harness.shift(blockStart: 3, edge: TimelineBlockEdge.start, delta: 2);

      harness.expectTimeline({0: _drawing('a', 1), 5: _drawing('b', 1)});
    });

    test('front shrink clamps at one frame', () {
      final harness = _Harness({0: _drawing('a', 3)});

      harness.shift(blockStart: 0, edge: TimelineBlockEdge.start, delta: 9);

      harness.expectTimeline({2: _drawing('a', 1)});
    });
  });

  group('marks (block-owned breakdown dots)', () {
    test('dots ride inside their blocks through a comma shift', () {
      // A[0,4) with a dot at offset 2, glued B[4,6) with a dot at offset 1.
      final harness = _Harness({
        0: _drawing('a', 4, dots: [2]),
        4: _drawing('b', 2, dots: [1]),
      });

      harness.shift(blockStart: 0, edge: TimelineBlockEdge.end, delta: 2);

      // A grows in place (dot offset unchanged); B is pushed to 6 and its
      // dot rides along for free.
      harness.expectTimeline({
        0: _drawing('a', 6, dots: [2]),
        6: _drawing('b', 2, dots: [1]),
      });
    });

    test('a comma shrink drops the dots it cut off', () {
      final harness = _Harness({
        0: _drawing('a', 4, dots: [1, 3]),
      });

      harness.shift(blockStart: 0, edge: TimelineBlockEdge.end, delta: -2);

      harness.expectTimeline({
        0: _drawing('a', 2, dots: [1]),
      });
    });
  });

  group('undo', () {
    test('a shift is one undoable command', () {
      final harness = _Harness({0: _drawing('a', 2), 2: _drawing('b', 2)});

      harness.shift(blockStart: 0, edge: TimelineBlockEdge.end, delta: 3);
      expect(harness.history.undoCount, 1);

      harness.history.undo();
      harness.expectTimeline({0: _drawing('a', 2), 2: _drawing('b', 2)});
    });
  });
}

TimelineExposure _drawing(String frameId, int length, {List<int>? dots}) {
  return TimelineExposure.drawing(
    FrameId(frameId),
    length: length,
    breakdownOffsets: dots ?? const [],
  );
}

class _Harness {
  _Harness(Map<int, TimelineExposure> timeline) {
    final frames = <Frame>[
      for (final entry in timeline.entries)
        if (entry.value.isDrawing)
          Frame(id: entry.value.frameId!, duration: 1, strokes: const []),
    ];
    final layer = Layer(
      id: const LayerId('layer-1'),
      name: 'A',
      frames: frames,
      timeline: timeline,
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
      historyManager: history,
    );
  }

  late final ProjectRepository repository;
  late final TimelineController controller;
  final history = HistoryManager();

  Layer get layer =>
      repository.currentProject!.tracks.first.cuts.first.layers.first;

  void shift({
    required int blockStart,
    required TimelineBlockEdge edge,
    required int delta,
  }) {
    controller.shiftExposureEdge(
      layerId: const LayerId('layer-1'),
      blockStartIndex: blockStart,
      edge: edge,
      delta: delta,
    );
  }

  void expectTimeline(Map<int, TimelineExposure> expected) {
    expect(Map<int, TimelineExposure>.from(layer.timeline), expected);
    validateTimelineCoverage(layer.timeline);
  }
}
