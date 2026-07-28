import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_tip_stamp_cache.dart';

/// R20-B tip-stamp cache (the CSP/PS brush architecture): every dab
/// resolves to a prerendered, quantized, PREROTATED raster mask consumed
/// through the existing unrotated-lattice fast path. Resolution is
/// idempotent and deterministic; the same key returns the same mask
/// object, so uploads and lattices amortize across a stroke.
void main() {
  BrushDab dab({
    double size = 12,
    double hardness = 1,
    double roundness = 1,
    double angle = 0,
    BrushTipShape shape = BrushTipShape.round,
    BrushTipMask? tipMask,
    double x = 16,
    double y = 16,
  }) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFF000000,
    size: size,
    opacity: 1,
    flow: 1,
    hardness: hardness,
    tipShape: shape,
    pressure: 1,
    sequence: 0,
    roundness: roundness,
    angleDegrees: angle,
    tipMask: tipMask,
  );

  test('resolution rewrites a dab to an unrotated cached-mask dab and is '
      'idempotent + deterministic (same mask OBJECT)', () {
    final cache = BrushTipStampCache();
    final resolved = cache.resolveDab(
      dab(size: 12.1, hardness: 0.5, roundness: 0.7, angle: 33.4),
    );

    expect(resolved.tipMask, isNotNull);
    expect(
      resolved.tipMask!.id,
      startsWith(BrushTipStampCache.resolvedIdPrefix),
    );
    expect(resolved.angleDegrees, 0.0, reason: 'rotation baked into mask');
    expect(resolved.roundness, 1.0, reason: 'roundness baked into mask');
    expect(resolved.size, closeTo(12.0, 0.3), reason: 'quantized size');

    final again = cache.resolveDab(
      dab(size: 12.1, hardness: 0.5, roundness: 0.7, angle: 33.4),
    );
    expect(
      identical(again.tipMask, resolved.tipMask),
      isTrue,
      reason: 'cache hit returns the identical mask object',
    );

    final rere = cache.resolveDab(resolved);
    expect(
      identical(rere, resolved),
      isTrue,
      reason: 'resolving a resolved dab is a no-op',
    );
  });

  test('stamp dabs (lift/fill pixels) bypass the cache untouched', () {
    final cache = BrushTipStampCache();
    final stampDab = dab().copyWith(
      stamp: BrushStampImage(
        id: 's',
        width: 1,
        height: 1,
        rgba: Uint8List.fromList([1, 2, 3, 4]),
      ),
    );
    expect(identical(cache.resolveDab(stampDab), stampDab), isTrue);
  });

  test('a hard round resolved dab covers the same disc: full alpha at the '
      'center, empty outside the radius', () {
    final cache = BrushTipStampCache();
    final resolved = cache.resolveDab(dab(size: 16, x: 16, y: 16));
    final result = materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(
        canvasSize: const CanvasSize(width: 32, height: 32),
        tileSize: 32,
      ),
      sequence: BrushDabSequence([resolved]),
    );
    final tile = result.surface.tiles[TileCoord(x: 0, y: 0)]!;
    int alphaAt(int x, int y) =>
        tile.pixels[tile.byteOffsetForPixel(x: x, y: y) + 3];

    expect(alphaAt(16, 16), 255, reason: 'center is fully covered');
    expect(alphaAt(16, 9), greaterThan(200), reason: 'inside the disc');
    expect(alphaAt(16, 2), 0, reason: 'outside the radius stays empty');
    expect(alphaAt(2, 2), 0, reason: 'corner outside the disc stays empty');
  });

  test('a 90°-rotated asymmetric raster tip resolves to the rotated '
      'footprint (prerotation)', () {
    // A 4x4 tip whose TOP half is opaque.
    final alpha = Uint8List(16);
    for (var i = 0; i < 8; i += 1) {
      alpha[i] = 255;
    }
    final tip = BrushTipMask(id: 'half', size: 4, alpha: alpha);
    final cache = BrushTipStampCache();

    final upright = cache.resolveDab(dab(size: 8, tipMask: tip));
    final rotated = cache.resolveDab(dab(size: 8, tipMask: tip, angle: 90));
    expect(identical(upright.tipMask, rotated.tipMask), isFalse);

    double halfMass(BrushTipMask mask, {required bool top, bool? left}) {
      var sum = 0.0;
      final size = mask.size;
      for (var y = 0; y < size; y += 1) {
        for (var x = 0; x < size; x += 1) {
          final inTop = y < size ~/ 2;
          final inLeft = x < size ~/ 2;
          final wanted = left == null ? (inTop == top) : (inLeft == left);
          if (wanted) {
            sum += mask.alpha[y * size + x];
          }
        }
      }
      return sum;
    }

    final uprightMask = upright.tipMask!;
    expect(
      halfMass(uprightMask, top: true),
      greaterThan(halfMass(uprightMask, top: false) * 4),
      reason: 'upright: mass stays in the top half',
    );
    // Visual CCW rotation in y-down canvas space maps the TOP half onto
    // one side; the mass must have LEFT the top/bottom split entirely.
    final rotatedMask = rotated.tipMask!;
    final leftMass = halfMass(rotatedMask, top: true, left: true);
    final rightMass = halfMass(rotatedMask, top: true, left: false);
    expect(
      (leftMass - rightMass).abs(),
      greaterThan((leftMass + rightMass) * 0.6),
      reason: '90°: mass concentrates on one horizontal side',
    );
  });

  test('size quantization: 1/4 px steps below 64 px, log steps above, '
      'round-trip stable', () {
    expect(
      BrushTipStampCache.dequantizeSize(
        BrushTipStampCache.quantizeSizeStep(12.10),
      ),
      closeTo(12.0, 0.13),
    );
    expect(
      BrushTipStampCache.dequantizeSize(
        BrushTipStampCache.quantizeSizeStep(12.24),
      ),
      closeTo(12.25, 0.01),
    );
    final big = BrushTipStampCache.dequantizeSize(
      BrushTipStampCache.quantizeSizeStep(500),
    );
    expect(big, closeTo(500, 500 * 0.011), reason: '~1.1% steps at 500px');
    // Quantization is a projection: dequantize(quantize(x)) is a fixpoint.
    final q = BrushTipStampCache.quantizeSizeStep(77.7);
    expect(
      BrushTipStampCache.quantizeSizeStep(BrushTipStampCache.dequantizeSize(q)),
      q,
    );
  });

  test('the LRU byte budget evicts oldest masks but keeps the newest', () {
    final cache = BrushTipStampCache(byteBudget: 1);
    final first = cache.resolveDab(dab(size: 10)).tipMask!;
    final second = cache.resolveDab(dab(size: 20)).tipMask!;
    expect(cache.entryCount, 1, reason: 'budget of 1 byte keeps only newest');
    expect(identical(cache.resolveDab(dab(size: 20)).tipMask, second), isTrue);
    expect(
      identical(cache.resolveDab(dab(size: 10)).tipMask, first),
      isFalse,
      reason: 'the evicted mask re-renders (deterministic bytes regardless)',
    );
  });
}
