import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/layer_controller.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  group('LayerController', () {
    test('exposes layers', () {
      final fixture = _createFixture();

      expect(fixture.controller.layers, hasLength(2));
    });

    test('selects active layer', () {
      final fixture = _createFixture();

      fixture.controller.selectLayer(const LayerId('layer-2'));

      expect(fixture.controller.activeLayerId, const LayerId('layer-2'));
      expect(fixture.controller.activeLayer?.name, 'B');
    });

    test('adds a layer', () {
      final fixture = _createFixture();

      fixture.controller.addLayerWithDefaults(
        layerId: const LayerId('layer-3'),
      );

      expect(fixture.controller.layers, hasLength(3));
      expect(fixture.controller.activeLayerId, const LayerId('layer-3'));
      expect(fixture.controller.activeLayer?.name, 'C');
      expect(fixture.controller.activeLayer?.frames, isEmpty);
      expect(fixture.controller.activeLayer?.timeline, isEmpty);
    });

    test('adds a default layer after the active layer in raw XSheet order', () {
      final fixture = _createFixture();
      fixture.controller.selectLayer(const LayerId('layer-2'));

      fixture.controller.addLayerWithDefaults(
        layerId: const LayerId('layer-3'),
      );

      expect(fixture.controller.layers.map((layer) => layer.name), [
        'A',
        'B',
        'C',
      ]);
      expect(fixture.controller.activeLayerId, const LayerId('layer-3'));
    });

    test('keeps raw order natural while adding above active visually', () {
      final fixture = _createSingleLayerFixture();

      expect(fixture.controller.layers.map((layer) => layer.name), ['A']);
      expect(fixture.controller.activeLayerId, const LayerId('layer-a'));

      fixture.controller.addLayerWithDefaults(
        layerId: const LayerId('layer-b'),
      );

      expect(fixture.controller.layers.map((layer) => layer.name), ['A', 'B']);
      expect(fixture.controller.activeLayerId, const LayerId('layer-b'));

      fixture.controller.addLayerWithDefaults(
        layerId: const LayerId('layer-c'),
      );

      expect(fixture.controller.layers.map((layer) => layer.name), [
        'A',
        'B',
        'C',
      ]);
      expect(fixture.controller.activeLayerId, const LayerId('layer-c'));
    });

    test('inserts a new raw layer immediately after active A', () {
      final fixture = _createThreeLayerFixture();
      fixture.controller.selectLayer(const LayerId('layer-a'));

      fixture.controller.addLayerWithDefaults(
        layerId: const LayerId('layer-d'),
      );

      expect(fixture.controller.layers.map((layer) => layer.name), [
        'A',
        'D',
        'B',
        'C',
      ]);
      expect(fixture.controller.activeLayerId, const LayerId('layer-d'));
    });

    test('toggles visibility', () {
      final fixture = _createFixture();

      fixture.controller.toggleLayerVisibility(const LayerId('layer-1'));
      expect(
        _findLayer(fixture.repository, const LayerId('layer-1')).isVisible,
        isFalse,
      );

      fixture.controller.toggleLayerVisibility(const LayerId('layer-1'));
      expect(
        _findLayer(fixture.repository, const LayerId('layer-1')).isVisible,
        isTrue,
      );
    });

    test('sets opacity', () {
      final fixture = _createFixture();

      fixture.controller.setLayerOpacity(
        layerId: const LayerId('layer-1'),
        opacity: 0.5,
      );

      expect(
        _findLayer(fixture.repository, const LayerId('layer-1')).opacity,
        0.5,
      );
    });

    test('a folder row rides the LAYER eye, static opacity (clamped) and '
        'the twirl — no folder-shaped methods at all', () {
      final fixture = _createFixture();
      const folderId = LayerId('folder-1');
      fixture.repository.insertLayer(
        cutId: const CutId('cut-1'),
        layer: createFolderLayer(id: folderId, name: 'F'),
      );
      Layer folder() =>
          _findLayer(fixture.repository, folderId);

      fixture.controller.toggleLayerVisibility(folderId);
      expect(folder().isVisible, isFalse);

      fixture.controller.setLayerOpacity(layerId: folderId, opacity: 1.7);
      expect(folder().opacity, 1.0, reason: 'clamped');

      fixture.controller.toggleLayerCollapsed(folderId);
      expect(folder().collapsed, isTrue);
    });

    test('throws for missing layers', () {
      final fixture = _createFixture();

      expect(
        () => fixture.controller.selectLayer(const LayerId('missing')),
        throwsStateError,
      );
      expect(
        () =>
            fixture.controller.toggleLayerVisibility(const LayerId('missing')),
        throwsStateError,
      );
      expect(
        () => fixture.controller.setLayerOpacity(
          layerId: const LayerId('missing'),
          opacity: 0.5,
        ),
        throwsStateError,
      );
    });

    group('active cut isolation', () {
      test('cut-a controller exposes only Cut A layers', () {
        final fixture = _createTwoCutFixture(const CutId('cut-a'));

        expect(fixture.controller.layers.map((layer) => layer.id), [
          const LayerId('layer-a'),
        ]);
        expect(fixture.controller.layers.single.name, 'Layer A');
      });

      test('cut-b controller exposes only Cut B layers', () {
        final fixture = _createTwoCutFixture(const CutId('cut-b'));

        expect(fixture.controller.layers.map((layer) => layer.id), [
          const LayerId('layer-b'),
        ]);
        expect(fixture.controller.layers.single.name, 'Layer B');
      });

      test('adding through cut-a controller updates Cut A only', () {
        final fixture = _createTwoCutFixture(const CutId('cut-a'));

        fixture.controller.addLayerWithDefaults(
          layerId: const LayerId('layer-a-added'),
          name: 'Layer A Added',
        );

        expect(
          _findCut(
            fixture.repository,
            const CutId('cut-a'),
          ).layers.map((layer) => layer.id),
          [const LayerId('layer-a'), const LayerId('layer-a-added')],
        );
        expect(
          _findCut(
            fixture.repository,
            const CutId('cut-b'),
          ).layers.map((layer) => layer.id),
          [const LayerId('layer-b')],
        );
      });

      test('adding through cut-b controller updates Cut B only', () {
        final fixture = _createTwoCutFixture(const CutId('cut-b'));

        fixture.controller.addLayerWithDefaults(
          layerId: const LayerId('layer-b-added'),
          name: 'Layer B Added',
        );

        expect(
          _findCut(
            fixture.repository,
            const CutId('cut-a'),
          ).layers.map((layer) => layer.id),
          [const LayerId('layer-a')],
        );
        expect(
          _findCut(
            fixture.repository,
            const CutId('cut-b'),
          ).layers.map((layer) => layer.id),
          [const LayerId('layer-b'), const LayerId('layer-b-added')],
        );
      });
    });
  });
}

