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

/// TimelineController on the unified model: drawing blocks with explicit
/// lengths cover `[start, start+length)`; everything uncovered is empty
/// ("X"); marks annotate without forming blocks. (Comma edge shifts have
/// their own suite in timeline_comma_shift_test.dart.)
void main() {
  group('coverage queries', () {
    test('covered cells resolve their block frame, uncovered cells resolve '
        'nothing', () {
      final fixture = _fixture();
      final layer = fixture.layer;

      expect(
        fixture.controller.resolveFrameIdForLayer(layer: layer, frameIndex: 0),
        const FrameId('a'),
      );
      expect(
        fixture.controller.resolveFrameIdForLayer(layer: layer, frameIndex: 2),
        const FrameId('a'),
      );
      // Past the block's explicit end: empty, NOT an endless trailing hold.
      expect(
        fixture.controller.resolveFrameIdForLayer(layer: layer, frameIndex: 3),
        isNull,
      );
      expect(
        fixture.controller.resolveFrameIdForLayer(layer: layer, frameIndex: 6),
        const FrameId('b'),
      );
    });

    test('drawing start and held cells classify by coverage', () {
      final fixture = _fixture();
      final layer = fixture.layer;

      expect(
        fixture.controller.isDrawingStartForLayer(layer: layer, frameIndex: 0),
        isTrue,
      );
      expect(
        fixture.controller.isHeldExposureForLayer(layer: layer, frameIndex: 1),
        isTrue,
      );
      expect(
        fixture.controller.isHeldExposureForLayer(layer: layer, frameIndex: 3),
        isFalse,
      );
      expect(
        fixture.controller.isDrawingStartForLayer(layer: layer, frameIndex: 6),
        isTrue,
      );
    });

    test('effective duration is the block length', () {
      final fixture = _fixture();

      expect(
        fixture.controller.effectiveDurationForLayerFrame(
          layer: fixture.layer,
          frameId: const FrameId('a'),
        ),
        3,
      );
      fixture.controller.selectFrameIndex(7);
      expect(
        fixture.controller.effectiveDurationForLayerAt(layer: fixture.layer),
        2,
      );
    });

    test('authored extent is the max block end across layers', () {
      final fixture = _fixture();

      expect(fixture.controller.authoredTimelineExtentFrameCount, 8);
    });

    test('negative indexes and empty timelines answer safely', () {
      final fixture = _fixture(timeline: const {});

      expect(
        fixture.controller.resolveFrameForLayer(
          layer: fixture.layer,
          frameIndex: 0,
        ),
        isNull,
      );
      expect(
        fixture.controller.isDrawingStartForLayer(
          layer: fixture.layer,
          frameIndex: -1,
        ),
        isFalse,
      );
      expect(fixture.controller.authoredTimelineExtentFrameCount, 0);
    });
  });

  group('createDrawingFrameForLayer', () {
    test('creates on an empty cell with a one-frame default length', () {
      final fixture = _fixture();
      fixture.controller.selectFrameIndex(4);

      fixture.controller.createDrawingFrameForLayer(
        layerId: _layerId,
        frameId: const FrameId('new'),
      );

      final layer = fixture.layer;
      expect(
        layer.timeline[4],
        TimelineExposure.drawing(const FrameId('new'), length: 1),
      );
      expect(
        layer.frames.map((frame) => frame.id),
        contains(const FrameId('new')),
      );
    });

    test('clamps the requested length against the next block', () {
      final fixture = _fixture();
      fixture.controller.selectFrameIndex(4);

      fixture.controller.createDrawingFrameForLayer(
        layerId: _layerId,
        frameId: const FrameId('new'),
        length: 10,
      );

      // The next block starts at 6.
      expect(fixture.layer.timeline[4]!.length, 2);
    });

    test('DIVIDES a covered cell instead of refusing it: the new drawing '
        'takes over the rest of the hold', () {
      final fixture = _fixture();
      fixture.controller.selectFrameIndex(1);

      expect(
        fixture.controller.canCreateDrawingAt(
          layer: fixture.layer,
          frameIndex: 1,
        ),
        isTrue,
      );
      fixture.controller.createDrawingFrameForLayer(
        layerId: _layerId,
        frameId: const FrameId('new'),
      );

      // The [0,3) block of 'a' divides at 1; the frames themselves do not
      // move, only the division between them.
      final timeline = fixture.layer.timeline;
      expect(timeline[0]!.length, 1);
      expect(timeline[0]!.frameId, const FrameId('a'));
      expect(timeline[1]!.length, 2);
      expect(timeline[1]!.frameId, const FrameId('new'));
    });

    test('refuses a block START: nothing there to divide', () {
      final fixture = _fixture();
      fixture.controller.selectFrameIndex(0);

      expect(
        fixture.controller.canCreateDrawingAt(
          layer: fixture.layer,
          frameIndex: 0,
        ),
        isFalse,
      );
      expect(
        () => fixture.controller.createDrawingFrameForLayer(
          layerId: _layerId,
          frameId: const FrameId('new'),
        ),
        throwsStateError,
      );
    });
  });

  group('cutExposureForLayer (the X action)', () {
    test('ends the covering hold before the current frame', () {
      final fixture = _fixture();
      fixture.controller.selectFrameIndex(1);

      fixture.controller.cutExposureForLayer(layerId: _layerId);

      final layer = fixture.layer;
      expect(layer.timeline[0]!.length, 1);
      expect(
        fixture.controller.resolveFrameForLayer(layer: layer, frameIndex: 1),
        isNull,
      );
    });

    test('is rejected on block starts and empty cells', () {
      final fixture = _fixture();

      expect(
        fixture.controller.canCutExposureAt(
          layer: fixture.layer,
          frameIndex: 0,
        ),
        isFalse,
      );
      expect(
        fixture.controller.canCutExposureAt(
          layer: fixture.layer,
          frameIndex: 4,
        ),
        isFalse,
      );
      expect(
        fixture.controller.canCutExposureAt(
          layer: fixture.layer,
          frameIndex: 2,
        ),
        isTrue,
      );
    });
  });

  group('deleteCellForLayer', () {
    test('removes the block and garbage-collects its unreferenced frame', () {
      final fixture = _fixture();
      fixture.controller.selectFrameIndex(0);

      fixture.controller.deleteCellForLayer(layerId: _layerId);

      final layer = fixture.layer;
      expect(layer.timeline.containsKey(0), isFalse);
      expect(
        layer.frames.map((frame) => frame.id),
        isNot(contains(const FrameId('a'))),
      );
    });

    test('keeps a frame that is still linked elsewhere', () {
      final fixture = _fixture(
        timeline: {
          0: TimelineExposure.drawing(const FrameId('a'), length: 2),
          4: TimelineExposure.drawing(const FrameId('a'), length: 1),
        },
        frames: [Frame(id: const FrameId('a'), duration: 1, strokes: const [])],
      );
      fixture.controller.selectFrameIndex(0);

      fixture.controller.deleteCellForLayer(layerId: _layerId);

      final layer = fixture.layer;
      expect(layer.timeline.containsKey(0), isFalse);
      expect(
        layer.frames.map((frame) => frame.id),
        contains(const FrameId('a')),
      );
    });

    test('anywhere inside the covering block is deletable (UI-R17 #1); '
        'empty cells are not', () {
      final fixture = _fixture();

      expect(
        fixture.controller.canDeleteCellAt(layer: fixture.layer, frameIndex: 1),
        isTrue,
        reason: 'held cell — deletes the covering block',
      );
      expect(
        fixture.controller.canDeleteCellAt(layer: fixture.layer, frameIndex: 0),
        isTrue,
      );
      expect(
        fixture.controller.canDeleteCellAt(
          layer: fixture.layer,
          frameIndex: 999,
        ),
        isFalse,
        reason: 'empty cell',
      );
    });
  });

  /// 🚨T3 — these three used to be the three PLACEMENT RULES, and the paste
  /// no longer has any. ⛔Do not restore them: each one let the DESTINATION
  /// decide the pasted length, and 「코마까지 포함해서 블록 자체를 복붙」
  /// means the clip decides. What is left is one sentence — insert at the
  /// index, everything after moves aside — so all three now assert the same
  /// thing from three starting positions.
  ///
  /// Fixture: `a` holds 0..2, `b` holds 6..7.
  group('pasteLinkedFrameForLayer', () {
    test('on a block START it inserts BEFORE the block — ⛔no relink, and '
        'the block it landed on survives', () {
      final fixture = _fixture();
      fixture.controller.selectFrameIndex(0);

      fixture.controller.pasteLinkedFrameForLayer(
        layerId: _layerId,
        frameId: const FrameId('b'),
      );

      final layer = fixture.layer;
      expect(
        layer.timeline[0],
        TimelineExposure.drawing(const FrameId('b'), length: 1),
      );
      expect(
        layer.timeline[1],
        TimelineExposure.drawing(const FrameId('a'), length: 3),
        reason: 'a moved over by the clip length; the old rule ate it',
      );
      expect(
        layer.frames.map((frame) => frame.id),
        contains(const FrameId('a')),
        reason: 'nothing was orphaned, so nothing was collected',
      );
    });

    test('INSIDE a hold it splits — but the tail keeps its own cel instead '
        'of being handed to the clip', () {
      final fixture = _fixture();
      fixture.controller.selectFrameIndex(1);

      fixture.controller.pasteLinkedFrameForLayer(
        layerId: _layerId,
        frameId: const FrameId('b'),
      );

      final layer = fixture.layer;
      expect(layer.timeline[0]!.length, 1);
      expect(
        layer.timeline[1],
        TimelineExposure.drawing(const FrameId('b'), length: 1),
      );
      expect(
        layer.timeline[2],
        TimelineExposure.drawing(const FrameId('a'), length: 2),
        reason: 'the rest of a is still a',
      );
    });

    test('on an EMPTY cell it takes the clip\'s length, not the distance to '
        'the next block', () {
      final fixture = _fixture();
      fixture.controller.selectFrameIndex(3);

      fixture.controller.pasteLinkedFrameForLayer(
        layerId: _layerId,
        frameId: const FrameId('a'),
      );

      expect(
        fixture.layer.timeline[3],
        TimelineExposure.drawing(const FrameId('a'), length: 1),
        reason: 'the old rule stretched it to 3, reaching b at 6',
      );
      expect(
        fixture.layer.timeline[7],
        TimelineExposure.drawing(const FrameId('b'), length: 2),
        reason: 'b moved aside even though there was room',
      );
    });

    test('requires the source frame to exist in the layer', () {
      final fixture = _fixture();

      expect(
        fixture.controller.canPasteLinkedFrameAt(
          layer: fixture.layer,
          frameIndex: 3,
          copiedFrameId: const FrameId('missing'),
        ),
        isFalse,
      );
    });
  });

  group('rename and link', () {
    test('renames a frame and reports name conflicts instead of renaming', () {
      final fixture = _fixture();

      fixture.controller.renameFrameForLayer(
        layerId: _layerId,
        frameId: const FrameId('a'),
        name: 'A1',
      );
      expect(
        fixture.layer.frames
            .singleWhere((frame) => frame.id == const FrameId('a'))
            .name,
        'A1',
      );

      final conflict = fixture.controller.conflictingFrameIdForRename(
        layer: fixture.layer,
        frameId: const FrameId('b'),
        name: 'A1',
      );
      expect(conflict, const FrameId('a'));
    });

    test('linkFrameForLayer rewires uses and collects the orphaned source', () {
      final fixture = _fixture();

      fixture.controller.linkFrameForLayer(
        layerId: _layerId,
        sourceFrameId: const FrameId('a'),
        targetFrameId: const FrameId('b'),
      );

      final layer = fixture.layer;
      expect(layer.timeline[0]!.frameId, const FrameId('b'));
      expect(layer.timeline[0]!.length, 3);
      expect(
        layer.frames.map((frame) => frame.id),
        isNot(contains(const FrameId('a'))),
      );
      expect(
        fixture.controller.linkedUseCountForLayerFrame(
          layer: layer,
          frameId: const FrameId('b'),
        ),
        2,
      );
    });
  });

  group('undo integration', () {
    test('every mutating op is a single undoable command', () {
      final history = HistoryManager();
      final fixture = _fixture(historyManager: history);
      final original = fixture.layer;

      fixture.controller.selectFrameIndex(1);
      fixture.controller.cutExposureForLayer(layerId: _layerId);
      fixture.controller.selectFrameIndex(4);
      fixture.controller.createDrawingFrameForLayer(
        layerId: _layerId,
        frameId: const FrameId('new'),
      );
      expect(history.undoCount, 2);

      history.undo();
      history.undo();
      expect(fixture.layer, original);
    });
  });
}

