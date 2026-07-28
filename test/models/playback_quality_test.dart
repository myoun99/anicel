import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/playback_quality.dart';

void main() {
  test('quality scales', () {
    expect(PlaybackQuality.full.scale, 1.0);
    expect(PlaybackQuality.half.scale, 0.5);
    expect(PlaybackQuality.quarter.scale, 0.25);
  });

  test('scaledCanvasSize rounds and scales per quality', () {
    const size = CanvasSize(width: 2340, height: 1654);

    expect(
      scaledCanvasSize(size, PlaybackQuality.full),
      const CanvasSize(width: 2340, height: 1654),
    );
    expect(
      scaledCanvasSize(size, PlaybackQuality.half),
      const CanvasSize(width: 1170, height: 827),
    );
    expect(
      scaledCanvasSize(size, PlaybackQuality.quarter),
      const CanvasSize(width: 585, height: 414),
    );
  });

  test('scaledCanvasSize never collapses below 1x1', () {
    expect(
      scaledCanvasSize(
        const CanvasSize(width: 1, height: 2),
        PlaybackQuality.quarter,
      ),
      const CanvasSize(width: 1, height: 1),
    );
  });
}
