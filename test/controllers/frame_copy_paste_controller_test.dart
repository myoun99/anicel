import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_exposure_type.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  group('linked frame copy/paste controller APIs', () {
    test('canPasteLinkedFrameAt validates index and frame existence', () {
      final fixture = _fixture(_layer());
      final layer = fixture.layer;

      expect(
        fixture.controller.canPasteLinkedFrameAt(
          layer: layer,
          frameIndex: -1,
          copiedFrameId: const FrameId('a'),
        ),
        isFalse,
      );
      expect(
        fixture.controller.canPasteLinkedFrameAt(
          layer: layer,
          frameIndex: 0,
          copiedFrameId: const FrameId('missing'),
        ),
        isFalse,
      );
      expect(
        fixture.controller.canPasteLinkedFrameAt(
          layer: layer,
          frameIndex: 0,
          copiedFrameId: const FrameId('a'),
        ),
        isTrue,
      );
    });

    test('paste linked frame on an empty X cell creates a drawing entry', () {
      final fixture = _fixture(_layer());
      fixture.controller.selectFrameIndex(3);

      fixture.controller.pasteLinkedFrameForLayer(
        layerId: const LayerId('layer'),
        frameId: const FrameId('a'),
      );
      final layer = _latestLayer(fixture.repository);

      expect(layer.timeline[3]?.type, TimelineExposureType.drawing);
      expect(layer.timeline[3]?.frameId, const FrameId('a'));
      expect(
        layer.frames.map((frame) => frame.id),
        contains(const FrameId('a')),
      );
    });

    test('paste linked frame on drawingStart replaces old drawing entry', () {
      final fixture = _fixture(_layer());
      fixture.controller.selectFrameIndex(5);

      fixture.controller.pasteLinkedFrameForLayer(
        layerId: const LayerId('layer'),
        frameId: const FrameId('a'),
      );
      final layer = _latestLayer(fixture.repository);

      expect(layer.timeline[5]?.frameId, const FrameId('a'));
      expect(
        layer.timeline.values.where((e) => e.frameId == const FrameId('a')),
        hasLength(3),
      );
    });

    /// 🚨T3 — 「replacing drawingStart」 was the RELINK, and it is retired: a
    /// paste on a block start inserts before that block rather than taking
    /// it over. ⛔Do not restore it.
    ///
    /// The bookkeeping it carried does survive, because it was never really
    /// about relinking: a cel that loses its last exposure leaves with it.
    /// These two now reach that rule the way anything else does — the lift
    /// half of the splice — instead of through a placement branch.
    test('a cel the splice orphaned goes with it', () {
      final fixture = _fixture(
        _layer(
          timeline: {
            0: TimelineExposure.drawing(const FrameId('a'), length: 1),
            5: TimelineExposure.drawing(const FrameId('b'), length: 1),
          },
        ),
      );

      fixture.controller.spliceRunsForLayers(
        runs: [
          (
            layerId: const LayerId('layer'),
            index: 5,
            liftCount: 1,
            clip: null,
            bornFrames: const <Frame>[],
          ),
        ],
        description: 'test',
      );

      expect(
        _latestLayer(fixture.repository).frames.map((frame) => frame.id),
        orderedEquals([const FrameId('a')]),
      );
    });

    test('a cel another exposure still points at stays', () {
      final fixture = _fixture(
        _layer(
          timeline: {
            0: TimelineExposure.drawing(const FrameId('a'), length: 1),
            5: TimelineExposure.drawing(const FrameId('b'), length: 1),
            9: TimelineExposure.drawing(const FrameId('b'), length: 1),
          },
        ),
      );

      fixture.controller.spliceRunsForLayers(
        runs: [
          (
            layerId: const LayerId('layer'),
            index: 5,
            liftCount: 1,
            clip: null,
            bornFrames: const <Frame>[],
          ),
        ],
        description: 'test',
      );

      expect(
        _latestLayer(fixture.repository).frames.map((frame) => frame.id),
        orderedEquals([const FrameId('a'), const FrameId('b')]),
      );
      expect(
        _latestLayer(fixture.repository).timeline[9]?.frameId,
        const FrameId('b'),
        reason: '⑳ — the hole stays open, so the surviving b never moved. '
            'What this test is really about is that it SURVIVED: another '
            'exposure still points at that cel, so the lift may not take it',
      );
    });

    test(
      'paste linked frame on held drawing creates authored drawingStart',
      () {
        final fixture = _fixture(_layer());
        fixture.controller.selectFrameIndex(1);

        fixture.controller.pasteLinkedFrameForLayer(
          layerId: const LayerId('layer'),
          frameId: const FrameId('b'),
        );

        expect(
          _latestLayer(fixture.repository).timeline[1]?.frameId,
          const FrameId('b'),
        );
      },
    );

    test(
      'paste linked frame inside an X run creates authored drawingStart',
      () {
        final fixture = _fixture(_layer());
        fixture.controller.selectFrameIndex(4);

        fixture.controller.pasteLinkedFrameForLayer(
          layerId: const LayerId('layer'),
          frameId: const FrameId('a'),
        );

        expect(
          _latestLayer(fixture.repository).timeline[4]?.frameId,
          const FrameId('a'),
        );
      },
    );

    test('paste linked frame on empty creates authored drawingStart', () {
      final fixture = _fixture(_layer(timeline: const {}));
      fixture.controller.selectFrameIndex(6);

      fixture.controller.pasteLinkedFrameForLayer(
        layerId: const LayerId('layer'),
        frameId: const FrameId('a'),
      );

      expect(
        _latestLayer(fixture.repository).timeline[6]?.frameId,
        const FrameId('a'),
      );
    });

    test('paste linked frame does not create a new Frame or clone strokes', () {
      final fixture = _fixture(_layer());
      final beforeFrames = fixture.layer.frames;
      fixture.controller.selectFrameIndex(3);

      fixture.controller.pasteLinkedFrameForLayer(
        layerId: const LayerId('layer'),
        frameId: const FrameId('a'),
      );
      final layer = _latestLayer(fixture.repository);

      expect(layer.frames, beforeFrames);
      expect(_frame(layer, const FrameId('a')).strokes, _sampleStrokes);
    });

    test('linked uses hold independent lengths and edge shifts touch the '
        'selected use only', () {
      final fixture = _fixture(
        _layer(
          timeline: {
            0: TimelineExposure.drawing(const FrameId('a'), length: 4),
          },
        ),
      );
      fixture.controller.selectFrameIndex(8);
      fixture.controller.pasteLinkedFrameForLayer(
        layerId: const LayerId('layer'),
        frameId: const FrameId('a'),
      );

      fixture.controller.shiftExposureEdge(
        layerId: const LayerId('layer'),
        blockStartIndex: 8,
        edge: TimelineBlockEdge.end,
        delta: 1,
      );

      final layer = _latestLayer(fixture.repository);
      expect(layer.timeline.keys, orderedEquals([0, 8]));
      expect(_frame(layer, const FrameId('a')).strokes, _sampleStrokes);
      expect(
        fixture.controller.linkedUseCountForLayerFrame(
          layer: layer,
          frameId: const FrameId('a'),
        ),
        2,
      );
      expect(
        fixture.controller.effectiveDurationForLayerAt(
          layer: layer,
          frameIndex: 8,
        ),
        2,
      );
      expect(
        fixture.controller.effectiveDurationForLayerFrame(
          layer: layer,
          frameId: const FrameId('a'),
        ),
        4,
      );
    });

    test('paste linked frame is undo and redo able', () {
      final history = HistoryManager();
      final fixture = _fixture(_layer(), historyManager: history);
      fixture.controller.selectFrameIndex(3);

      fixture.controller.pasteLinkedFrameForLayer(
        layerId: const LayerId('layer'),
        frameId: const FrameId('a'),
      );
      expect(
        _latestLayer(fixture.repository).timeline[3]?.frameId,
        const FrameId('a'),
      );

      history.undo();
      expect(_latestLayer(fixture.repository).timeline.containsKey(3), isFalse);

      history.redo();
      expect(
        _latestLayer(fixture.repository).timeline[3]?.frameId,
        const FrameId('a'),
      );
    });

    test(
      'linked use count tracks authored drawing exposures without dense frames',
      () {
        final fixture = _fixture(_layer());

        expect(
          fixture.controller.linkedUseCountForLayerFrame(
            layer: fixture.layer,
            frameId: const FrameId('b'),
          ),
          1,
        );

        fixture.controller.selectFrameIndex(3);
        fixture.controller.pasteLinkedFrameForLayer(
          layerId: const LayerId('layer'),
          frameId: const FrameId('b'),
        );
        final layer = _latestLayer(fixture.repository);

        expect(
          fixture.controller.linkedUseCountForLayerFrame(
            layer: layer,
            frameId: const FrameId('b'),
          ),
          2,
        );
        // 🚨T3: the keys after 3 each moved by the clip's one cell. The old
        // paste dropped into the gap without disturbing anything, which is
        // the same rule that decided its length for it.
        expect(layer.timeline.keys, orderedEquals([0, 3, 6, 10]));
        expect(layer.frames, hasLength(2));
      },
    );
  });

  /// ㉕ 독립 붙여넣기. The linked paste puts the SAME cel at a second place,
  /// which is the feature; this one puts a cel that came FROM it and owes it
  /// nothing afterwards. The two share their placement rules on purpose —
  /// only which cel the exposure names is different.
  group('independent frame paste', () {
    test('it makes a NEW cel, where the linked paste reuses the old one', () {
      final fixture = _fixture(_layer());
      fixture.controller.selectFrameIndex(3);

      fixture.controller.pasteIndependentFrameForLayer(
        layerId: const LayerId('layer'),
        frameId: const FrameId('a'),
        newFrameId: const FrameId('a-copy'),
      );

      final layer = fixture.repository.requireProject().tracks.single.cuts
          .single
          .layers
          .single;
      expect(
        layer.frames.map((frame) => frame.id.value),
        containsAll(<String>['a', 'a-copy']),
        reason: 'the source stays, and the copy is a cel of its own',
      );
      expect(layer.timeline[3]?.frameId, const FrameId('a-copy'));
      expect(
        layer.timeline[0]?.frameId,
        const FrameId('a'),
        reason: 'the cel it came from is untouched where it already was',
      );
    });

    test('the copy carries the content and NOT the identity — drawing on one '
        'can never reach the other', () {
      final fixture = _fixture(_layer());
      fixture.controller.selectFrameIndex(3);

      fixture.controller.pasteIndependentFrameForLayer(
        layerId: const LayerId('layer'),
        frameId: const FrameId('a'),
        newFrameId: const FrameId('a-copy'),
      );

      final layer = fixture.repository.requireProject().tracks.single.cuts
          .single
          .layers
          .single;
      final source = layer.frames.firstWhere(
        (frame) => frame.id == const FrameId('a'),
      );
      final copy = layer.frames.firstWhere(
        (frame) => frame.id == const FrameId('a-copy'),
      );
      expect(copy.strokes, hasLength(source.strokes.length));
      for (var index = 0; index < source.strokes.length; index += 1) {
        expect(
          identical(copy.strokes[index], source.strokes[index]),
          isFalse,
          reason: 'a shared stroke object is a link wearing a copy\'s name',
        );
      }
    });

    test('the copy comes out UNNAMED — a name is the identity that would '
        'link it right back to the cel it came from', () {
      final named = _layer(
        frames: [
          Frame(
            id: const FrameId('a'),
            duration: 1,
            strokes: _sampleStrokes,
            name: 'A1',
          ),
          Frame(id: const FrameId('b'), duration: 1, strokes: const []),
        ],
      );
      final fixture = _fixture(named);
      fixture.controller.selectFrameIndex(3);

      fixture.controller.pasteIndependentFrameForLayer(
        layerId: const LayerId('layer'),
        frameId: const FrameId('a'),
        newFrameId: const FrameId('a-copy'),
      );

      final layer = fixture.repository.requireProject().tracks.single.cuts
          .single
          .layers
          .single;
      expect(
        layer.frames
            .firstWhere((frame) => frame.id == const FrameId('a-copy'))
            .name,
        isNull,
      );
      expect(
        layer.frames
            .firstWhere((frame) => frame.id == const FrameId('a'))
            .name,
        'A1',
        reason: 'the source keeps the name it had',
      );
      // The invariant a rename enforces and this path must not slip past:
      // inside a layer, a name belongs to exactly one cel.
      final names = layer.frames
          .map((frame) => frame.name)
          .whereType<String>()
          .toList();
      expect(names.toSet(), hasLength(names.length));
    });

    test('it lands the SAME way the linked paste does — one splice, and '
        'only the cel differs', () {
      final fixture = _fixture(_layer());
      fixture.controller.selectFrameIndex(1);

      fixture.controller.pasteIndependentFrameForLayer(
        layerId: const LayerId('layer'),
        frameId: const FrameId('b'),
        newFrameId: const FrameId('b-copy'),
      );

      final layer = fixture.repository.requireProject().tracks.single.cuts
          .single
          .layers
          .single;
      expect(layer.timeline[0]?.length, 1, reason: 'the hold splits here');
      expect(layer.timeline[1]?.frameId, const FrameId('b-copy'));
      // 🚨T3: the clip's length, not the rest of the hold it split. The old
      // rule handed the tail's cells to the pasted cel; now the tail keeps
      // them, still pointing at the cel that owned them.
      expect(layer.timeline[1]?.length, 1);
      expect(layer.timeline[2]?.frameId, const FrameId('a'));
    });

    test('a copied id the layer does not have is refused, like the linked '
        'paste refuses it', () {
      final fixture = _fixture(_layer());
      fixture.controller.selectFrameIndex(3);

      fixture.controller.pasteIndependentFrameForLayer(
        layerId: const LayerId('layer'),
        frameId: const FrameId('missing'),
        newFrameId: const FrameId('nope'),
      );

      final layer = fixture.repository.requireProject().tracks.single.cuts
          .single
          .layers
          .single;
      expect(layer.frames, hasLength(2));
      expect(layer.timeline.keys, orderedEquals([0, 5, 9]));
    });
  });
}

