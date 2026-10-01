import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_pixel_coverage.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/stroke_pixel.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_pixel_blend.dart';
import 'package:anicel/src/services/brush_tip_stamp_cache.dart';

import '../helpers/native_engine_path.dart';

/// 🗣️유저 2026-10-01 (board `one-pixel-steps-change-a-brush-with-its-size`
/// Q2, 「a는 제안한대로 16비트?」): a stroke piles up on a 16-bit plane beside
/// its bytes (`qa_dab_store`, ABI 40). A dab used to round what it left to a
/// byte and the next dab read that byte back, so a soft tail laying under
/// half a level a dab never piled up at all.
///
/// Every case runs on the Dart kernel and on the C kernel, each built on an
/// empty buffer the way a stroke is.
void main() {
  const canvasSize = CanvasSize(width: 64, height: 64);
  final origin = TileCoord(x: 0, y: 0);
  const blue = 0xFF224488;
  final dllPath = nativeEngineLibraryPathOrNull();

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  /// A hard round dab over the middle of the only tile: full coverage at
  /// the pixel read below.
  BrushDab dab({required double flow, int color = blue, int sequence = 0}) =>
      BrushDab(
        center: CanvasPoint(x: 32, y: 32),
        color: color,
        size: 12,
        opacity: 1,
        flow: flow,
        hardness: 1,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: sequence,
      );

  List<int> pixelAfter(List<BrushDab> dabs) {
    final surface = materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: 64),
      sequence: BrushDabSequence(dabs),
    ).surface;
    final tile = surface.tileAt(origin)!;
    final at = tile.byteOffsetForPixel(x: 32, y: 32);
    return tile.pixels.sublist(at, at + 4);
  }

  void onEachEngine(String name, void Function() body) {
    test('$name — Dart kernel', () {
      QaNativeEngine.debugResetForTests();
      QaNativeEngine.debugForceDartFallback = true;
      expect(QaNativeEngine.instance, isNull);
      body();
    });
    test('$name — C kernel', () {
      if (dllPath == null) {
        markTestSkipped(nativeEngineMissingSkipReason);
        return;
      }
      QaNativeEngine.debugResetForTests();
      debugQaEngineLibraryPathOverride = dllPath;
      QaNativeEngine.debugForceDartFallback = false;
      expect(QaNativeEngine.instance, isNotNull);
      body();
    });
  }

  onEachEngine('a dab laying a quarter of a level still piles up', () {
    // Flow 0.001 lays 0.255 of a level over nothing: on bytes it rounded to
    // 0, the next dab found 0 again, and a hundred of them left nothing.
    // On the plane they pile up as they would in real numbers:
    // 1 − 0.999¹⁰⁰ = 0.0952 → 24.28 → 24.
    final dabs = [for (var i = 0; i < 100; i += 1) dab(flow: 0.001, sequence: i)];
    expect(pixelAfter(dabs)[3], 24);
    // ⚠️And as the canvas hands them over: a round tip prerendered as a mask
    // (BrushTipStampCache), which the C kernel blends two pixels at a time —
    // a road of its own (`qa_dab_blend_pairs`).
    expect(
      pixelAfter([
        for (final one in dabs) BrushTipStampCache.instance.resolveDab(one),
      ])[3],
      24,
    );
  });

  onEachEngine('a soft pile stays within a level of the real-number pile', () {
    // Flow 0.03: 1 − 0.97ⁿ, one rounding of the plane a dab — far below a
    // level after 120 dabs, where bytes drifted one rounding a dab.
    for (final count in [10, 40, 120]) {
      var exact = 0.0;
      for (var i = 0; i < count; i += 1) {
        exact = 0.03 + exact * (1.0 - 0.03);
      }
      final dabs = [
        for (var i = 0; i < count; i += 1) dab(flow: 0.03, sequence: i),
      ];
      expect(
        pixelAfter(dabs)[3],
        (exact * 255.0).round(),
        reason: '$count dabs: ${exact * 255.0}',
      );
    }
  });

  onEachEngine('a dab after a stamp piles over what the stamp left', () {
    // The stamp writes the bytes alone, so the plane under them goes stale:
    // a dab after it must read the stamp's picture, not the plane the dabs
    // before the stamp left (`CommitTileScratch`).
    const side = 20;
    final stamp = BrushStampImage(
      id: 'wide-plane-stamp',
      width: side,
      height: side,
      rgba: Uint8List.fromList([
        for (var p = 0; p < side * side; p += 1) ...[200, 40, 90, 150],
      ]),
    );
    final stampDab = BrushDab(
      center: CanvasPoint(x: 32, y: 32),
      color: 0xFF000000,
      size: side.toDouble(),
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 3,
      stamp: stamp,
    );
    final after = dab(flow: 0.37, color: 0xFF10E060, sequence: 4);
    final underStamp = pixelAfter([
      for (var i = 0; i < 3; i += 1) dab(flow: 0.2, sequence: i),
      stampDab,
    ]);
    final expected = blendBrushDabStrokePixel(
      dab: after,
      coverage: BrushPixelCoverage(x: 32, y: 32, coverage: 1),
      destination: StrokePixel.widened(
        RgbaColor(
          r: underStamp[0],
          g: underStamp[1],
          b: underStamp[2],
          a: underStamp[3],
        ),
      ),
    ).bytes;

    expect(
      pixelAfter([
        for (var i = 0; i < 3; i += 1) dab(flow: 0.2, sequence: i),
        stampDab,
        after,
      ]),
      [expected.r, expected.g, expected.b, expected.a],
    );
  });
}
