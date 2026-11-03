import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_in_and_out.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/ui/brush/brush_stroke_preview_cache.dart';

/// The brush list's swatch draws the brush the canvas will (F-434 「실제
/// 브러시랑 다른모양?」) — its 入り抜き too (brush-in-and-out), by the
/// canvas's own measure along the line.
void main() {
  const width = 160;
  const height = 40;

  int inked(Uint8List alpha, {required int from, required int to}) {
    var count = 0;
    for (var y = 0; y < height; y++) {
      for (var x = from; x < to; x++) {
        if (alpha[y * width + x] > 0) {
          count++;
        }
      }
    }
    return count;
  }

  test('its ends are thinner, and its middle is the brush as it is', () {
    final plain = BrushSettings(size: 20);
    final tapered = plain.copyWith(
      inAndOut: const BrushInAndOut(inLength: 40, outLength: 40),
    );
    final full = rasterizeBrushStrokeSample(plain, width, height);
    final thinned = rasterizeBrushStrokeSample(tapered, width, height);

    expect(
      inked(thinned, from: 0, to: 30),
      lessThan(inked(full, from: 0, to: 30)),
      reason: 'it comes in',
    );
    expect(
      inked(thinned, from: 130, to: width),
      lessThan(inked(full, from: 130, to: width)),
      reason: 'it goes out',
    );
    expect(
      inked(thinned, from: 70, to: 90),
      inked(full, from: 70, to: 90),
      reason: 'all the way in, and not yet going out',
    );
  });
}