const _cutId = CutId('cut-1');
const _frameId = FrameId('frame-1');

_LayerFixture _createFixture() {
  final repository = ProjectRepository(initialProject: _createSampleProject());
  final controller = LayerController(
    repository: repository,
    historyManager: HistoryManager(),
    cutId: _cutId,
    frameId: _frameId,
  );

  return _LayerFixture(repository: repository, controller: controller);
}

Project _createSampleProject() {
  return Project(
    id: const ProjectId('project-1'),
    name: 'Test Project',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('track-1'),
        name: 'Track 1',
        cuts: [
          Cut(
            id: _cutId,
            name: 'Cut 1',
            duration: 1,
            canvasSize: const CanvasSize(width: 100, height: 100),
            layers: [
              Layer(
                id: const LayerId('layer-1'),
                name: 'A',
                frames: [Frame(id: _frameId, duration: 1, strokes: const [])],
              ),
              Layer(
                id: const LayerId('layer-2'),
                name: 'B',
                frames: [
                  Frame(
                    id: const FrameId('frame-2'),
                    duration: 1,
                    strokes: const [],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

_LayerFixture _createSingleLayerFixture() {
  final repository = ProjectRepository(
    initialProject: _projectWithLayers([_testLayer(id: 'layer-a', name: 'A')]),
  );
  final controller = LayerController(
    repository: repository,
    historyManager: HistoryManager(),
    cutId: _cutId,
    frameId: _frameId,
  );

  return _LayerFixture(repository: repository, controller: controller);
}

_LayerFixture _createThreeLayerFixture() {
  final repository = ProjectRepository(
    initialProject: _projectWithLayers([
      _testLayer(id: 'layer-a', name: 'A'),
      _testLayer(id: 'layer-b', name: 'B'),
      _testLayer(id: 'layer-c', name: 'C'),
    ]),
  );
  final controller = LayerController(
    repository: repository,
    historyManager: HistoryManager(),
    cutId: _cutId,
    frameId: _frameId,
  );

  return _LayerFixture(repository: repository, controller: controller);
}

Project _projectWithLayers(List<Layer> layers) {
  return Project(
    id: const ProjectId('project-layers'),
    name: 'Layer Order Test Project',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('track-1'),
        name: 'Track 1',
        cuts: [
          Cut(
            id: _cutId,
            name: 'Cut 1',
            duration: 1,
            canvasSize: const CanvasSize(width: 100, height: 100),
            layers: layers,
          ),
        ],
      ),
    ],
  );
}

Layer _testLayer({required String id, required String name}) {
  return Layer(
    id: LayerId(id),
    name: name,
    frames: [Frame(id: _frameId, duration: 1, strokes: const [])],
  );
}

Layer _findLayer(ProjectRepository repository, LayerId layerId) {
  for (final track in repository.requireProject().tracks) {
    for (final cut in track.cuts) {
      for (final layer in cut.layers) {
        if (layer.id == layerId) {
          return layer;
        }
      }
    }
  }
  throw StateError('Layer not found.');
}

class _LayerFixture {
  const _LayerFixture({required this.repository, required this.controller});

  final ProjectRepository repository;
  final LayerController controller;
}

_LayerFixture _createTwoCutFixture(CutId cutId) {
  final repository = ProjectRepository(initialProject: _createTwoCutProject());
  final controller = LayerController(
    repository: repository,
    historyManager: HistoryManager(),
    cutId: cutId,
    frameId: const FrameId('frame-a'),
  );

  return _LayerFixture(repository: repository, controller: controller);
}

Project _createTwoCutProject() {
  return Project(
    id: const ProjectId('two-cut-project'),
    name: 'Two Cut Test Project',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('track-1'),
        name: 'Track 1',
        cuts: [
          Cut(
            id: const CutId('cut-a'),
            name: 'Cut A',
            duration: 12,
            canvasSize: const CanvasSize(width: 100, height: 100),
            layers: [
              Layer(
                id: const LayerId('layer-a'),
                name: 'Layer A',
                frames: [
                  Frame(
                    id: const FrameId('frame-a'),
                    duration: 4,
                    strokes: const [],
                    name: 'Frame A',
                  ),
                ],
                timeline: {
                  0: TimelineExposure.drawing(
                    const FrameId('frame-a'),
                    length: 1,
                  ),
                },
              ),
            ],
          ),
          Cut(
            id: const CutId('cut-b'),
            name: 'Cut B',
            duration: 8,
            canvasSize: const CanvasSize(width: 100, height: 100),
            layers: [
              Layer(
                id: const LayerId('layer-b'),
                name: 'Layer B',
                frames: [
                  Frame(
                    id: const FrameId('frame-b'),
                    duration: 2,
                    strokes: const [],
                    name: 'Frame B',
                  ),
                ],
                timeline: {
                  0: TimelineExposure.drawing(
                    const FrameId('frame-b'),
                    length: 1,
                  ),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

Cut _findCut(ProjectRepository repository, CutId cutId) {
  for (final track in repository.requireProject().tracks) {
    for (final cut in track.cuts) {
      if (cut.id == cutId) {
        return cut;
      }
    }
  }
  throw StateError('Cut not found.');
}
