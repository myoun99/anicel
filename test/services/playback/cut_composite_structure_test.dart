import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/playback/cut_composite_structure.dart';
import 'package:anicel/src/services/playback/cut_frame_composite_signature.dart';

/// I-22: the rulers ask readiness per span of one picture. The spans must
/// be EXACTLY what asking every frame would give — across the chunk seams
/// they are discovered in, from any window start, and past the drawings.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);

  TimelineExposure drawing(String id, int length) =>
      TimelineExposure.drawing(FrameId(id), length: length);

  /// Every way a picture changes, laid across the 64-frame chunk seams: a
  /// held drawing crossing a seam, a hole, a pose tween over a hold, and a
  /// HIDDEN row whose block reaches furthest — so the authored extent ends
  /// on frames that already show nothing.
  Cut cut() => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    duration: 200,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: const LayerId('held'),
        name: 'A',
        frames: [frame('a'), frame('b'), frame('c')],
        timeline: {
          0: drawing('a', 70),
          70: drawing('b', 60),
          140: drawing('c', 100),
        },
      ),
      Layer(
        id: const LayerId('tween'),
        name: 'B',
        frames: [frame('t')],
        timeline: {100: drawing('t', 50)},
        transformTrack: TransformTrack(
          keyframes: {
            110: TransformPose(center: CanvasPoint(x: 0, y: 0)),
            120: TransformPose(center: CanvasPoint(x: 10, y: 0)),
          },
        ),
      ),
      Layer(
        id: const LayerId('hidden'),
        name: 'C',
        frames: [frame('h')],
        timeline: {0: drawing('h', 260)},
        isVisible: false,
      ),
    ],
  );

  CutFrameCompositeSignature structureAt(Cut of, int frameIndex) =>
      computeCutFrameCompositeSignature(
        cut: of,
        frameIndex: frameIndex,
        quality: PlaybackQuality.full,
        revisionOf: (_, _) => 0,
      );

  /// The answer asking every frame gives.
  List<(int, int)> everyFrame(Cut of, int start, int end) {
    final spans = <(int, int)>[];
    CutFrameCompositeSignature? current;
    for (var frameIndex = start; frameIndex < end; frameIndex += 1) {
      final structure = structureAt(of, frameIndex);
      if (current != null && structure == current) {
        spans.last = (spans.last.$1, frameIndex + 1);
        continue;
      }
      spans.add((frameIndex, frameIndex + 1));
      current = structure;
    }
    return spans;
  }

  List<(int, int)> bounds(Cut of, int start, int end) => [
    for (final span in compositeStructureSpansIn(of, start: start, end: end))
      (span.start, span.endExclusive),
  ];

  test('every window gives exactly the spans asking every frame would', () {
    final held = cut();
    for (final (start, end) in [
      (0, 400),
      (5, 70),
      (63, 65),
      (64, 128),
      (100, 125),
      (239, 262),
      (250, 300),
      (500, 520),
      (0, 1),
    ]) {
      expect(
        bounds(held, start, end),
        everyFrame(held, start, end),
        reason: 'window [$start, $end)',
      );
    }
  });

  test('each span is named by the structure of every frame it holds', () {
    final held = cut();
    for (final span in compositeStructureSpansIn(held, start: 0, end: 300)) {
      expect(span.signature, structureAt(held, span.start));
      expect(span.signature, structureAt(held, span.endExclusive - 1));
    }
  });

  test('the frames past the drawings are ONE span, joined to the stretch '
      'before them that already shows nothing', () {
    final held = cut();

    final tail = compositeStructureSpansIn(held, start: 0, end: 1000000).last;

    expect((tail.start, tail.endExclusive), (240, 1000000));
    expect(tail.signature.nodes, isEmpty);
  });

  test('a ten-minute window resolves the drawings, never the tail', () {
    final held = cut();
    final before = debugCompositeStructureFramesResolved;

    compositeStructureSpansIn(held, start: 0, end: 14400);

    expect(
      debugCompositeStructureFramesResolved - before,
      260,
      reason: 'the authored extent is 260 frames; the other 14,140 are '
          'one span nobody resolves',
    );
  });

  test('a window costs about itself, and a second ask costs nothing', () {
    final long = Cut(
      id: const CutId('long'),
      name: 'Long',
      duration: 10000,
      canvasSize: canvasSize,
      layers: [
        Layer(
          id: const LayerId('held'),
          name: 'A',
          frames: [frame('a')],
          timeline: {0: drawing('a', 10000)},
        ),
      ],
    );
    final before = debugCompositeStructureFramesResolved;

    compositeStructureSpansIn(long, start: 5000, end: 5100);
    final first = debugCompositeStructureFramesResolved - before;
    compositeStructureSpansIn(long, start: 5000, end: 5100);

    expect(first, lessThanOrEqualTo(3 * 64));
    expect(debugCompositeStructureFramesResolved - before, first);
  });

  test('an edited cut is a new instance and is read again', () {
    final held = cut();
    compositeStructureSpansIn(held, start: 0, end: 300);
    final edited = held.copyWith(
      layers: [
        for (final layer in held.layers)
          if (layer.id == const LayerId('held'))
            layer.copyWith(
              timeline: {0: drawing('a', 30), 30: drawing('b', 100)},
            )
          else
            layer,
      ],
    );

    expect(bounds(edited, 0, 300), everyFrame(edited, 0, 300));
    expect(bounds(edited, 0, 300), isNot(bounds(held, 0, 300)));
  });
}
