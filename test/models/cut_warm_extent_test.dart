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
}