const _cutId = CutId('cut');
final _sampleStrokes = [
  Stroke(
    id: const StrokeId('stroke-a'),
    points: const [StrokePoint(x: 1, y: 2), StrokePoint(x: 3, y: 4)],
    brushSettings: BrushSettings(size: 8),
  ),
];

/// Default: a[0,3) .. X[3,5) .. b[5,9) .. a[9,12).
Layer _layer({Map<int, TimelineExposure>? timeline, List<Frame>? frames}) {
  return Layer(
    id: const LayerId('layer'),
    name: 'Layer',
    frames:
        frames ??
        [
          Frame(id: const FrameId('a'), duration: 3, strokes: _sampleStrokes),
          Frame(id: const FrameId('b'), duration: 4, strokes: const []),
        ],
    timeline:
        timeline ??
        {
          0: TimelineExposure.drawing(const FrameId('a'), length: 3),
          5: TimelineExposure.drawing(const FrameId('b'), length: 4),
          9: TimelineExposure.drawing(const FrameId('a'), length: 3),
        },
  );
}

_FrameCopyPasteFixture _fixture(Layer layer, {HistoryManager? historyManager}) {
  final repository = ProjectRepository(initialProject: _project(layer));
  final controller = TimelineController(
    repository: repository,
    cutId: _cutId,
    historyManager: historyManager,
  );
  return _FrameCopyPasteFixture(
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

class _FrameCopyPasteFixture {
  const _FrameCopyPasteFixture({
    required this.repository,
    required this.controller,
    required this.layer,
  });

  final ProjectRepository repository;
  final TimelineController controller;
  final Layer layer;
}
