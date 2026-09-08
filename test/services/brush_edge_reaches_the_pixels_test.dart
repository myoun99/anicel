// THE EDGE SETTING REACHES THE PIXELS, AND IT LANDS BEFORE THE TEXTURES.
//
// The enum's own arithmetic is pinned in `brush_anti_alias_test.dart`. What
// is pinned HERE is that a dab carrying it actually rasterizes differently
// — a setting that only travels through the model is a setting that does
// nothing.
//
// ⚠️These run the REFERENCE path (`brushPixelCoveragesForDab`). The tile
// kernel and the C kernel are the other two transcriptions of the same
// cascade; they are held to this one by the parity suites, which is why the
// remap had to go in the same place in all three.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_input_sample.dart';
import 'package:anicel/src/models/brush_pixel_coverage.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_dab_coverage.dart';

void main() {
  BrushDab dab({
    required BrushAntiAlias antiAlias,
    double hardness = 0.0,
    BrushTipMask? textureMask,
    double textureDensity = 1.0,
  }) => BrushDab(
    center: CanvasPoint(x: 10, y: 10),
    color: 0xFF000000,
    size: 9,
    opacity: 1,
    flow: 1,
    hardness: hardness,
    pressure: 1,
    sequence: 0,
    tipShape: BrushTipShape.round,
    antiAlias: antiAlias,
    textureMask: textureMask,
    textureDensity: textureDensity,
  );

  /// The coverages strictly between 0 and 1 — the soft edge itself.
  Iterable<double> softPixels(BrushAntiAlias step, {double hardness = 0.0}) =>
      brushPixelCoveragesForDab(dab(antiAlias: step, hardness: hardness))
          .map((BrushPixelCoverage c) => c.coverage)
          .where((c) => c > 0.0 && c < 1.0);

  test('🚨THE SETTING REACHES THE DAB — the hop the pixel tests cannot see', () {
    // ⛔Every other case here builds a dab by hand, so all of them survived
    // deleting `antiAlias: settings.antiAlias` from `fromInputSample`
    // (measured 2026-09-08). The brush -> dab hop needs its own pin, or the
    // panel can say 없음 while the canvas keeps drawing 3단계.
    for (final step in BrushAntiAlias.values) {
      final placed = BrushDab.fromInputSample(
        sample: BrushInputSample(x: 1, y: 1),
        settings: BrushSettings(size: 4, antiAlias: step),
        sequence: 0,
      );
      expect(placed.antiAlias, step, reason: 'the brush said ${step.name}');
    }
  });

  test('없음 leaves NO partly-covered pixel — that is what hard means', () {
    expect(softPixels(BrushAntiAlias.none), isEmpty);
  });

  test('3단계 has a soft ring, and each step down thins it', () {
    final counts = [
      softPixels(BrushAntiAlias.high).length,
      softPixels(BrushAntiAlias.medium).length,
      softPixels(BrushAntiAlias.low).length,
      softPixels(BrushAntiAlias.none).length,
    ];
    expect(counts.first, greaterThan(0), reason: 'the soft ring exists');
    for (var i = 1; i < counts.length; i += 1) {
      expect(
        counts[i],
        lessThanOrEqualTo(counts[i - 1]),
        reason: 'step $i must not be softer than the one before it',
      );
    }
    expect(counts.last, 0);
  });

  test('🚨the stroke does NOT get thinner — the painted footprint holds', () {
    // 유저: 「굵기 안바꾸고 가장자리만 조이는거였어」. Measured as the count of
    // pixels the eye reads as inside: coverage at or above a half.
    int solidish(BrushAntiAlias step) =>
        brushPixelCoveragesForDab(dab(antiAlias: step))
            .where((c) => c.coverage >= 0.5)
            .length;
    final base = solidish(BrushAntiAlias.high);
    for (final step in BrushAntiAlias.values) {
      expect(
        solidish(step),
        base,
        reason: '$step moved the half-coverage footprint',
      );
    }
  });

  test('⛔the edge is cut BEFORE the paper texture, so the texture inside '
      'stays soft', () {
    // A texture that darkens every pixel to half. With the cut ahead of it,
    // the interior comes out textured (0 < c < 1) even at 없음 — the
    // SILHOUETTE hardened, not the brush. Behind it, every pixel would be
    // 0 or 1 and a textured brush would binarize whole.
    final texture = BrushTipMask(
      id: 'flat-half',
      size: 2,
      alpha: Uint8List.fromList(const [128, 128, 128, 128]),
    );
    final textured = brushPixelCoveragesForDab(
      dab(antiAlias: BrushAntiAlias.none, textureMask: texture),
    ).map((c) => c.coverage).toList();

    expect(textured, isNotEmpty);
    expect(
      textured.where((c) => c > 0.0 && c < 1.0),
      isNotEmpty,
      reason: 'the texture survived the hard edge',
    );
  });
}
