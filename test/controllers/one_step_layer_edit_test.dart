import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/timeline_controller.dart';
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
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

/// Characterisation of the controller's THREE shared edit shapes, pinned
/// before they were folded into one body each (round 8, clone pairs
/// 5/6/7, 9, 10):
///
/// 1. the ONE-STEP layer edit — blank / delete / mark / retime each take a
///    per-layer value, turn every layer that changes into a command, and
///    commit the lot as ONE undo step (nothing when nothing changed);
/// 2. the COVERING-BLOCK edit at the edit frame — toggle-mark and the X
///    both gate, then replace the covering block's HEAD entry in place;
/// 3. the command DISPATCH — through the history when there is one, run
///    directly when there is none.
void main() {
  group('one edit step across layers', () {
    test('blank: every swept row blanks, ONE undo restores them all', () {
      final h = _Harness(a: {0: _drawing('a', 4)}, b: {0: _drawing('b', 4)});

      h.controller.blankSpansForLayers({
        _a: (start: 1, endExclusive: 2),
        _b: (start: 2, endExclusive: 3),
      });

      expect(h.timeline(_a), {0: _drawing('a', 1), 2: _drawing('a', 2)});
      expect(h.timeline(_b), {0: _drawing('b', 2), 3: _drawing('b', 1)});
      expect(h.history.undoCount, 1);
      h.history.undo();
      expect(h.timeline(_a), {0: _drawing('a', 4)});
      expect(h.timeline(_b), {0: _drawing('b', 4)});
    });

    test('delete: every row\'s blocks go in ONE undo step', () {
      final h = _Harness(
        a: {0: _drawing('a', 2), 2: _drawing('a2', 2)},
        b: {0: _drawing('b', 2)},
      );

      h.controller.deleteBlocksForLayers({
        _a: [0],
        _b: [0],
      });

      expect(h.timeline(_a), {2: _drawing('a2', 2)});
      expect(h.timeline(_b), isEmpty);
      expect(h.history.undoCount, 1);
      h.history.undo();
      expect(h.timeline(_a), {0: _drawing('a', 2), 2: _drawing('a2', 2)});
      expect(h.timeline(_b), {0: _drawing('b', 2)});
    });

    test('mark: every row\'s frames mark in ONE undo step', () {
      final h = _Harness(a: {0: _drawing('a', 4)}, b: {0: _drawing('b', 4)});

      h.controller.setMarksForFrames({
        _a: [1, 2],
        _b: [3],
      }, marked: true);

      expect(h.timeline(_a)[0]!.breakdownOffsets, [1, 2]);
      expect(h.timeline(_b)[0]!.breakdownOffsets, [3]);
      expect(h.history.undoCount, 1);
      h.history.undo();
      expect(h.timeline(_a)[0]!.breakdownOffsets, isEmpty);
      expect(h.timeline(_b)[0]!.breakdownOffsets, isEmpty);
    });

    test('retime: every row\'s blocks resize in ONE undo step', () {
      final h = _Harness(a: {0: _drawing('a', 3)}, b: {0: _drawing('b', 3)});

      h.controller.retimeBlocksForLayers({
        _a: {0: 1},
        _b: {0: 2},
      });

      expect(h.timeline(_a), {0: _drawing('a', 1)});
      expect(h.timeline(_b), {0: _drawing('b', 2)});
      expect(h.history.undoCount, 1);
      h.history.undo();
      expect(h.timeline(_a), {0: _drawing('a', 3)});
      expect(h.timeline(_b), {0: _drawing('b', 3)});
    });

    test('a row the edit leaves unchanged adds nothing; all unchanged adds '
        'no undo entry at all', () {
      final h = _Harness(a: {0: _drawing('a', 2)}, b: {0: _drawing('b', 2)});

      // Row b names a start with no block: only row a changes.
      h.controller.deleteBlocksForLayers({
        _a: [0],
        _b: [5],
      });
      expect(h.timeline(_a), isEmpty);
      expect(h.timeline(_b), {0: _drawing('b', 2)});
      expect(h.history.undoCount, 1);

      // Nothing changes anywhere: no phantom step, for every verb.
      h.controller.deleteBlocksForLayers({
        _b: [5],
      });
      h.controller.blankSpansForLayers({_b: (start: 5, endExclusive: 6)});
      h.controller.setMarksForFrames({
        _b: [1],
      }, marked: false);
      h.controller.retimeBlocksForLayers({
        _b: {0: 2},
      });
      expect(h.history.undoCount, 1);
    });

    test('with no history the edit still lands in the repository', () {
      final h = _Harness(
        a: {0: _drawing('a', 4)},
        b: {0: _drawing('b', 4)},
        withHistory: false,
      );

      h.controller.blankSpansForLayers({_a: (start: 0, endExclusive: 4)});
      h.controller.setMarksForFrames({
        _b: [1],
      }, marked: true);

      expect(h.timeline(_a), isEmpty);
      expect(h.timeline(_b)[0]!.breakdownOffsets, [1]);
    });
  });

  group('the covering block edit at the edit frame', () {
    test('the gate refuses: nothing lands, no undo entry', () {
      final h = _Harness(a: {0: _drawing('a', 3)}, b: {0: _drawing('b', 3)});

      h.controller.selectFrameIndex(0); // a block HEAD: both gates refuse.
      h.controller.toggleMarkForLayer(layerId: _a);
      h.controller.cutExposureForLayer(layerId: _b);

      expect(h.timeline(_a), {0: _drawing('a', 3)});
      expect(h.timeline(_b), {0: _drawing('b', 3)});
      expect(h.history.undoCount, 0);
    });

    test('the head entry is replaced in place, keyed by the block start', () {
      final h = _Harness(
        a: {0: _drawing('a', 3), 3: _drawing('a2', 1)},
        b: {0: _drawing('b', 3), 3: _drawing('b2', 1)},
      );

      h.controller.selectFrameIndex(2);
      h.controller.toggleMarkForLayer(layerId: _a);
      h.controller.cutExposureForLayer(layerId: _b);

      expect(h.timeline(_a), {
        0: _drawing('a', 3, dots: [2]),
        3: _drawing('a2', 1),
      });
      expect(h.timeline(_b), {0: _drawing('b', 2), 3: _drawing('b2', 1)});
      expect(h.history.undoCount, 2);
    });

    test('a track-owned row edits at the playhead SHIFTED by its offset', () {
      final h = _Harness(
        a: {0: _drawing('a', 3)},
        b: {0: _drawing('b', 3)},
        seTimeline: {10: _drawing('se', 4)},
        seOffset: 10,
      );

      h.controller.selectFrameIndex(2); // cut-local 2 = global 12.
      h.controller.toggleMarkForLayer(layerId: _se);
      expect(h.seLayer.timeline[10]!.breakdownOffsets, [2]);

      h.controller.selectFrameIndex(3); // global 13.
      h.controller.cutExposureForLayer(layerId: _se);
      expect(h.seLayer.timeline[10]!.length, 3);
    });
  });

  group('commands run through the history when there is one', () {
    test('rasterize: ONE undo restores the kind and every cel\'s text', () {
      final h = _Harness(
        a: {0: _drawing('a', 2)},
        b: {0: _drawing('b', 2)},
        aKind: LayerKind.text,
        aText: const TextCelContent(text: 'hi'),
      );

      h.controller.rasterizeTextLayer(layerId: _a);

      expect(h.layer(_a).kind, LayerKind.animation);
      expect(h.layer(_a).frames.single.textContent, isNull);
      expect(h.history.undoCount, 1);
      h.history.undo();
      expect(h.layer(_a).kind, LayerKind.text);
      expect(h.layer(_a).frames.single.textContent?.text, 'hi');
    });

    test('rasterize with no history still lands', () {
      final h = _Harness(
        a: {0: _drawing('a', 2)},
        b: {0: _drawing('b', 2)},
        aKind: LayerKind.text,
        aText: const TextCelContent(text: 'hi'),
        withHistory: false,
      );

      h.controller.rasterizeTextLayer(layerId: _a);

      expect(h.layer(_a).kind, LayerKind.animation);
      expect(h.layer(_a).frames.single.textContent, isNull);
    });

    test('the single-layer edit with no history still lands', () {
      final h = _Harness(
        a: {0: _drawing('a', 3)},
        b: {0: _drawing('b', 3)},
        withHistory: false,
      );

      h.controller.selectFrameIndex(1);
      h.controller.cutExposureForLayer(layerId: _a);

      expect(h.timeline(_a), {0: _drawing('a', 1)});
    });
  });
}

