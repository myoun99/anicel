import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/canvas_controller.dart';
import 'package:anicel/src/controllers/layer_controller.dart';
import 'package:anicel/src/controllers/timeline_controller.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/stroke.dart';
import 'package:anicel/src/models/stroke_id.dart';
import 'package:anicel/src/models/stroke_point.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  group('CanvasController', () {
    test('starts with no strokes', () {
      final fixture = _createFixture();

      expect(fixture.controller.strokes, isEmpty);
    });

    test('draw stroke', () {
      final fixture = _createFixture();

      fixture.controller.beginStroke(const Offset(10, 20));
      fixture.controller.updateStroke(const Offset(30, 40));
      fixture.controller.endStroke();

      final strokes = _findLayerFrame(
        fixture.repository,
        const LayerId('layer-1'),
      ).strokes;
      expect(strokes, hasLength(1));
      expect(strokes.single.points, hasLength(2));
      expect(strokes.single.points[0].x, 10);
      expect(strokes.single.points[0].y, 20);
      expect(strokes.single.points[1].x, 30);
      expect(strokes.single.points[1].y, 40);
    });

    test('ignores short stroke', () {
      final fixture = _createFixture();

      fixture.controller.beginStroke(const Offset(10, 20));
      fixture.controller.endStroke();

      expect(
        _findLayerFrame(fixture.repository, const LayerId('layer-1')).strokes,
        isEmpty,
      );
    });

    test('undo stroke', () {
      final fixture = _createFixture();

      _drawStroke(fixture.controller);
      fixture.controller.undo();

      expect(
        _findLayerFrame(fixture.repository, const LayerId('layer-1')).strokes,
        isEmpty,
      );
    });

    test('redo stroke', () {
      final fixture = _createFixture();

      _drawStroke(fixture.controller);
      fixture.controller.undo();
      fixture.controller.redo();

      expect(
        _findLayerFrame(fixture.repository, const LayerId('layer-1')).strokes,
        hasLength(1),
      );
    });

    test('cancel stroke', () {
      final fixture = _createFixture();

      fixture.controller.beginStroke(const Offset(10, 20));
      fixture.controller.updateStroke(const Offset(30, 40));
      fixture.controller.cancelStroke();
      fixture.controller.endStroke();

      expect(fixture.controller.activePoints, isEmpty);
      expect(
        _findLayerFrame(fixture.repository, const LayerId('layer-1')).strokes,
        isEmpty,
      );
    });

    test('drawing targets active layer', () {
      final fixture = _createFixture();

      fixture.layerController.selectLayer(const LayerId('layer-1'));
      _drawStroke(fixture.controller);

      expect(
        _findLayerFrame(fixture.repository, const LayerId('layer-1')).strokes,
        hasLength(1),
      );
      expect(
        _findLayerFrame(fixture.repository, const LayerId('layer-2')).strokes,
        isEmpty,
      );

      fixture.layerController.selectLayer(const LayerId('layer-2'));
      _drawStroke(fixture.controller);

      expect(
        _findLayerFrame(fixture.repository, const LayerId('layer-1')).strokes,
        hasLength(1),
      );
      expect(
        _findLayerFrame(fixture.repository, const LayerId('layer-2')).strokes,
        hasLength(1),
      );
    });

    test('undo active layer stroke', () {
      final fixture = _createFixture();

      fixture.layerController.selectLayer(const LayerId('layer-2'));
      _drawStroke(fixture.controller);
      fixture.controller.undo();

      expect(
        _findLayerFrame(fixture.repository, const LayerId('layer-1')).strokes,
        isEmpty,
      );
      expect(
        _findLayerFrame(fixture.repository, const LayerId('layer-2')).strokes,
        isEmpty,
      );
    });

    test('drawing uses current timeline frame', () {
      final fixture = _createFixture(
        layers: [
          Layer(
            id: const LayerId('layer-1'),
            name: 'Layer 1',
            frames: [
              Frame(
                id: const FrameId('frame-a'),
                duration: 1,
                strokes: const [],
              ),
              Frame(
                id: const FrameId('frame-b'),
                duration: 1,
                strokes: const [],
              ),
            ],
          ),
        ],
      );

      fixture.timelineController.selectFrameIndex(0);
      _drawStroke(fixture.controller);
      fixture.timelineController.selectFrameIndex(1);
      _drawStroke(fixture.controller);

      expect(
        _findFrameById(fixture.repository, const FrameId('frame-a')).strokes,
        hasLength(1),
      );
      expect(
        _findFrameById(fixture.repository, const FrameId('frame-b')).strokes,
        hasLength(1),
      );
    });

    test(
      'drawing on an empty timeline does not automatically create a frame',
      () {
        final fixture = _createFixture(
          layers: [
            Layer(
              id: const LayerId('layer-1'),
              name: 'Layer 1',
              frames: const [],
            ),
          ],
        );

        fixture.timelineController.selectFrameIndex(10);
        _drawStroke(fixture.controller);

        final layer = _findLayer(fixture.repository, const LayerId('layer-1'));
        expect(layer.frames, isEmpty);
        expect(layer.timeline, isEmpty);
        expect(
          fixture.timelineController.resolveFrameForLayer(
            layer: layer,
            frameIndex: 10,
          ),
          isNull,
        );
      },
    );

    test('drawing still targets active layer at current timeline frame', () {
      final fixture = _createFixture();

      fixture.layerController.selectLayer(const LayerId('layer-2'));
      fixture.timelineController.selectFrameIndex(0);
      _drawStroke(fixture.controller);

      expect(
        _findLayerFrame(fixture.repository, const LayerId('layer-1')).strokes,
        isEmpty,
      );
      expect(
        _findLayerFrame(fixture.repository, const LayerId('layer-2')).strokes,
        hasLength(1),
      );
    });

    test(
      'undo on different timeline frame moves first then removes stroke',
      () {
        final fixture = _createFixture();

        fixture.timelineController.selectFrameIndex(0);
        _drawStroke(fixture.controller);
        fixture.timelineController.selectFrameIndex(5);

        fixture.controller.undo();

        expect(fixture.timelineController.currentFrameIndex, 0);
        expect(
          _findLayerFrame(fixture.repository, const LayerId('layer-1')).strokes,
          hasLength(1),
        );

        fixture.controller.undo();

        expect(
          _findLayerFrame(fixture.repository, const LayerId('layer-1')).strokes,
          isEmpty,
        );
      },
    );

    test('undo on same timeline frame removes stroke immediately', () {
      final fixture = _createFixture();

      fixture.timelineController.selectFrameIndex(0);
      _drawStroke(fixture.controller);
      fixture.controller.undo();

      expect(fixture.timelineController.currentFrameIndex, 0);
      expect(
        _findLayerFrame(fixture.repository, const LayerId('layer-1')).strokes,
        isEmpty,
      );
    });

    test('redo active layer stroke', () {
      final fixture = _createFixture();

      fixture.layerController.selectLayer(const LayerId('layer-2'));
      _drawStroke(fixture.controller);
      fixture.controller.undo();
      fixture.controller.redo();

      expect(
        _findLayerFrame(fixture.repository, const LayerId('layer-1')).strokes,
        isEmpty,
      );
      expect(
        _findLayerFrame(fixture.repository, const LayerId('layer-2')).strokes,
        hasLength(1),
      );
    });

    group('active cut layer frame resolution', () {
      test('layerFramesForCut returns Cut A paintable data only', () {
        final fixture = _createTwoCutCanvasFixture();

        final layerFrames = fixture.controller.layerFramesForCut(
          const CutId('cut-a'),
        );

        expect(layerFrames, hasLength(1));
        expect(layerFrames.single.layer.id, const LayerId('layer-a'));
        expect(layerFrames.single.layer.name, 'Layer A');
        expect(layerFrames.single.frame.id, const FrameId('frame-a'));
        expect(layerFrames.single.frame.name, 'Frame A');
        expect(layerFrames.single.frame.strokes, hasLength(1));
      });

      test('layerFramesForCut returns Cut B paintable data only', () {
        final fixture = _createTwoCutCanvasFixture();

        final layerFrames = fixture.controller.layerFramesForCut(
          const CutId('cut-b'),
        );

        expect(layerFrames, hasLength(1));
        expect(layerFrames.single.layer.id, const LayerId('layer-b'));
        expect(layerFrames.single.layer.name, 'Layer B');
        expect(layerFrames.single.frame.id, const FrameId('frame-b'));
        expect(layerFrames.single.frame.name, 'Frame B');
        expect(layerFrames.single.frame.strokes, hasLength(2));
      });
    });
  });
}

