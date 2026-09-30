// THE EDGE SETTING REACHES THE PIXELS, AND IT LANDS BEFORE THE TEXTURES.
//
// The law's own arithmetic is pinned in `brush_edge_law_test.dart` and the
// round tip's geometry in `the_analytic_tip_is_one_law_test.dart`. What is
// pinned HERE is that a dab carrying the step actually rasterizes
// differently — a setting that only travels through the model is a setting
// that does nothing.
//
// ⚠️These run the REFERENCE path (`brushPixelCoveragesForDab`). The tile
// kernel and the C kernel are the other two transcriptions of the same
// cascade; they are held to this one by the parity suites, which is why the
// remap had to go in the same place in all three.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_dab.dart';
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

  // ⛔THE BRUSH -> DAB HOP USED TO BE PINNED HERE, on
  // `BrushDab.fromInputSample` — and that factory turned out to be the one
  // producer NOTHING in the app called, so the pin was green while the
  // canvas dropped the setting entirely. The hop is pinned at the LIVE
  // doors now: `every_brush_setting_reaches_the_dab_test`.
  //
  // ⚠️Every case below builds its dab by hand, which is why none of them
  // could ever catch it (measured 2026-09-08 by deleting `antiAlias:` and
  // watching this file stay green).

  test('없음 leaves NO partly-covered pixel — that is what hard means', () {
    expect(softPixels(BrushAntiAlias.none), isEmpty);
  });

  test('🚨a HARD nib gets a soft ring, and each step up widens it', () {
    // I-50 (「aa 값이 3인데도 너무 약함」): a hardness-100% nib has no ramp of
    // its own, so a ladder on its ramp drew the same staircase at every
    // step. The step now gives it the edge.
    final counts = [
      for (final step in BrushAntiAlias.values)
        softPixels(step, hardness: 1).length,
    ];
    expect(counts.first, 0, reason: '없음');
    for (var i = 1; i < counts.length; i += 1) {
      expect(
        counts[i],
        greaterThan(counts[i - 1]),
        reason: '${BrushAntiAlias.values[i]} must be softer than the step '
            'before it',
      );
    }
  });

  test('🚨the rim holds — no step paints a pixel the hard nib does not', () {
    // ↩️「굵기 안바꾸고」 was pinned here as the half-coverage footprint. Clip
    // Studio's own lines said the rim is what holds (board I-50): the ramp
    // grows inward, so the footprint is the same at every step.
    Set<(int, int)> footprint(BrushAntiAlias step) => {
      for (final c in brushPixelCoveragesForDab(
        dab(antiAlias: step, hardness: 1),
      ))
        if (c.coverage > 0.0) (c.x, c.y),
    };
    final hard = footprint(BrushAntiAlias.none);
    expect(hard, isNotEmpty, reason: 'premise');
    for (final step in BrushAntiAlias.values) {
      expect(footprint(step), hard, reason: '$step');
    }
  });

  test('a soft tip\'s own ramp is wider than any step, and stands at every '
      'step but 없음', () {
    List<double> coverages(BrushAntiAlias step) => [
      for (final c in brushPixelCoveragesForDab(dab(antiAlias: step)))
        c.coverage,
    ];
    final high = coverages(BrushAntiAlias.high);
    expect(high.where((c) => c > 0.0 && c < 1.0), isNotEmpty);
    expect(coverages(BrushAntiAlias.medium), high);
    expect(coverages(BrushAntiAlias.low), high);
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