const _layerId = LayerId('layer');
const _cutId = CutId('cut');

/// Default fixture: A[0,3) .. X gap .. B[6,8).
class _Fixture {
  _Fixture({
    Map<int, TimelineExposure>? timeline,
    List<Frame>? frames,
    HistoryManager? historyManager,
  }) {
    final layer = Layer(
      id: _layerId,
      name: 'Layer',
      frames:
          frames ??
          [
            Frame(id: const FrameId('a'), duration: 1, strokes: const []),
            Frame(id: const FrameId('b'), duration: 1, strokes: const []),
          ],
      timeline:
          timeline ??
          {
            0: TimelineExposure.drawing(const FrameId('a'), length: 3),
            6: TimelineExposure.drawing(const FrameId('b'), length: 2),
          },
    );
    repository = ProjectRepository(
      initialProject: Project(
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
                canvasSize: const CanvasSize(width: 100, height: 100),
                layers: [layer],
              ),
            ],
          ),
        ],
      ),
    );
    controller = TimelineController(
      repository: repository,
      cutId: _cutId,
      historyManager: historyManager,
    );
  }

  late final ProjectRepository repository;
  late final TimelineController controller;

  Layer get layer =>
      repository.requireProject().tracks.single.cuts.single.layers.single;
}

_Fixture _fixture({
  Map<int, TimelineExposure>? timeline,
  List<Frame>? frames,
  HistoryManager? historyManager,
}) {
  return _Fixture(
    timeline: timeline,
    frames: frames,
    historyManager: historyManager,
  );
}
