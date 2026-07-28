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
import 'package:anicel/src/services/project_repository.dart';

const _cutId = CutId('cut-1');
const _otherCutId = CutId('cut-2');
const _layerAId = LayerId('layer-a');
const _layerBId = LayerId('layer-b');
const _layerCId = LayerId('layer-c');
const _frameAId = FrameId('frame-a');
const _frameBId = FrameId('frame-b');

void main() {
  group('CutCommandCoordinator.deleteLayer', () {
    test('removes target layer and preserves remaining raw order', () {
      final fixture = _fixture();

      fixture.coordinator.deleteLayer(cutId: _cutId, layerId: _layerBId);

      expect(_layerNames(fixture.repository, _cutId), ['A', 'C']);
      expect(_layerIds(fixture.repository, _cutId), [_layerAId, _layerCId]);
      expect(fixture.history.undoCount, 1);
    });

    test(
      'undo restores deleted layer at same raw index and redo deletes again',
      () {
        final fixture = _fixture();
        final beforeLayer = _cut(fixture.repository, _cutId).layers[1];

        fixture.coordinator.deleteLayer(cutId: _cutId, layerId: _layerBId);
        fixture.history.undo();

        expect(_layerIds(fixture.repository, _cutId), [
          _layerAId,
          _layerBId,
          _layerCId,
        ]);
        expect(_cut(fixture.repository, _cutId).layers[1], beforeLayer);

        fixture.history.redo();
        expect(_layerIds(fixture.repository, _cutId), [_layerAId, _layerCId]);
      },
    );

    test('deleted layer snapshot is fully restored', () {
      final fixture = _fixture();
      final beforeLayer = _cut(fixture.repository, _cutId).layers[1];

      fixture.coordinator.deleteLayer(cutId: _cutId, layerId: _layerBId);
      fixture.history.undo();

      final restoredLayer = _cut(fixture.repository, _cutId).layers[1];
      expect(restoredLayer.id, beforeLayer.id);
      expect(restoredLayer.name, beforeLayer.name);
      expect(restoredLayer.kind, beforeLayer.kind);
      expect(restoredLayer.frames, beforeLayer.frames);
      expect(restoredLayer.timeline, beforeLayer.timeline);
      expect(restoredLayer.isVisible, beforeLayer.isVisible);
      expect(restoredLayer.opacity, beforeLayer.opacity);
      expect(restoredLayer, beforeLayer);
    });

    test('delete in one Cut does not affect another Cut', () {
      final fixture = _fixture();

      fixture.coordinator.deleteLayer(cutId: _cutId, layerId: _layerBId);

      expect(_layerNames(fixture.repository, _cutId), ['A', 'C']);
      expect(_layerNames(fixture.repository, _otherCutId), ['Other A']);
    });

    test('R28 #14: deleting the LAST layer is allowed — the cut may stand '
        'empty', (
    ) {
      final fixture = _fixture();

      fixture.coordinator.deleteLayer(cutId: _otherCutId, layerId: _layerAId);

      expect(
        _layerNames(fixture.repository, _otherCutId),
        isEmpty,
        reason: 'R28 #14: "액션 레이어가 1개도 없는상황 허용" — the floor that '
            'kept one layer alive is gone',
      );
      expect(fixture.history.undoCount, 1);

      fixture.history.undo();
      expect(_layerNames(fixture.repository, _otherCutId), ['Other A']);
    });

    test(
      'deleting Storyboard Layer allows another layer to become Storyboard',
      () {
        final fixture = _fixture();

        fixture.coordinator.deleteLayer(cutId: _cutId, layerId: _layerBId);
        fixture.coordinator.updateLayerKind(
          cutId: _cutId,
          layerId: _layerCId,
          kind: LayerKind.storyboard,
        );

        expect(
          _cut(
            fixture.repository,
            _cutId,
          ).layers.singleWhere((layer) => layer.id == _layerCId).kind,
          LayerKind.storyboard,
        );
      },
    );
  });
}

_Fixture _fixture() {
  final project = _project();
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

Cut _cut(ProjectRepository repository, CutId cutId) {
  for (final track in repository.requireProject().tracks) {
    for (final cut in track.cuts) {
      if (cut.id == cutId) {
        return cut;
      }
    }
  }
  throw StateError('Cut not found: $cutId');
}

List<LayerId> _layerIds(ProjectRepository repository, CutId cutId) {
  return _cut(repository, cutId).layers.map((layer) => layer.id).toList();
}

List<String> _layerNames(ProjectRepository repository, CutId cutId) {
  return _cut(repository, cutId).layers.map((layer) => layer.name).toList();
}

Project _project() {
  return Project(
    id: const ProjectId('project'),
    name: 'Project',
    createdAt: DateTime.utc(2026, 6, 12),
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
              _layer(_layerAId, 'A'),
              _layer(
                _layerBId,
                'B',
                kind: LayerKind.storyboard,
                isVisible: false,
                opacity: 0.42,
              ),
              _layer(_layerCId, 'C'),
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