const _cutId = CutId('cut-1');
const _frameId = FrameId('frame-1');

_CanvasFixture _createFixture({List<Layer>? layers}) {
  final repository = ProjectRepository(
    initialProject: _createSampleProject(layers: layers),
  );
  final historyManager = HistoryManager();
  final layerController = LayerController(
    repository: repository,
    historyManager: historyManager,
    cutId: _cutId,
    frameId: _frameId,
  );
  final timelineController = TimelineController(
    repository: repository,
    cutId: _cutId,
  );
  final controller = CanvasController(
    repository: repository,
    historyManager: historyManager,
    frameId: _frameId,
    layerController: layerController,
    timelineController: timelineController,
  );

  return _CanvasFixture(
    repository: repository,
    controller: controller,
    layerController: layerController,
    timelineController: timelineController,
  );
}

Project _createSampleProject({List<Layer>? layers}) {
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
            layers:
                layers ??
                [
                  Layer(
                    id: const LayerId('layer-1'),
                    name: 'Layer 1',
                    frames: [
                      Frame(id: _frameId, duration: 1, strokes: const []),
                    ],
                  ),
                  Layer(
                    id: const LayerId('layer-2'),
                    name: 'Layer 2',
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

Frame _findFrameById(ProjectRepository repository, FrameId frameId) {
  for (final track in repository.requireProject().tracks) {
    for (final cut in track.cuts) {
      for (final layer in cut.layers) {
        for (final frame in layer.frames) {
          if (frame.id == frameId) {
            return frame;
          }
        }
      }
    }
  }

  throw StateError('Frame not found.');
}

Frame _findLayerFrame(ProjectRepository repository, LayerId layerId) {
  for (final track in repository.requireProject().tracks) {
    for (final cut in track.cuts) {
      for (final layer in cut.layers) {
        if (layer.id == layerId) {
          return layer.frames.single;
        }
      }
    }
  }

  throw StateError('Layer not found.');
}

void _drawStroke(CanvasController controller) {
  controller.beginStroke(const Offset(10, 20));
  controller.updateStroke(const Offset(30, 40));
  controller.endStroke();
}

class _CanvasFixture {
  const _CanvasFixture({
    required this.repository,
    required this.controller,
    required this.layerController,
    required this.timelineController,
  });

  final ProjectRepository repository;
  final CanvasController controller;
  final LayerController layerController;
  final TimelineController timelineController;
}

_CanvasFixture _createTwoCutCanvasFixture() {
  final repository = ProjectRepository(initialProject: _createTwoCutProject());
  final historyManager = HistoryManager();
  final layerController = LayerController(
    repository: repository,
    historyManager: historyManager,
    cutId: const CutId('cut-a'),
    frameId: const FrameId('frame-a'),
  );
  final timelineController = TimelineController(
    repository: repository,
    cutId: const CutId('cut-a'),
  );
  final controller = CanvasController(
    repository: repository,
    historyManager: historyManager,
    frameId: const FrameId('frame-a'),
    layerController: layerController,
    timelineController: timelineController,
  );

  return _CanvasFixture(
    repository: repository,
    controller: controller,
    layerController: layerController,
    timelineController: timelineController,
  );
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
                    strokes: [_stroke('stroke-a-1')],
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
                    strokes: [_stroke('stroke-b-1'), _stroke('stroke-b-2')],
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

Stroke _stroke(String id) {
  return Stroke(
    id: StrokeId(id),
    points: const [StrokePoint(x: 0, y: 0), StrokePoint(x: 1, y: 1)],
    brushSettings: BrushSettings(),
  );
}
