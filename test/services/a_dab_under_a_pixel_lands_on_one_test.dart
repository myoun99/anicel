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
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_dab_interpolator.dart';
import 'package:anicel/src/services/mark_under_a_pixel.dart';
import 'package:anicel/src/services/brush_tip_stamp_cache.dart';

import '../helpers/native_engine_path.dart';

/// size-rack-0-7-under-the-brush-floor (유저 2026-10-12 「브러시 사이즈
/// 최소치만 0.1까지 내림」, 10-17 「다른부분 발견되는거있으면 법 통일」): a
/// dab narrower than a pixel lands as the one-pixel dab, its opacity scaled
/// by its size — the law ([liftedToOnePixel]), the cache every stroke's dabs
/// resolve through, and the pixels both kernels lay from it.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  BrushDab dab({
    double size = 0.3,
    BrushAntiAlias antiAlias = BrushAntiAlias.high,
    BrushStampImage? stamp,
    BrushTipMask? tipMask,
  }) => BrushDab(
    center: CanvasPoint(x: 10.25, y: 7.5),
    color: 0xFF336699,
    size: size,
    opacity: 0.8,
    flow: 0.9,
    hardness: 0.7,
    pressure: 0.6,
    sequence: 3,
    tipShape: BrushTipShape.round,
    antiAlias: antiAlias,
    stamp: stamp,
    tipMask: tipMask,
  );

  group('the law', () {
    test('a mark under a pixel is a pixel across, keeping as much of its '
        'opacity as its width — all of it with anti-aliasing off', () {
      expect(markUnderAPixel(0.3, antiAliased: true), (
        width: 1.0,
        opacity: 0.3,
      ));
      expect(markUnderAPixel(0.3, antiAliased: false), (
        width: 1.0,
        opacity: 1.0,
      ));
      for (final width in [1.0, 2.5, 0.0]) {
        expect(
          markUnderAPixel(width, antiAliased: true),
          (width: width, opacity: 1.0),
          reason: 'width $width',
        );
      }
    });

    test('a dab under a pixel is the one-pixel dab, its opacity times its '
        'size — the rest of it as it was', () {
      final lifted = liftedToOnePixel(dab());

      expect(lifted.size, 1.0);
      expect(lifted.opacity, closeTo(0.8 * 0.3, 1e-12));
      expect(
        (lifted.center, lifted.color, lifted.flow, lifted.hardness),
        (CanvasPoint(x: 10.25, y: 7.5), 0xFF336699, 0.9, 0.7),
      );
    });

    test('⛔anti-aliasing off: its one-pixel dab lands whole (H39)', () {
      final lifted = liftedToOnePixel(dab(antiAlias: BrushAntiAlias.none));

      expect(lifted.size, 1.0);
      expect(lifted.opacity, 0.8);
    });

    test('a pixel or more, no size at all, and a stamp are left as they '
        'are', () {
      for (final size in [1.0, 2.5, 0.0]) {
        final kept = dab(size: size);
        expect(liftedToOnePixel(kept), same(kept), reason: 'size $size');
      }
      final lift = dab(
        size: 0.5,
        stamp: BrushStampImage(
          id: 'lift',
          width: 1,
          height: 1,
          rgba: Uint8List(4),
        ),
      );
      expect(liftedToOnePixel(lift), same(lift));
    });
  });

  group('the tip-stamp cache every stroke\'s dabs resolve through', () {
    test('lands a dab under a pixel on the one-pixel stamp', () {
      final cache = BrushTipStampCache();
      final resolved = cache.resolveDab(dab());

      expect(resolved.size, 1.0);
      expect(resolved.opacity, closeTo(0.8 * 0.3, 1e-12));
      expect(
        resolved.tipMask!.id,
        cache.resolveDab(dab(size: 1)).tipMask!.id,
        reason: 'the stamp a one-pixel dab is drawn with — ↩️the cache held '
            'a dab to a quarter of a pixel, so 0.1 and 0.25 drew alike',
      );
    });

    test('and a raster tip\'s dab under a pixel, its tip as it was', () {
      final grain = BrushTipMask(
        id: 'grain',
        size: 4,
        alpha: Uint8List(16)..fillRange(0, 16, 255),
      );
      final resolved = BrushTipStampCache().resolveDab(
        dab(size: 0.4, tipMask: grain),
      );

      expect(resolved.size, 1.0);
      expect(resolved.opacity, closeTo(0.8 * 0.4, 1e-12));
      expect(resolved.tipMask, same(grain));
    });
  });

  /// The alpha a level line lays on a 64 × 64 canvas, pixel by pixel:
  /// [width] across, through [y], forty pixels on from x [from] — laid by
  /// the interpolator and resolved through the cache, as the canvas lays a
  /// stroke's dabs.
  Uint8List line(
    double width, {
    required double y,
    required double from,
    BrushAntiAlias antiAlias = BrushAntiAlias.high,
  }) {
    BrushDab at(double x, int sequence) => BrushDab(
      center: CanvasPoint(x: x, y: y),
      color: 0xFF000000,
      size: width,
      opacity: 1,
      flow: 1,
      hardness: 1,
      pressure: 1,
      sequence: sequence,
      tipShape: BrushTipShape.round,
      antiAlias: antiAlias,
    );
    final first = at(from, 0);
    final dabs = [
      first,
      ...const BrushDabInterpolator().interpolate(
        previous: first,
        nextRaw: at(from + 40, 1),
        firstSequence: 1,
      ),
    ];
    final surface = materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(
        canvasSize: const CanvasSize(width: 64, height: 64),
        tileSize: 64,
      ),
      sequence: BrushDabSequence(BrushTipStampCache.instance.resolveDabs(dabs)),
    ).surface;
    final alpha = Uint8List(64 * 64);
    for (final tile in surface.tiles.values) {
      tile.readPixels((_, view) {
        for (var i = 0; i < alpha.length; i += 1) {
          alpha[i] = view[i * 4 + 3];
        }
      });
    }
    return alpha;
  }

  // Where a line lies across the pixels: through a row's centre, a quarter
  // below it, nearly on the next row — from a pixel's edge, a fifth in, and
  // its middle.
  const placements = [
    (y: 16.5, from: 10.0),
    (y: 16.75, from: 10.2),
    (y: 16.95, from: 10.5),
  ];

  final routes = <({String name, bool native})>[
    (name: 'Dart kernel', native: false),
    if (libraryPath != null) (name: 'C kernel', native: true),
  ];

  for (final route in routes) {
    void useRoute() {
      QaNativeEngine.debugResetForTests();
      QaNativeEngine.debugForceDartFallback = !route.native;
      debugQaEngineLibraryPathOverride = route.native ? libraryPath : null;
      expect(
        QaNativeEngine.instance != null,
        route.native,
        reason: 'the route must be the one it says it is',
      );
    }

    test('🎯a line under a pixel wide lays what the one-pixel line lays, '
        'lighter by its width — ${route.name}', () {
      useRoute();
      for (final place in placements) {
        final whole = line(1, y: place.y, from: place.from);
        expect(
          whole.where((alpha) => alpha > 0),
          isNotEmpty,
          reason: 'premise: the one-pixel line draws at $place',
        );
        for (final width in [0.1, 0.5, 0.9]) {
          final thin = line(width, y: place.y, from: place.from);
          final off = [
            for (var i = 0; i < thin.length; i += 1)
              if ((thin[i] - whole[i] * width).abs() > 2)
                (x: i % 64, y: i ~/ 64, thin: thin[i], whole: whole[i]),
          ];
          expect(off, isEmpty, reason: '$width wide at $place');
        }
      }
    });

    test('🚨anti-aliasing off: a line under a pixel wide lays the one-pixel '
        'line whole, no pixel partly covered (H39) — ${route.name}', () {
      useRoute();
      const none = BrushAntiAlias.none;
      for (final place in placements) {
        final whole = line(1, y: place.y, from: place.from, antiAlias: none);
        for (final width in [0.1, 0.5]) {
          final thin = line(
            width,
            y: place.y,
            from: place.from,
            antiAlias: none,
          );
          expect(thin, whole, reason: '$width wide at $place');
          expect(
            thin.where((alpha) => alpha > 0 && alpha < 255),
            isEmpty,
            reason: '「진짜 안티앨리어싱 완전없었으면」 — $width wide at $place',
          );
        }
      }
      expect(
        line(0.5, y: 16.5, from: 10.0, antiAlias: none).where(
          (alpha) => alpha == 255,
        ),
        isNotEmpty,
        reason: 'premise: it draws',
      );
    });
  }
}
