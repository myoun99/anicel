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
import 'package:anicel/src/services/project_repository.dart';

void main() {
  group('TimelineController responsibility baseline', () {
    test('current frame is cursor state and does not mutate project data', () {
      final fixture = _createResponsibilityFixture();
      final beforeProject = fixture.repository.requireProject();
      final beforeCut = fixture.cut;

      fixture.controller.selectFrameIndex(9);

      expect(fixture.controller.currentFrameIndex, 9);
      expect(fixture.repository.requireProject(), beforeProject);
      expect(fixture.cut, beforeCut);
    });

    test(
      'current frame selects resolved exposure without editing authored data',
      () {
        final fixture = _createResponsibilityFixture();
        final layer = fixture.layer(const LayerId('animation-a'));
        final beforeLayer = layer;

        fixture.controller.selectFrameIndex(4);

        expect(
          fixture.controller.resolveFrameIdForLayer(layer: layer),
          const FrameId('a-1'),
        );
        expect(fixture.layer(const LayerId('animation-a')), beforeLayer);
      },
    );

    test(
      'authored extent is calculated from authored data, not Cut.duration',
      () {
        final fixture = _createResponsibilityFixture(cutDuration: 24);

        expect(fixture.cut.duration, 24);
        expect(fixture.controller.authoredTimelineExtentFrameCount, 13);
        expect(
          fixture.controller.authoredTimelineExtentFrameCount,
          isNot(fixture.cut.duration),
        );
      },
    );

    test(
      'Cut.duration remains playback/export duration during timeline edits',
      () {
        final fixture = _createResponsibilityFixture(cutDuration: 3);

        fixture.controller.selectFrameIndex(10);
        fixture.controller.createDrawingFrameForLayer(
          layerId: const LayerId('empty-layer'),
          frameId: const FrameId('outside-playback'),
          length: 4,
        );

        final cut = fixture.cut;
        final editedLayer = fixture.layer(const LayerId('empty-layer'));

        expect(cut.duration, 3);
        expect(
          editedLayer.timeline[10]?.frameId,
          const FrameId('outside-playback'),
        );
        expect(fixture.controller.authoredTimelineExtentFrameCount, 14);
      },
    );

    test(
      'ordinary selection and read-only queries do not mutate Cut.duration',
      () {
        final fixture = _createResponsibilityFixture(cutDuration: 8);
        final layer = fixture.layer(const LayerId('animation-b'));

        fixture.controller.selectFrameIndex(12);
        fixture.controller.resolveFrameForLayer(layer: layer);
        fixture.controller.hasDrawingAtCurrentFrame(layer: layer);
        fixture.controller.isHeldExposureForLayer(layer: layer, frameIndex: 12);

        expect(fixture.cut.duration, 8);
      },
    );

    test('empty repository state is safe for cursor and authored extent', () {
      final repository = ProjectRepository();
      final controller = TimelineController(
        repository: repository,
        cutId: const CutId('missing-cut'),
      );

      controller.selectFrameIndex(5);

      expect(controller.currentFrameIndex, 5);
      expect(controller.authoredTimelineExtentFrameCount, 0);
    });

    test('empty cut and empty layer authored extents are zero', () {
      final emptyCutFixture = _createResponsibilityFixture(layers: const []);
      expect(emptyCutFixture.controller.authoredTimelineExtentFrameCount, 0);

      final emptyLayerFixture = _createResponsibilityFixture(
        layers: [
          Layer(
            id: const LayerId('only-empty-layer'),
            name: 'Only Empty Layer',
            frames: const [],
          ),
        ],
      );
      final emptyLayer = emptyLayerFixture.layer(
        const LayerId('only-empty-layer'),
      );

      expect(emptyLayerFixture.controller.authoredTimelineExtentFrameCount, 0);
      expect(
        emptyLayerFixture.controller.resolveFrameForLayer(
          layer: emptyLayer,
          frameIndex: 0,
        ),
        isNull,
      );
    });
  });
}

_ResponsibilityFixture _createResponsibilityFixture({
  int cutDuration = 6,
  List<Layer>? layers,
}) {
  final cut = Cut(
    id: const CutId('cut-a'),
    name: 'Cut A',
    duration: cutDuration,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
    layers: layers ?? _defaultLayers(),
  );
  final project = Project(
    id: const ProjectId('project-a'),
    name: 'Project A',
    tracks: [
      Track(id: const TrackId('track-a'), name: 'Track A', cuts: [cut]),
    ],
    createdAt: DateTime.utc(2026),
  );
  final repository = ProjectRepository(initialProject: project);
  final controller = TimelineController(
    repository: repository,
    cutId: const CutId('cut-a'),
  );

  return _ResponsibilityFixture(repository: repository, controller: controller);
}

List<Layer> _defaultLayers() => [
  Layer(
    id: const LayerId('animation-a'),
    name: 'Animation A',
    frames: [
      Frame(id: const FrameId('a-1'), duration: 4, strokes: const []),
      Frame(id: const FrameId('a-2'), duration: 2, strokes: const []),
    ],
    timeline: {
      0: TimelineExposure.drawing(const FrameId('a-1'), length: 7),
      7: TimelineExposure.drawing(const FrameId('a-2'), length: 2),
    },
  ),
  Layer(
    id: const LayerId('animation-b'),
    name: 'Animation B',
    frames: [Frame(id: const FrameId('b-1'), duration: 3, strokes: const [])],
    timeline: {10: TimelineExposure.drawing(const FrameId('b-1'), length: 3)},
  ),
  Layer(
    id: const LayerId('empty-layer'),
    name: 'Empty Layer',
    frames: const [],
  ),
];

class _ResponsibilityFixture {
  const _ResponsibilityFixture({
    required this.repository,
    required this.controller,
  });

  final ProjectRepository repository;
  final TimelineController controller;

  Cut get cut => repository.requireProject().tracks.single.cuts.single;

  Layer layer(LayerId layerId) => cut.layers.singleWhere(
    (layer) => layer.id == layerId,
    orElse: () => throw StateError('Layer not found: $layerId'),
  );
}
