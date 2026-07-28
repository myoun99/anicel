@Tags(['benchmark'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';

import '../helpers/native_engine_path.dart';

/// §C's PRE-MEASUREMENT (not a correctness test): what does one frame of
/// pre-blend actually cost today?
///
/// The pre-blend runs per touched tile — one blend call and one
/// premultiply call each, both with count=1, which means the C worker
/// pool never engages (a one-item batch runs inline on the caller). A
/// big brush touches ~200 tiles on its FIRST dab, so the question the
/// batch kernel exists to answer is: how much of a frame is that serial
/// fan-out, and how much of it is the FFI boundary versus the pixel math?
///
/// Prints; asserts only that the work happened.
void main() {
  final dllPath = nativeEngineLibraryPathOrNull();

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  test('pre-blend cost per frame, by touched-tile count', () {
    if (dllPath == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
    expect(QaNativeEngine.instance, isNotNull);

    const tileSize = 256;
    // A canvas big enough to hold a giant brush's footprint.
    const canvasSize = CanvasSize(width: 4096, height: 4096);

    for (final brushSize in [256.0, 1000.0, 1800.0]) {
      // A painted base so the staging copy has real bytes to move.
      final base = materializeBrushDabSequenceOnBitmapSurface(
        surface: BitmapSurface(canvasSize: canvasSize, tileSize: tileSize),
        sequence: BrushDabSequence([
          BrushDab(
            center: CanvasPoint(x: 2048, y: 2048),
            color: 0xFF994411,
            size: brushSize + 400,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: 0,
          ),
        ]),
      ).surface;

      final rasterizer = BrushLiveStrokeRasterizer(
        canvasSize: canvasSize,
        tileSize: tileSize,
      );
      rasterizer.blendFrom([
        BrushDab(
          center: CanvasPoint(x: 2048, y: 2048),
          color: 0xB02266AA,
          size: brushSize,
          opacity: 0.8,
          flow: 0.9,
          hardness: 0.5,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: 0,
        ),
      ], from: 0);

      final bounds = rasterizer.strokeBounds!;
      final coords = bounds.toTileCoords(tileSize: tileSize).toList();

      // Warm: first pass allocates the resident results.
      for (final coord in coords) {
        rasterizer
            .preBlendedOverlayTile(
              tileX: coord.x,
              tileY: coord.y,
              base: base,
              mode: BrushBlendMode.multiply,
              erase: false,
            )
            ?.free();
      }

      // Measured: the steady-state frame — every touched tile re-blends
      // because the brush moved over it again.
      const rounds = 20;
      // Two clocks: the dab blend (unchanged by this round) and the
      // pre-blend (what the batch kernel replaced). Timing them together
      // would hide the pre-blend behind a 2.5M-pixel dab.
      final dabWatch = Stopwatch();
      final watch = Stopwatch();
      for (var round = 0; round < rounds; round += 1) {
        dabWatch.start();
        rasterizer.blendFrom([
          BrushDab(
            center: CanvasPoint(x: 2048 + round + 1, y: 2048),
            color: 0xB02266AA,
            size: brushSize,
            opacity: 0.8,
            flow: 0.9,
            hardness: 0.5,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: round + 1,
          ),
        ], from: 0);
        dabWatch.stop();
        watch.start();
        for (final tile in rasterizer.preBlendedOverlayTiles(
          coords: coords,
          base: base,
          mode: BrushBlendMode.multiply,
          erase: false,
        )) {
          tile?.free();
        }
        watch.stop();
      }
      final perFrameUs = watch.elapsedMicroseconds / rounds;
      final dabUs = dabWatch.elapsedMicroseconds / rounds;
      // ignore: avoid_print
      print(
        'pre-blend ${brushSize.toInt()}px brush: ${coords.length} tiles, '
        '${(perFrameUs / 1000).toStringAsFixed(1)}ms/frame '
        '(${(perFrameUs / coords.length).toStringAsFixed(1)}us/tile) '
        '[dab blend ${(dabUs / 1000).toStringAsFixed(1)}ms]',
      );
      expect(coords, isNotEmpty);
      rasterizer.clear();
    }
  });
}
