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
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

/// Inbetween dots are BLOCK-OWNED (UI-R9 #8): they live inside a drawing
/// entry as breakdownOffsets (held cells only, offset 1..length-1) and
/// ride every move/copy of the block. Empty cells and block starts take
/// no dot; ghosts get theirs from the source block.
void main() {
  group('Timeline marks (block-owned breakdown dots)', () {
    test('empty layer has no dot and rejects negative toggle checks', () {
      final fixture = _fixture(_markedTestLayer());

      expect(
        fixture.controller.hasMarkAt(layer: fixture.layer, frameIndex: 2),
        isFalse,
      );
      expect(
        fixture.controller.canToggleMarkAt(
          layer: fixture.layer,
          frameIndex: -1,
        ),
        isFalse,
      );
    });

    test('toggle dot on and off edits the covering block entry in place', () {
      final fixture = _fixture(_markedTestLayer());
      fixture.controller.selectFrameIndex(1);

      fixture.controller.toggleMarkForLayer(layerId: const LayerId('layer'));
      var layer = _latestLayer(fixture.repository);
      expect(layer.timeline[0]!.breakdownOffsets, const [1]);
      expect(layer.timeline.keys, [0]);
      expect(layer.frames, hasLength(1));
      expect(
        fixture.controller.hasMarkAt(layer: layer, frameIndex: 1),
        isTrue,
      );

      fixture.controller.toggleMarkForLayer(layerId: const LayerId('layer'));
      layer = _latestLayer(fixture.repository);
      expect(layer.timeline[0]!.breakdownOffsets, isEmpty);
      expect(layer.frames, hasLength(1));
    });

    test('dots are allowed on held cells only: no block starts, no empty '
        'cells, no ghosts', () {
      final fixture = _fixture(_markedTestLayer());

      // Block start = the drawing itself.
      expect(
        fixture.controller.canToggleMarkAt(layer: fixture.layer, frameIndex: 0),
        isFalse,
      );
      // Held cells inside the block.
      for (final index in [1, 2]) {
        expect(
          fixture.controller.canToggleMarkAt(
            layer: fixture.layer,
            frameIndex: index,
          ),
          isTrue,
          reason: 'index $index',
        );
      }
      // Empty cells have no block to own the dot (author a frame first).
      for (final index in [3, 4, 8]) {
        expect(
          fixture.controller.canToggleMarkAt(
            layer: fixture.layer,
            frameIndex: index,
          ),
          isFalse,
          reason: 'index $index',
        );
      }

      // Ghost blocks are derived: their dots come from the source.
      final ghostLayer = Layer(
        id: const LayerId('ghost-layer'),
        name: 'Ghost layer',
        frames: [
          Frame(id: const FrameId('a'), duration: 2, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(const FrameId('a'), length: 2),
          2: TimelineExposure.drawing(
            const FrameId('a'),
            length: 2,
            ghost: true,
            ghostOwnerId: 'a:end',
          ),
        },
      );
      expect(
        fixture.controller.canToggleMarkAt(layer: ghostLayer, frameIndex: 3),
        isFalse,
      );

      // Toggling where it's disallowed is a no-op.
      fixture.controller.selectFrameIndex(0);
      fixture.controller.toggleMarkForLayer(layerId: const LayerId('layer'));
      expect(_latestLayer(fixture.repository).timeline[0]!.breakdownOffsets,
          isEmpty);
      fixture.controller.selectFrameIndex(4);
      fixture.controller.toggleMarkForLayer(layerId: const LayerId('layer'));
      expect(_latestLayer(fixture.repository).timeline.keys, [0]);
    });

    test('dots never affect blocks, canvas resolution, or block length', () {
      final fixture = _fixture(_markedTestLayer());
      fixture.controller.selectFrameIndex(1);
      fixture.controller.toggleMarkForLayer(layerId: const LayerId('layer'));

      final layer = _latestLayer(fixture.repository);
      // Dot inside the hold: the covering frame still shows.
      expect(
        fixture.controller.resolveFrameIdForLayer(layer: layer, frameIndex: 1),
        const FrameId('a'),
      );
      expect(
        fixture.controller.effectiveDurationForLayerFrame(
          layer: layer,
          frameId: const FrameId('a'),
        ),
        3,
      );
    });

    test('undo and redo dot add and remove', () {
      final history = HistoryManager();
      final fixture = _fixture(_markedTestLayer(), historyManager: history);
      fixture.controller.selectFrameIndex(2);

      fixture.controller.toggleMarkForLayer(layerId: const LayerId('layer'));
      expect(
        _latestLayer(fixture.repository).timeline[0]!.breakdownOffsets,
        const [2],
      );

      history.undo();
      expect(
        _latestLayer(fixture.repository).timeline[0]!.breakdownOffsets,
        isEmpty,
      );

      history.redo();
      expect(
        _latestLayer(fixture.repository).timeline[0]!.breakdownOffsets,
        const [2],
      );

      fixture.controller.toggleMarkForLayer(layerId: const LayerId('layer'));
      expect(
        _latestLayer(fixture.repository).timeline[0]!.breakdownOffsets,
        isEmpty,
      );

      history.undo();
      expect(
        _latestLayer(fixture.repository).timeline[0]!.breakdownOffsets,
        const [2],
      );
    });
  });
}

const _cutId = CutId('cut');

/// Drawing block [0,3), empty (X) cells from 3 on.
Layer _markedTestLayer() {
  return Layer(
    id: const LayerId('layer'),
    name: 'Layer',
    frames: [Frame(id: const FrameId('a'), duration: 3, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(const FrameId('a'), length: 3)},
  );
}

_TimelineMarkFixture _fixture(Layer layer, {HistoryManager? historyManager}) {
  final repository = ProjectRepository(initialProject: _project(layer));
  final controller = TimelineController(
    repository: repository,
    historyManager: historyManager,
    cutId: _cutId,
  );
  return _TimelineMarkFixture(
    repository: repository,
    controller: controller,
    layer: layer,
  );
}

Project _project(Layer layer) {
  return Project(
    id: const ProjectId('project'),
    name: 'Project',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Track',
        cuts: [
          Cut(
            id: _cutId,
            name: 'Cut',
            duration: 1,
            canvasSize: const CanvasSize(width: 100, height: 100),
            layers: [layer],
          ),
        ],
      ),
    ],
  );
}

Layer _latestLayer(ProjectRepository repository) {
  return repository.requireProject().tracks.single.cuts.single.layers.single;
}

class _TimelineMarkFixture {
  const _TimelineMarkFixture({
    required this.repository,
    required this.controller,
    required this.layer,
  });

  final ProjectRepository repository;
  final TimelineController controller;
  final Layer layer;
}
