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

void main() {
  group('Frame editing timeline controller', () {
    test('renames frame by ID, trims whitespace, and clears empty names', () {
      final fixture = _fixture(_editingLayer());

      fixture.controller.renameFrameForLayer(
        layerId: const LayerId('layer'),
        frameId: const FrameId('a'),
        name: '  A1  ',
      );
      expect(
        _frame(_latestLayer(fixture.repository), const FrameId('a')).name,
        'A1',
      );

      fixture.controller.renameFrameForLayer(
        layerId: const LayerId('layer'),
        frameId: const FrameId('a'),
        name: '   ',
      );
      expect(
        _frame(_latestLayer(fixture.repository), const FrameId('a')).name,
        isNull,
      );
    });

    test('rename is undo and redo able', () {
      final history = HistoryManager();
      final fixture = _fixture(_editingLayer(), historyManager: history);

      fixture.controller.renameFrameForLayer(
        layerId: const LayerId('layer'),
        frameId: const FrameId('a'),
        name: 'A1',
      );
      expect(
        _frame(_latestLayer(fixture.repository), const FrameId('a')).name,
        'A1',
      );

      history.undo();
      expect(
        _frame(_latestLayer(fixture.repository), const FrameId('a')).name,
        isNull,
      );

      history.redo();
      expect(
        _frame(_latestLayer(fixture.repository), const FrameId('a')).name,
        'A1',
      );
    });

    test('delete cell does nothing on blank start / X', () {
      final fixture = _fixture(_editingLayer());
      fixture.controller.selectFrameIndex(3);

      fixture.controller.deleteCellForLayer(layerId: const LayerId('layer'));

      expect(_latestLayer(fixture.repository), _editingLayer());
    });

    test('delete on a dot-held cell removes the COVERING block (UI-R17 #1 '
        '— the head-only rule is gone)', () {
      final dottedLayer = _editingLayer(markIndex: 1);
      final fixture = _fixture(dottedLayer);
      fixture.controller.selectFrameIndex(1);

      fixture.controller.deleteCellForLayer(layerId: const LayerId('layer'));

      final layer = _latestLayer(fixture.repository);
      expect(layer.timeline.keys, orderedEquals([5, 9]));
      // 'a' survives the frame GC — still referenced by the block at 9.
      expect(
        layer.frames.map((frame) => frame.id),
        orderedEquals([const FrameId('a'), const FrameId('b')]),
      );
    });

    test(
      'delete drawing start removes entry and unreferenced backing frame',
      () {
        final fixture = _fixture(_editingLayer(markIndex: 2));
        fixture.controller.selectFrameIndex(5);

        fixture.controller.deleteCellForLayer(layerId: const LayerId('layer'));
        final layer = _latestLayer(fixture.repository);

        expect(layer.timeline.keys, orderedEquals([0, 9]));
        expect(
          layer.frames.map((frame) => frame.id),
          orderedEquals([const FrameId('a')]),
        );
        expect(layer.timeline[0]!.breakdownOffsets, const [2]);
        expect(layer.timeline[9]?.frameId, const FrameId('a'));
      },
    );

    test('delete drawing start deletes its block-owned dots with it', () {
      final fixture = _fixture(_editingLayer(markIndex: 7));
      fixture.controller.selectFrameIndex(5);

      fixture.controller.deleteCellForLayer(layerId: const LayerId('layer'));
      final layer = _latestLayer(fixture.repository);

      expect(layer.timeline.keys, orderedEquals([0, 9]));
      expect(
        layer.frames.map((frame) => frame.id),
        orderedEquals([const FrameId('a')]),
      );
      for (final entry in layer.timeline.values) {
        expect(entry.breakdownOffsets, isEmpty);
      }
    });

    test(
      'delete drawing start keeps backing frame while referenced elsewhere',
      () {
        final fixture = _fixture(_editingLayer());
        fixture.controller.selectFrameIndex(9);

        fixture.controller.deleteCellForLayer(layerId: const LayerId('layer'));
        final layer = _latestLayer(fixture.repository);

        expect(layer.timeline.keys, orderedEquals([0, 5]));
        expect(
          layer.frames.map((frame) => frame.id),
          orderedEquals([const FrameId('a'), const FrameId('b')]),
        );
        expect(layer.timeline[0]?.frameId, const FrameId('a'));
      },
    );

    test('delete works on held cells via the covering block (UI-R17 #1); '
        'blank/empty cells stay no-ops', () {
      final drawingHeld = _fixture(_editingLayer());
      drawingHeld.controller.selectFrameIndex(1);
      drawingHeld.controller.deleteCellForLayer(
        layerId: const LayerId('layer'),
      );
      expect(
        _latestLayer(drawingHeld.repository).timeline.keys,
        orderedEquals([5, 9]),
        reason: 'the covering a-block at 0 deletes from its held cell',
      );

      final blankHeld = _fixture(_editingLayer());
      blankHeld.controller.selectFrameIndex(4);
      blankHeld.controller.deleteCellForLayer(layerId: const LayerId('layer'));
      expect(_latestLayer(blankHeld.repository), _editingLayer());

      final emptyLayer = Layer(
        id: const LayerId('layer'),
        name: 'Layer',
        frames: const [],
        timeline: const {},
      );
      final empty = _fixture(emptyLayer);
      empty.controller.selectFrameIndex(4);
      empty.controller.deleteCellForLayer(layerId: const LayerId('layer'));
      expect(_latestLayer(empty.repository), emptyLayer);
    });

    test('delete drawing start is undo and redo able', () {
      final history = HistoryManager();
      final fixture = _fixture(_editingLayer(), historyManager: history);
      fixture.controller.selectFrameIndex(5);

      fixture.controller.deleteCellForLayer(layerId: const LayerId('layer'));
      expect(_latestLayer(fixture.repository).timeline.containsKey(5), isFalse);

      history.undo();
      expect(
        _latestLayer(fixture.repository).timeline[5]?.frameId,
        const FrameId('b'),
      );

      history.redo();
      expect(_latestLayer(fixture.repository).timeline.containsKey(5), isFalse);
    });

    test('mark toggle can still remove marks', () {
      final fixture = _fixture(_editingLayer(markIndex: 4));
      fixture.controller.selectFrameIndex(4);

      fixture.controller.toggleMarkForLayer(layerId: const LayerId('layer'));

      final layer = _latestLayer(fixture.repository);
      expect(layer.timeline.containsKey(4), isFalse);
      expect(layer.timeline, _editingLayer().timeline);
    });

    test('can delete and rename checks match follow-up cell rules', () {
      final fixture = _fixture(_editingLayer(markIndex: 4));
      final layer = fixture.layer;

      expect(
        fixture.controller.canRenameFrameAt(layer: layer, frameIndex: 1),
        isTrue,
      );
      expect(
        fixture.controller.canRenameFrameAt(layer: layer, frameIndex: 4),
        isFalse,
      );
      expect(
        fixture.controller.canDeleteCellAt(layer: layer, frameIndex: 4),
        isFalse,
        reason: 'empty cell — nothing covers it',
      );
      expect(
        fixture.controller.canDeleteCellAt(layer: layer, frameIndex: 5),
        isTrue,
      );
      expect(
        fixture.controller.canDeleteCellAt(layer: layer, frameIndex: 3),
        isFalse,
        reason: 'empty cell',
      );
      expect(
        fixture.controller.canDeleteCellAt(layer: layer, frameIndex: 1),
        isTrue,
        reason: 'held cell deletes its covering block (UI-R17 #1)',
      );
      expect(
        fixture.controller.canDeleteCellAt(layer: layer, frameIndex: -1),
        isFalse,
      );
    });
  });
}

