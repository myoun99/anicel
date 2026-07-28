import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/editing_session_state.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';

const _cutId = CutId('cut-1');
const _otherCutId = CutId('cut-2');
const _layerAId = LayerId('layer-a');
const _layerBId = LayerId('layer-b');
const _layerCId = LayerId('layer-c');
const _frameAId = FrameId('frame-a');
const _frameBId = FrameId('frame-b');

void main() {
  group('CutCommandCoordinator.duplicateLayer', () {
    test('inserts copy after source with new id and source name', () {
      final fixture = _fixture();

      final duplicateId = fixture.coordinator.duplicateLayer(
        cutId: _cutId,
        sourceLayerId: _layerBId,
      );

      final layers = requireCut(
        fixture.repository.requireProject(),
        _cutId,
      ).layers;
      expect(layers.map((layer) => layer.id), [
        _layerAId,
        _layerBId,
        duplicateId,
        _layerCId,
      ]);
      expect(layers[1].id, _layerBId);
      expect(layers[2].id, isNot(_layerBId));
      expect(layers[2].name, 'B');
      expect(fixture.history.undoCount, 1);
    });

    test('duplicating B in A/B/C creates raw A/B/B/C names', () {
      final fixture = _fixture();

      fixture.coordinator.duplicateLayer(
        cutId: _cutId,
        sourceLayerId: _layerBId,
      );

      expect(_layerNames(fixture.repository, _cutId), ['A', 'B', 'B', 'C']);
    });

    test('preserves copied content without reusing frame ids', () {
      final fixture = _fixture();
      final source = requireLayer(
        fixture.repository.requireProject(),
        cutId: _cutId,
        layerId: _layerBId,
      );

      final duplicateId = fixture.coordinator.duplicateLayer(
        cutId: _cutId,
        sourceLayerId: _layerBId,
      );

      final duplicate = requireLayer(
        fixture.repository.requireProject(),
        cutId: _cutId,
        layerId: duplicateId,
      );
      expect(duplicate.isVisible, source.isVisible);
      expect(duplicate.opacity, source.opacity);
      expect(duplicate.frames.length, source.frames.length);
      expect(duplicate.frames.first.id, isNot(source.frames.first.id));
      expect(duplicate.frames.first.name, source.frames.first.name);
      // The memo lives on the EXPOSURE, so the copy carries it there.
      expect(duplicate.timeline[0]!.memo, source.timeline[0]!.memo);
      expect(duplicate.timeline.keys, source.timeline.keys);
      expect(duplicate.timeline[0]!.frameId, duplicate.frames.first.id);
      expect(
        duplicate.timeline[0]!.frameId,
        isNot(source.timeline[0]!.frameId),
      );
    });

    test(
      'undo removes duplicate and redo restores same layer at same index',
      () {
        final fixture = _fixture();
        final duplicateId = fixture.coordinator.duplicateLayer(
          cutId: _cutId,
          sourceLayerId: _layerBId,
        );
        final duplicate = requireLayer(
          fixture.repository.requireProject(),
          cutId: _cutId,
          layerId: duplicateId,
        );

        fixture.history.undo();
        expect(_layerIds(fixture.repository, _cutId), [
          _layerAId,
          _layerBId,
          _layerCId,
        ]);

        fixture.history.redo();
        final layers = requireCut(
          fixture.repository.requireProject(),
          _cutId,
        ).layers;
        expect(layers.map((layer) => layer.id), [
          _layerAId,
          _layerBId,
          duplicateId,
          _layerCId,
        ]);
        expect(layers[2], duplicate);
      },
    );

    test('duplicating one Cut does not affect another Cut', () {
      final fixture = _fixture();

      fixture.coordinator.duplicateLayer(
        cutId: _cutId,
        sourceLayerId: _layerBId,
      );

      expect(_layerNames(fixture.repository, _otherCutId), ['Other A']);
    });

    test(
      'Animation duplicates as Animation and Storyboard duplicates as Animation',
      () {
        final fixture = _fixture();

        final animationDuplicateId = fixture.coordinator.duplicateLayer(
          cutId: _cutId,
          sourceLayerId: _layerAId,
        );
        final storyboardDuplicateId = fixture.coordinator.duplicateLayer(
          cutId: _cutId,
          sourceLayerId: _layerBId,
        );

        expect(
          requireLayer(
            fixture.repository.requireProject(),
            cutId: _cutId,
            layerId: animationDuplicateId,
          ).kind,
          LayerKind.animation,
        );
        expect(
          requireLayer(
            fixture.repository.requireProject(),
            cutId: _cutId,
            layerId: storyboardDuplicateId,
          ).kind,
          LayerKind.animation,
        );
        expect(
          requireCut(
            fixture.repository.requireProject(),
            _cutId,
          ).layers.where((layer) => layer.kind == LayerKind.storyboard).length,
          1,
        );
      },
    );
  });
}

_Fixture _fixture({List<String> names = const ['A', 'B', 'C']}) {
  final project = _project(names: names);
  final repository = ProjectRepository(initialProject: project);
  final history = HistoryManager();
  return _Fixture(
    repository: repository,
    history: history,
    coordinator: CutCommandCoordinator(
      repository: repository,
      editingSession: EditingSessionState.forProject(project),
      historyManager: history,
    ),
  );
}

Project _project({required List<String> names}) {
  return Project(
    id: const ProjectId('project'),
    name: 'Project',
    createdAt: DateTime.utc(2026, 6, 14),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Track',
        cuts: [
          Cut(
            id: _cutId,
            name: 'Cut 1',
            duration: 3,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            layers: [
              _layer(_layerAId, names[0]),
              _layer(
                _layerBId,
                names[1],
                kind: LayerKind.storyboard,
                isVisible: false,
                opacity: 0.42,
              ),
              _layer(_layerCId, names[2]),
            ],
          ),
          Cut(
            id: _otherCutId,
            name: 'Cut 2',
            duration: 1,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            layers: [_layer(_layerAId, 'Other A')],
          ),
        ],
      ),
    ],
  );
}

Layer _layer(
  LayerId id,
  String name, {
  LayerKind kind = LayerKind.animation,
  bool isVisible = true,
  double opacity = 1.0,
}) {
  return Layer(
    id: id,
    name: name,
    kind: kind,
    isVisible: isVisible,
    opacity: opacity,
    frames: [
      Frame(
        id: _frameAId,
        duration: 2,
        strokes: const [],
        name: '$name-1',
      ),
      Frame(id: _frameBId, duration: 1, strokes: const [], name: '$name-2'),
    ],
    timeline: {
      0: TimelineExposure.drawing(
        _frameAId,
        length: 2,
        memo: const ExposureMemo(actionMemo: 'action', note: 'note'),
      ),
    },
  );
}

List<LayerId> _layerIds(ProjectRepository repository, CutId cutId) {
  return requireCut(
    repository.requireProject(),
    cutId,
  ).layers.map((layer) => layer.id).toList();
}

List<String> _layerNames(ProjectRepository repository, CutId cutId) {
  return requireCut(
    repository.requireProject(),
    cutId,
  ).layers.map((layer) => layer.name).toList();
}

class _Fixture {
  const _Fixture({
    required this.repository,
    required this.history,
    required this.coordinator,
  });

  final ProjectRepository repository;
  final HistoryManager history;
  final CutCommandCoordinator coordinator;
}
