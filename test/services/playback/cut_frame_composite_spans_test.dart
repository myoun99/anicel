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
import 'package:anicel/src/services/playback/cut_frame_composite_spans.dart';

void main() {
  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);

  Layer drawingLayer({TransformTrack? transformTrack}) {
    return Layer(
      id: const LayerId('layer-1'),
      name: 'A',
      frames: [frame('frame-1'), frame('frame-2')],
      timeline: {
        0: TimelineExposure.drawing(const FrameId('frame-1'), length: 6),
        6: TimelineExposure.drawing(const FrameId('frame-2'), length: 4),
      },
      transformTrack: transformTrack,
    );
  }

  Cut cut({List<Layer>? layers}) {
    return Cut(
      id: const CutId('cut'),
      name: 'Cut',
      layers: layers ?? [drawingLayer()],
      duration: 24,
      canvasSize: const CanvasSize(width: 100, height: 50),
    );
  }

  List<CutFrameCompositeSpan> spans({
    Cut? forCut,
    int frameCount = 14,
    PlaybackQuality quality = PlaybackQuality.half,
    int Function(LayerId, FrameId)? revisionOf,
  }) {
    return computeCutFrameCompositeSpans(
      cut: forCut ?? cut(),
      frameCount: frameCount,
      quality: quality,
      revisionOf: revisionOf ?? (_, _) => 7,
    );
  }

  /// The one structural law: spans tile [0, frameCount) exactly — no
  /// gaps, no overlaps, no reordering.
  void expectTiles(List<CutFrameCompositeSpan> table, int frameCount) {
    expect(table.first.start, 0);
    expect(table.last.endExclusive, frameCount);
    for (var i = 1; i < table.length; i++) {
      expect(table[i].start, table[i - 1].endExclusive);
    }
  }

  test('held exposures collapse into spans, and the blank tail is one '
      'span with an empty signature', () {
    final table = spans();

    expectTiles(table, 14);
    expect(
      table.map((span) => (span.start, span.endExclusive)),
      [(0, 6), (6, 10), (10, 14)],
    );
    // Past the authored content there is nothing to compose — one run,
    // empty identity. Readiness readers treat this as "nothing to
    // prepare = ready by definition"; the span function itself takes no
    // stance beyond reporting the empty signature.
    expect(table.last.signature.nodes, isEmpty);
    expect(table[0].signature.nodes, isNot(isEmpty));
  });

  test('an animated pose splits a held exposure into per-frame spans, and '
      'the run merges again where the pose freezes', () {
    final moved = cut(
      layers: [
        drawingLayer(
          transformTrack: TransformTrack(
            keyframes: {
              0: TransformPose(center: CanvasPoint(x: 0, y: 0)),
              5: TransformPose(center: CanvasPoint(x: 10, y: 0)),
            },
          ),
        ),
      ],
    );

    final table = spans(forCut: moved, frameCount: 12);

    expectTiles(table, 12);
    // Frames 0..4 interpolate — every frame is its own picture.
    for (var i = 0; i < 5; i++) {
      expect(table[i].start, i);
      expect(table[i].length, 1, reason: 'frame $i interpolates');
    }
    // Frame 5 holds the frozen pose but is still frame-1; frame 6 swaps
    // to frame-2 under the same pose — the drawing, not the pose, is the
    // boundary there.
    expect(
      table.skip(5).map((span) => (span.start, span.endExclusive)),
      [(5, 6), (6, 10), (10, 12)],
    );
  });

  test('editing one cel changes exactly that span\'s identity — the '
      'boundaries and every other span survive', () {
    int before(LayerId _, FrameId frameId) =>
        frameId.value == 'frame-1' ? 3 : 7;
    int after(LayerId _, FrameId frameId) =>
        frameId.value == 'frame-1' ? 4 : 7;

    final beforeTable = spans(revisionOf: before);
    final afterTable = spans(revisionOf: after);

    expect(
      afterTable.map((span) => (span.start, span.endExclusive)),
      beforeTable.map((span) => (span.start, span.endExclusive)),
    );
    expect(afterTable[0].signature, isNot(beforeTable[0].signature));
    expect(afterTable[1].signature, beforeTable[1].signature);
    expect(afterTable[2].signature, beforeTable[2].signature);
  });

  test('quality rides every span signature without moving a boundary', () {
    final half = spans(quality: PlaybackQuality.half);
    final full = spans(quality: PlaybackQuality.full);

    expect(
      full.map((span) => (span.start, span.endExclusive)),
      half.map((span) => (span.start, span.endExclusive)),
    );
    for (var i = 0; i < half.length; i++) {
      expect(full[i].signature, isNot(half[i].signature));
    }
  });

  test('zero frames is an empty table', () {
    expect(spans(frameCount: 0), isEmpty);
  });

  test('contains answers per frame', () {
    final span = spans()[1]; // [6, 10)
    expect(span.contains(5), isFalse);
    expect(span.contains(6), isTrue);
    expect(span.contains(9), isTrue);
    expect(span.contains(10), isFalse);
  });
}
