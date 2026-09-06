import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_warm_extent.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// B1 — one law for "how many frames does this cut's warm world span".
void main() {
  Cut cut({
    int duration = 4,
    Map<int, TimelineExposure> timeline = const {},
  }) {
    return Cut(
      id: const CutId('cut'),
      name: '1',
      duration: duration,
      canvasSize: const CanvasSize(width: 8, height: 8),
      layers: [
        Layer(
          id: const LayerId('layer'),
          name: 'A',
          frames: [
            Frame(id: const FrameId('frame-a'), duration: 1, strokes: const []),
          ],
          timeline: timeline,
        ),
      ],
    );
  }

  test('an undrawn-past cut spans its duration', () {
    expect(
      cutWarmFrameCount(
        cut(timeline: {
          0: const TimelineExposure.drawing(FrameId('frame-a'), length: 4),
        }),
      ),
      4,
    );
  });

  test('a runway drawing extends the span past the end line', () {
    expect(
      cutWarmFrameCount(
        cut(timeline: {
          5: const TimelineExposure.drawing(FrameId('frame-a'), length: 2),
        }),
      ),
      7,
      reason: 'the drawings reach frame 6, so the world is 7 frames',
    );
  });

  test('an empty zero-duration cut still spans one frame', () {
    expect(cutWarmFrameCount(cut(duration: 0)), 1);
  });

  group('cutAuthoredExtent', () {
    Cut cutWithLayers(List<Layer> layers, {int duration = 24}) => Cut(
      id: const CutId('cut'),
      name: '1',
      duration: duration,
      canvasSize: const CanvasSize(width: 8, height: 8),
      layers: layers,
    );

    Layer layer(String id, Map<int, TimelineExposure> timeline) => Layer(
      id: LayerId(id),
      name: id,
      frames: [
        Frame(id: const FrameId('frame-a'), duration: 1, strokes: const []),
      ],
      timeline: timeline,
    );

    test('is the max block end across layers, not Cut.duration', () {
      final cut = cutWithLayers([
        layer('a', {
          0: const TimelineExposure.drawing(FrameId('frame-a'), length: 7),
          7: const TimelineExposure.drawing(FrameId('frame-a'), length: 2),
        }),
        layer('b', {
          10: const TimelineExposure.drawing(FrameId('frame-a'), length: 3),
        }),
        layer('empty', const {}),
      ], duration: 24);

      expect(cutAuthoredExtent(cut), 13);
      expect(cutAuthoredExtent(cut), isNot(cut.duration));
    });

    test('a cut with no layers, or only undrawn ones, has extent zero', () {
      expect(cutAuthoredExtent(cutWithLayers(const [])), 0);
      expect(
        cutAuthoredExtent(cutWithLayers([layer('empty', const {})])),
        0,
      );
    });

    test('the warm count is the extent floored by the duration and by one', () {
      final runway = cutWithLayers([
        layer('a', {
          5: const TimelineExposure.drawing(FrameId('frame-a'), length: 2),
        }),
      ], duration: 4);

      expect(cutAuthoredExtent(runway), 7);
      expect(cutWarmFrameCount(runway), 7);
      expect(cutWarmFrameCount(cutWithLayers(const [], duration: 0)), 1);
    });
  });
}
