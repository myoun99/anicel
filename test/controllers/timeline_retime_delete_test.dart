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
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

/// UI-R17: the bulk retime (1/2/3/4/N comma set + bulk edge drags) and
/// the selection-delete controller cores.
void main() {
  group('retimeBlocksForLayer', () {
    test('the TVP compaction: 1--2--3--4--5-- with 1,2,3 set to 1 comma '
        'packs to 1234--5--', () {
      final harness = _Harness({
        0: _drawing('a', 3),
        3: _drawing('b', 3),
        6: _drawing('c', 3),
        9: _drawing('d', 3),
        12: _drawing('e', 3),
      });

      harness.retime({0: 1, 3: 1, 6: 1});

      harness.expectTimeline({
        0: _drawing('a', 1),
        1: _drawing('b', 1),
        2: _drawing('c', 1),
        3: _drawing('d', 3),
        6: _drawing('e', 3),
      });
    });

    test('growing pushes the glued tail right', () {
      final harness = _Harness({0: _drawing('a', 1), 1: _drawing('b', 1)});

      harness.retime({0: 3, 1: 3});

      harness.expectTimeline({0: _drawing('a', 3), 3: _drawing('b', 3)});
    });

    test('a separated block keeps its start when the shrink opens space', () {
      final harness = _Harness({0: _drawing('a', 3), 6: _drawing('c', 1)});

      harness.retime({0: 1});

      harness.expectTimeline({0: _drawing('a', 1), 6: _drawing('c', 1)});
    });

    test('blocks before the first retimed one never move', () {
      final harness = _Harness({
        0: _drawing('a', 2),
        2: _drawing('b', 2),
        4: _drawing('c', 2),
      });

      harness.retime({2: 1, 4: 1});

      harness.expectTimeline({
        0: _drawing('a', 2),
        2: _drawing('b', 1),
        3: _drawing('c', 1),
      });
    });

    test('a shrink drops the dots it cut off', () {
      final harness = _Harness({
        0: _drawing('a', 4, dots: [1, 3]),
      });

      harness.retime({0: 2});

      harness.expectTimeline({
        0: _drawing('a', 2, dots: [1]),
      });
    });

    test('lengths clamp at one frame and the whole set is ONE undo', () {
      final harness = _Harness({0: _drawing('a', 3), 3: _drawing('b', 3)});

      harness.retime({0: 0, 3: 2});

      harness.expectTimeline({0: _drawing('a', 1), 1: _drawing('b', 2)});
      expect(harness.history.undoCount, 1);

      harness.history.undo();
      harness.expectTimeline({0: _drawing('a', 3), 3: _drawing('b', 3)});
    });

    test('no-op when nothing changes (no phantom undo entry)', () {
      final harness = _Harness({0: _drawing('a', 2)});

      harness.retime({0: 2});

      expect(harness.history.undoCount, 0);
    });
  });

  group('canDeleteCellAt anywhere in the block (UI-R17 #1)', () {
    test('held cells inside a block are deletable; empty cells are not', () {
      final harness = _Harness({0: _drawing('a', 3)});

      expect(harness.canDeleteAt(0), isTrue);
      expect(harness.canDeleteAt(2), isTrue, reason: 'mid-hold deletes too');
      expect(harness.canDeleteAt(3), isFalse, reason: 'empty cell');
    });

    test('deleteCellForLayer standing on a held cell removes the covering '
        'block', () {
      final harness = _Harness({0: _drawing('a', 3), 3: _drawing('b', 1)});

      harness.controller.selectFrameIndex(1);
      harness.controller.deleteCellForLayer(layerId: const LayerId('layer-1'));

      harness.expectTimeline({3: _drawing('b', 1)});
    });
  });

  group('deleteBlocksForLayer (UI-R17 #2)', () {
    test('removes every listed block in one undo step, leaving holes', () {
      final harness = _Harness({
        0: _drawing('a', 2),
        2: _drawing('b', 2),
        4: _drawing('c', 2),
      });

      harness.controller.deleteBlocksForLayer(
        layerId: const LayerId('layer-1'),
        blockStartIndexes: const [0, 4],
      );

      harness.expectTimeline({2: _drawing('b', 2)});
      expect(harness.history.undoCount, 1);

      harness.history.undo();
      harness.expectTimeline({
        0: _drawing('a', 2),
        2: _drawing('b', 2),
        4: _drawing('c', 2),
      });
    });

    test('a linked cel still referenced elsewhere survives the frame GC', () {
      final harness = _Harness({
        0: _drawing('a', 1),
        1: _drawing('a', 1),
        2: _drawing('b', 1),
      });

      harness.controller.deleteBlocksForLayer(
        layerId: const LayerId('layer-1'),
        blockStartIndexes: const [0, 2],
      );

      harness.expectTimeline({1: _drawing('a', 1)});
      expect(
        harness.layer.frames.map((frame) => frame.id.value).toList(),
        ['a'],
        reason: 'a stays referenced at 1; b is GC\'d',
      );
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
    final seen = <String>{};
    final frames = <Frame>[
      for (final entry in timeline.entries)
        if (entry.value.isDrawing && seen.add(entry.value.frameId!.value))
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

  void retime(Map<int, int> newLengthByStart) {
    controller.retimeBlocksForLayer(
      layerId: const LayerId('layer-1'),
      newLengthByStart: newLengthByStart,
    );
  }

  bool canDeleteAt(int frameIndex) =>
      controller.canDeleteCellAt(layer: layer, frameIndex: frameIndex);

  void expectTimeline(Map<int, TimelineExposure> expected) {
    expect(Map<int, TimelineExposure>.from(layer.timeline), expected);
    validateTimelineCoverage(layer.timeline);
  }
}
