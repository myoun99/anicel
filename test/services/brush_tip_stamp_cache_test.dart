import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
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

/// R20-B tip-stamp cache (the CSP/PS brush architecture): every analytic
/// dab resolves to a prerendered, quantized, PREROTATED raster mask consumed
/// through the existing unrotated-lattice fast path; a raster tip is sampled
/// as it is (F-251). Resolution is idempotent and deterministic; the same
/// key returns the same mask object, so uploads and lattices amortize across
/// a stroke.
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
    // At 없음: the disc itself, with no anti-alias edge grown inside it
    // (I-50 — at 3단계 the stamp carries a ramp in from the rim).
    final resolved = cache.resolveDab(
      dab(size: 16, x: 16, y: 16).copyWith(antiAlias: BrushAntiAlias.none),
    );
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

  // F-251 (2026-10-01): a raster tip is sampled where it is — baking one cost
  // its source's resolution per degree, and the baked mask lost the corners.
  group('a raster tip is not baked', () {
    BrushTipMask solid() => BrushTipMask(
      id: 'solid',
      size: 4,
      alpha: Uint8List(16)..fillRange(0, 16, 255),
    );

    int alphaAt(BitmapSurface surface, int x, int y) {
      final tile = surface.tiles[TileCoord(x: 0, y: 0)];
      return tile == null
          ? 0
          : tile.pixels[tile.byteOffsetForPixel(x: x, y: y) + 3];
    }

    BitmapSurface laid(BrushDab dab) =>
        materializeBrushDabSequenceOnBitmapSurface(
          surface: BitmapSurface(
            canvasSize: const CanvasSize(width: 64, height: 64),
            tileSize: 64,
          ),
          sequence: BrushDabSequence([BrushTipStampCache().resolveDab(dab)]),
        ).surface;

    test('it passes through as it is — its own mask, angle and roundness, '
        'and nothing in the cache', () {
      final cache = BrushTipStampCache();
      final raster = dab(
        size: 6,
        tipMask: solid(),
        angle: 117,
        roundness: 0.6,
      );
      expect(identical(cache.resolveDab(raster), raster), isTrue);
      expect(cache.entryCount, 0);
    });

    test('a rotated one keeps its corners', () {
      // A solid square turned 45° reaches its radius × √2 along the axes —
      // 14px from the centre of a 20px dab. The baked mask held only the
      // dab's own box and cut that off at 10.
      final turned = laid(
        dab(size: 20, tipMask: solid(), angle: 45, x: 32, y: 32),
      );
      expect(alphaAt(turned, 44, 32), greaterThan(0), reason: 'past the box');
      expect(alphaAt(turned, 32, 44), greaterThan(0), reason: 'past the box');
      expect(
        alphaAt(turned, 42, 42),
        0,
        reason: 'the box corner is outside the turned square',
      );
    });

    test('a 90° turn moves an asymmetric tip onto one side', () {
      // A 4x4 tip whose TOP half is opaque.
      final half = BrushTipMask(
        id: 'half',
        size: 4,
        alpha: Uint8List(16)..fillRange(0, 8, 255),
      );
      double mass(BitmapSurface surface, bool Function(int x, int y) keep) {
        var sum = 0.0;
        for (var y = 22; y < 42; y += 1) {
          for (var x = 22; x < 42; x += 1) {
            if (keep(x, y)) {
              sum += alphaAt(surface, x, y);
            }
          }
        }
        return sum;
      }

      final upright = laid(dab(size: 16, tipMask: half, x: 32, y: 32));
      expect(
        mass(upright, (_, y) => y < 32),
        greaterThan(mass(upright, (_, y) => y >= 32) * 4),
        reason: 'upright: the mass stays in the top half',
      );
      final turned = laid(
        dab(size: 16, tipMask: half, angle: 90, x: 32, y: 32),
      );
      final left = mass(turned, (x, _) => x < 32);
      final right = mass(turned, (x, _) => x >= 32);
      expect(
        (left - right).abs(),
        greaterThan((left + right) * 0.6),
        reason: '90°: the mass concentrates on one side',
      );
    });
  });

  test('a circle is one stamp at every angle — an ellipse is not', () {
    final cache = BrushTipStampCache();
    final level = cache.resolveDab(dab(size: 30)).tipMask;
    final turned = cache.resolveDab(dab(size: 30, angle: 137)).tipMask;
    expect(identical(turned, level), isTrue);
    final ellipse = cache.resolveDab(dab(size: 30, roundness: 0.5)).tipMask;
    final turnedEllipse = cache
        .resolveDab(dab(size: 30, roundness: 0.5, angle: 137))
        .tipMask;
    expect(identical(turnedEllipse, ellipse), isFalse);
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