const _a = LayerId('a');
const _b = LayerId('b');
const _se = LayerId('se');
const _cutId = CutId('cut');

TimelineExposure _drawing(String frameId, int length, {List<int>? dots}) {
  return TimelineExposure.drawing(
    FrameId(frameId),
    length: length,
    breakdownOffsets: dots ?? const [],
  );
}

class _Harness {
  _Harness({
    required Map<int, TimelineExposure> a,
    required Map<int, TimelineExposure> b,
    Map<int, TimelineExposure> seTimeline = const {},
    int seOffset = 0,
    LayerKind aKind = LayerKind.animation,
    TextCelContent? aText,
    bool withHistory = true,
  }) {
    final cut = Cut(
      id: _cutId,
      name: 'Cut',
      duration: 24,
      canvasSize: const CanvasSize(width: 8, height: 8),
      layers: [
        _layer(_a, a, kind: aKind, text: aText),
        _layer(_b, b),
      ],
    );
    repository = ProjectRepository(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'P',
        createdAt: DateTime(2026),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'T',
            cuts: [cut],
            seLayers: [_layer(_se, seTimeline)],
          ),
        ],
      ),
    );
    _history = withHistory ? HistoryManager() : null;
    controller = TimelineController(
      repository: repository,
      cutId: _cutId,
      historyManager: _history,
      frameOffsetForLayer: (layerId) => layerId == _se ? seOffset : 0,
      trackSeLayers: () => repository.currentProject!.tracks.single.seLayers,
    );
  }

  late final ProjectRepository repository;
  late final TimelineController controller;
  late final HistoryManager? _history;

  HistoryManager get history => _history!;

  Layer get seLayer => repository.currentProject!.tracks.single.seLayers.single;

  Layer layer(LayerId id) => repository
      .currentProject!
      .tracks
      .single
      .cuts
      .single
      .layers
      .firstWhere((layer) => layer.id == id);

  Map<int, TimelineExposure> timeline(LayerId id) =>
      Map<int, TimelineExposure>.from(layer(id).timeline);

  static Layer _layer(
    LayerId id,
    Map<int, TimelineExposure> timeline, {
    LayerKind kind = LayerKind.animation,
    TextCelContent? text,
  }) {
    final seen = <String>{};
    return Layer(
      id: id,
      name: id.value,
      kind: kind,
      frames: [
        for (final entry in timeline.entries)
          if (entry.value.isDrawing && seen.add(entry.value.frameId!.value))
            Frame(
              id: entry.value.frameId!,
              duration: 1,
              strokes: const [],
              textContent: text,
            ),
      ],
      timeline: timeline,
    );
  }
}