const _cutId = CutId('cut');

/// a[0,3) .. X[3,5) .. b[5,9) .. a[9,12); optional block-owned dot at
/// [markIndex] (folded into the covering block's breakdownOffsets).
Layer _editingLayer({int? markIndex}) {
  final timeline = <int, TimelineExposure>{
    0: TimelineExposure.drawing(const FrameId('a'), length: 3),
    5: TimelineExposure.drawing(const FrameId('b'), length: 4),
    9: TimelineExposure.drawing(const FrameId('a'), length: 3),
  };
  if (markIndex != null) {
    final start = timeline.keys.lastWhere((key) => key <= markIndex);
    timeline[start] = timeline[start]!.copyWith(
      breakdownOffsets: [markIndex - start],
    );
  }
  return Layer(
    id: const LayerId('layer'),
    name: 'Layer',
    frames: [
      Frame(id: const FrameId('a'), duration: 3, strokes: const []),
      Frame(id: const FrameId('b'), duration: 4, strokes: const []),
    ],
    timeline: timeline,
  );
}

_FrameEditingFixture _fixture(Layer layer, {HistoryManager? historyManager}) {
  final repository = ProjectRepository(initialProject: _project(layer));
  final controller = TimelineController(
    repository: repository,
    cutId: _cutId,
    historyManager: historyManager,
  );
  return _FrameEditingFixture(
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
            duration: 24,
            canvasSize: const CanvasSize(width: 1920, height: 1080),
            layers: [layer],
          ),
        ],
      ),
    ],
  );
}

Layer _latestLayer(ProjectRepository repository) {
  return repository.currentProject!.tracks.single.cuts.single.layers.single;
}

Frame _frame(Layer layer, FrameId frameId) {
  return layer.frames.singleWhere((frame) => frame.id == frameId);
}

class _FrameEditingFixture {
  const _FrameEditingFixture({
    required this.repository,
    required this.controller,
    required this.layer,
  });

  final ProjectRepository repository;
  final TimelineController controller;
  final Layer layer;
}
