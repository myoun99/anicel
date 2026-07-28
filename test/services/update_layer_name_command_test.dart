import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/editing_session_state.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
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
const _frameId = FrameId('frame-a');

void main() {
  group('CutCommandCoordinator.renameLayer', () {
    test(
      'changes name, undo restores old name, and redo reapplies new name',
      () {
        final fixture = _fixture();

        fixture.coordinator.renameLayer(
          cutId: _cutId,
          layerId: _layerBId,
          name: ' BG ',
        );

        expect(_cut(fixture.repository, _cutId).layers[1].name, 'BG');
        expect(fixture.history.undoCount, 1);

        fixture.history.undo();
        expect(_cut(fixture.repository, _cutId).layers[1].name, 'B');

        fixture.history.redo();
        expect(_cut(fixture.repository, _cutId).layers[1].name, 'BG');
      },
    );

    test('rejects an empty trimmed name without history', () {
      final fixture = _fixture();

      expect(
        () => fixture.coordinator.renameLayer(
          cutId: _cutId,
          layerId: _layerAId,
          name: '   ',
        ),
        throwsArgumentError,
      );

      expect(_cut(fixture.repository, _cutId).layers[0].name, 'A');
      expect(fixture.history.undoCount, 0);
    });

    test('allows duplicate layer names in the same Cut', () {
      final fixture = _fixture();

      fixture.coordinator.renameLayer(
        cutId: _cutId,
        layerId: _layerAId,
        name: 'B',
      );

      expect(
        _cut(fixture.repository, _cutId).layers.map((layer) => layer.name),
        ['B', 'B', 'C'],
      );
      expect(fixture.history.undoCount, 1);
    });

    test('unchanged trimmed name is a no-op without history', () {
      final fixture = _fixture();

      fixture.coordinator.renameLayer(
        cutId: _cutId,
        layerId: _layerAId,
        name: ' A ',
      );

      expect(_cut(fixture.repository, _cutId).layers[0].name, 'A');
      expect(fixture.history.undoCount, 0);
    });

    test(
      'preserves id, kind, frames, timeline, visibility, opacity, and order',
      () {
        final fixture = _fixture();
        final beforeCut = _cut(fixture.repository, _cutId);
        final beforeLayer = beforeCut.layers[1];
        final beforeOrder = beforeCut.layers.map((layer) => layer.id).toList();

        fixture.coordinator.renameLayer(
          cutId: _cutId,
          layerId: _layerBId,
          name: 'BG',
        );

        final afterCut = _cut(fixture.repository, _cutId);
        final afterLayer = afterCut.layers[1];
        expect(afterLayer.name, 'BG');
        expect(afterLayer.id, beforeLayer.id);
        expect(afterLayer.kind, beforeLayer.kind);
        expect(afterLayer.frames, beforeLayer.frames);
        expect(afterLayer.timeline, beforeLayer.timeline);
        expect(afterLayer.isVisible, beforeLayer.isVisible);
        expect(afterLayer.opacity, beforeLayer.opacity);
        expect(afterCut.layers.map((layer) => layer.id).toList(), beforeOrder);
      },
    );

    test('renaming in one Cut does not affect another Cut', () {
      final fixture = _fixture();

      fixture.coordinator.renameLayer(
        cutId: _cutId,
        layerId: _layerAId,
        name: 'BG',
      );

      expect(_cut(fixture.repository, _cutId).layers[0].name, 'BG');
      expect(_cut(fixture.repository, _otherCutId).layers.single.name, 'A');
    });
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
              _layer(id: _layerAId, name: 'A'),
              _layer(
                id: _layerBId,
                name: 'B',
                kind: LayerKind.storyboard,
                visible: false,
                opacity: 0.4,
              ),
              _layer(id: _layerCId, name: 'C'),
            ],
          ),
          Cut(
            id: _otherCutId,
            name: 'Cut 2',
            duration: 1,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            layers: [_layer(id: const LayerId('other-layer-a'), name: 'A')],
          ),
        ],
      ),
    ],
  );
}

Layer _layer({
  required LayerId id,
  required String name,
  LayerKind kind = LayerKind.animation,
  bool visible = true,
  double opacity = 1,
}) {
  return Layer(
    id: id,
    name: name,
    kind: kind,
    isVisible: visible,
    opacity: opacity,
    frames: [Frame(id: _frameId, duration: 2, strokes: const [], name: 'A1')],
    timeline: {
      0: TimelineExposure.drawing(
        _frameId,
        length: 2,
        breakdownOffsets: const [1],
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
