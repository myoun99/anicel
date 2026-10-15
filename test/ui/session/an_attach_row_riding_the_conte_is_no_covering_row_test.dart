import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
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
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨AN ATTACH ROW TAKES ITS BASE'S KIND, AND IS NOT ITS BASE (I-73).
///
/// A row added on a cut's conte is a storyboard row riding it. The conte
/// tiles its cut — no empty cell in its world, its last edge the cut's own
/// length — and those rules were asked of the row's KIND, so the attach row
/// answered them too: 🧪measured 2026-10-08, a comma set on a block of a
/// free attach row riding the conte resized the CUT to that row's end (12
/// frames to 10), and a frame could not be added at its blocks' heads. The
/// same row riding a cel layer did neither. The question is the LAYER's now
/// (`layerCoversWithoutGaps`).
void main() {
  /// A free attach row holding two four-frame blocks, at 0 and at 4.
  Layer rider(String id, LayerKind kind, String base) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    attachedToLayerId: LayerId(base),
    attachedPlacement: AttachedPlacement.above,
    attachedMode: AttachedMode.free,
    frames: [
      Frame(id: FrameId('$id-1'), duration: 4, strokes: const []),
      Frame(id: FrameId('$id-2'), duration: 4, strokes: const []),
    ],
    timeline: {
      0: TimelineExposure.drawing(FrameId('$id-1'), length: 4),
      4: TimelineExposure.drawing(FrameId('$id-2'), length: 4),
    },
  );

  Layer covering(String id, LayerKind kind) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    frames: [Frame(id: FrameId('$id-1'), duration: 12, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-1'), length: 12)},
  );

  /// One twelve-frame cut: a cel layer and the conte, each with a free
  /// attach row riding it.
  EditorSessionManager sessionOf() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('riders'),
        name: 'Riders',
        createdAt: DateTime.utc(2026, 10, 8),
        tracks: [
          Track(
            id: const TrackId('t1'),
            name: 'V1',
            cuts: [
              Cut(
                id: const CutId('a'),
                name: 'a',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  covering('cel', LayerKind.animation),
                  rider('on-cel', LayerKind.animation, 'cel'),
                  covering('conte', LayerKind.storyboard),
                  rider('on-conte', LayerKind.storyboard, 'conte'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  Cut cutOf(EditorSessionManager session) =>
      session.repository.requireProject().tracks.single.cuts.single;

  List<String> blocksOf(EditorSessionManager session, String id) => [
    for (final entry
        in cutOf(session).layers
            .firstWhere((layer) => layer.id == LayerId(id))
            .timeline
            .entries)
      if (!entry.value.ghost) '${entry.key}+${entry.value.length}',
  ];

  void standOn(EditorSessionManager session, String id, int frame) {
    session.selectLayer(LayerId(id));
    session.selectFrameIndex(frame);
    expect(session.activeLayerId, LayerId(id), reason: 'fixture: standing');
  }

  test('the premise: the two attach rows differ in kind alone', () {
    final layers = cutOf(sessionOf()).layers;
    final onConte = layers.firstWhere(
      (layer) => layer.id == const LayerId('on-conte'),
    );
    expect(onConte.kind, LayerKind.storyboard);
    expect(isAttachedLayer(onConte), isTrue);
    expect(layerCoversWithoutGaps(onConte), isFalse);
    expect(
      layerCoversWithoutGaps(
        layers.firstWhere((layer) => layer.id == const LayerId('conte')),
      ),
      isTrue,
      reason: 'LIVENESS: the conte itself is the covering row',
    );
  });

  test('🚨a comma set on a block of it leaves the cut\'s length alone — the '
      'conte\'s own still sizes its cut', () {
    for (final id in const ['on-cel', 'on-conte']) {
      final session = sessionOf();
      standOn(session, id, 4);

      session.edgeDrag.setCommaForTimelineCursor(6);

      expect(blocksOf(session, id), ['0+4', '4+6'], reason: '$id: retimed');
      expect(cutOf(session).duration, 12, reason: '$id: the cut is the cut');
    }

    final session = sessionOf();
    standOn(session, 'conte', 0);
    session.edgeDrag.setCommaForTimelineCursor(6);
    expect(
      cutOf(session).duration,
      6,
      reason: 'LIVENESS: the conte\'s panel is the cut\'s length',
    );
  });

  test('🚨an edge dragged on a block of it leaves the cut\'s length alone '
      '— alone, and inside a selection', () {
    for (final selected in const [false, true]) {
      final session = sessionOf();
      standOn(session, 'on-conte', 4);
      if (selected) {
        session.frameRangeSelection.value = const TimelineFrameRangeSelection(
          layerId: LayerId('on-conte'),
          startIndex: 4,
          endIndexExclusive: 8,
        );
      }

      expect(
        session.edgeDrag.beginExposureEdgeDrag(
          layerId: const LayerId('on-conte'),
          blockStartIndex: 4,
          edge: TimelineBlockEdge.end,
        ),
        isTrue,
        reason: 'fixture: a free row\'s edge drags',
      );
      session.edgeDrag.updateExposureEdgeDrag(2);
      session.edgeDrag.endExposureEdgeDrag();

      final why = selected ? 'inside a selection' : 'alone';
      expect(blocksOf(session, 'on-conte'), ['0+4', '4+6'], reason: why);
      expect(cutOf(session).duration, 12, reason: why);
    }
  });

  test('every frame gate answers for it what it answers for the same row '
      'riding a cel layer', () {
    for (final frame in const [0, 2, 4, 5, 9]) {
      final answers = <String, List<bool>>{};
      for (final id in const ['on-cel', 'on-conte']) {
        final session = sessionOf();
        standOn(session, id, frame);
        answers[id] = [
          session.frameVerbs.canCreateDrawingAtCurrentFrame,
          session.exposureVerbs.canBlankExposureAtCurrentFrame,
          session.storyboardCursor.canSetCommaForTimelineCursor,
        ];
      }
      expect(
        answers['on-conte'],
        answers['on-cel'],
        reason: 'frame $frame: [add a frame, X, comma]',
      );
    }
    // LIVENESS: the gates do tell a covering row from a drawing row — a
    // frame is added at a block's head on the one and not on the other.
    final onRider = sessionOf();
    standOn(onRider, 'on-conte', 4);
    expect(onRider.frameVerbs.canCreateDrawingAtCurrentFrame, isTrue);
    final onConte = sessionOf();
    standOn(onConte, 'conte', 0);
    expect(onConte.frameVerbs.canCreateDrawingAtCurrentFrame, isFalse);
  });

  /// One answer per rider: what [act] leaves on the row riding the cel, and
  /// on the row riding the conte.
  Map<String, List<String>> onBoth(
    void Function(EditorSessionManager session, String id) act,
  ) => {
    for (final id in const ['on-cel', 'on-conte'])
      id: () {
        final session = sessionOf();
        act(session, id);
        return blocksOf(session, id);
      }(),
  };

  test('🚨a band authors into its gaps, as it does on the row riding a cel',
      () {
    final filled = onBoth((session, id) {
      standOn(session, id, 9);
      session.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: LayerId(id),
        startIndex: 6,
        endIndexExclusive: 12,
      );
      expect(session.cellInstances.createInstancesForSelection(), isTrue);
    });

    expect(filled['on-conte'], filled['on-cel']);
    expect(
      filled['on-conte'],
      ['0+4', '4+4', '8+4'],
      reason: 'LIVENESS: the gap inside the band took a block',
    );
  });

  test('🚨its blocks move as the same row\'s riding a cel do — past the '
      'cut\'s end, and back to its first frame', () {
    void move(EditorSessionManager session, String id, int by) {
      final blocks = cutOf(session).layers
          .firstWhere((layer) => layer.id == LayerId(id))
          .timeline;
      session.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: LayerId(id),
        startIndex: blocks.keys.first,
        endIndexExclusive: blocks.keys.last + blocks.values.last.length!,
      );
      expect(
        session.rangeMove.beginFrameRangeMoveDrag(LayerId(id)),
        isTrue,
        reason: 'fixture: $id by $by',
      );
      session.rangeMove.updateFrameRangeMoveDrag(frameDelta: by);
      session.rangeMove.endFrameRangeMoveDrag();
    }

    final out = onBoth((session, id) {
      standOn(session, id, 0);
      move(session, id, 6);
    });
    expect(out['on-conte'], out['on-cel']);
    expect(
      out['on-conte'],
      ['6+4', '10+4'],
      reason: 'LIVENESS: the cut ends at 12, and the row is not held to it',
    );

    final back = onBoth((session, id) {
      standOn(session, id, 0);
      move(session, id, 6);
      move(session, id, -6);
    });
    expect(back['on-conte'], back['on-cel']);
    expect(
      back['on-conte'],
      ['0+4', '4+4'],
      reason: 'LIVENESS: its first block is no floor for the row',
    );
  });

  test('an IMAGE row\'s kind still answers for every row of it — a row '
      'riding it among them', () {
    Layer image(String id, {String? ridesOn}) => Layer(
      id: LayerId(id),
      name: id,
      kind: LayerKind.image,
      attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
      attachedPlacement: AttachedPlacement.above,
      frames: const [],
      timeline: const {},
    );

    expect(layerCoversWithoutGaps(image('bg')), isTrue);
    expect(layerCoversWithoutGaps(image('bg+1', ridesOn: 'bg')), isTrue);
  });
}
