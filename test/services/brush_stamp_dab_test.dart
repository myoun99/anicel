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

/// R14-④ bitmap lift engine: RGBA stamp dabs land 1:1 through the stroke
/// funnel's materializer, and the erase-mask + stamp pair implements the
/// lift.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  BrushDab stampDab({
    required int left,
    required int top,
    required BrushStampImage stamp,
    double opacity = 1.0,
  }) {
    return BrushDab(
      center: CanvasPoint(x: left + stamp.width / 2, y: top + stamp.height / 2),
      color: 0xFF000000,
      size: stamp.width > stamp.height
          ? stamp.width.toDouble()
          : stamp.height.toDouble(),
      opacity: opacity,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      stamp: stamp,
    );
  }

  List<int> pixelAt(BitmapSurface surface, int x, int y) {
    final tileSize = surface.tileSize;
    final tile = surface.tiles[TileCoord(x: x ~/ tileSize, y: y ~/ tileSize)];
    if (tile == null) {
      return const [0, 0, 0, 0];
    }
    final pixels = tile.pixels;
    final offset = ((y % tileSize) * tileSize + (x % tileSize)) * 4;
    return pixels.sublist(offset, offset + 4);
  }

  test('a full-opacity stamp onto blank pixels lands byte-exactly 1:1', () {
    // A 2x3 stamp with distinct pixels, placed at (3, 2).
    final rgba = Uint8List.fromList([
      // row 0
      255, 0, 0, 255, /**/ 0, 255, 0, 128,
      // row 1
      0, 0, 255, 255, /**/ 10, 20, 30, 0,
      // row 2
      200, 100, 50, 64, /**/ 255, 255, 255, 255,
    ]);
    final stamp = BrushStampImage(
      id: 'lift-1',
      width: 2,
      height: 3,
      rgba: rgba,
    );

    final result = materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: 4),
      sequence: BrushDabSequence([stampDab(left: 3, top: 2, stamp: stamp)]),
    );

    expect(pixelAt(result.surface, 3, 2), [255, 0, 0, 255]);
    expect(pixelAt(result.surface, 4, 2), [0, 255, 0, 128]);
    expect(pixelAt(result.surface, 3, 3), [0, 0, 255, 255]);
    expect(
      pixelAt(result.surface, 4, 3),
      [0, 0, 0, 0],
      reason: 'alpha-0 stamp pixels leave the destination untouched',
    );
    expect(pixelAt(result.surface, 3, 4), [200, 100, 50, 64]);
    expect(pixelAt(result.surface, 4, 4), [255, 255, 255, 255]);
    // Outside the stamp rect nothing changes.
    expect(pixelAt(result.surface, 2, 2), [0, 0, 0, 0]);
    expect(pixelAt(result.surface, 5, 2), [0, 0, 0, 0]);
    // The stamp rect crosses the 4px tile boundary: both tiles dirty.
    expect(result.dirtyTiles.isNotEmpty, isTrue);
  });

  test('stamp opacity modulates like source-over paint', () {
    final stamp = BrushStampImage(
      id: 'lift-2',
      width: 1,
      height: 1,
      rgba: Uint8List.fromList([255, 0, 0, 255]),
    );
    final result = materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: 4),
      sequence: BrushDabSequence([
        stampDab(left: 1, top: 1, stamp: stamp, opacity: 0.5),
      ]),
    );

    expect(pixelAt(result.surface, 1, 1), [255, 0, 0, 128]);
  });

  test('the LIFT pair — erase mask at the origin + stamp at the target — '
      'moves exactly the masked pixels', () {
    // Base: a 2x2 red block at (1,1)..(2,2).
    var surface = BitmapSurface(canvasSize: canvasSize, tileSize: 4);
    final red = Uint8List.fromList([
      for (var i = 0; i < 4; i += 1) ...[255, 0, 0, 255],
    ]);
    surface = materializeBrushDabSequenceOnBitmapSurface(
      surface: surface,
      sequence: BrushDabSequence([
        stampDab(
          left: 1,
          top: 1,
          stamp: BrushStampImage(id: 'base', width: 2, height: 2, rgba: red),
        ),
      ]),
    ).surface;

    // Lift the LEFT column only: erase mask covers (1,1)-(1,2); the lifted
    // pixels land at (5,5).
    final maskAlpha = Uint8List.fromList([255, 0, 255, 0]);
    final eraseDab = BrushDab(
      center: CanvasPoint(x: 2, y: 2), // 2x2 mask over (1,1)..(2,2)
      color: 0xFF000000,
      size: 2,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      tipMask: BrushTipMask(id: 'lift-mask', size: 2, alpha: maskAlpha),
      erase: true,
    );
    final lifted = Uint8List.fromList([
      255,
      0,
      0,
      255,
      /**/ 0,
      0,
      0,
      0,
      255,
      0,
      0,
      255,
      /**/ 0,
      0,
      0,
      0,
    ]);
    final result = materializeBrushDabSequenceOnBitmapSurface(
      surface: surface,
      sequence: BrushDabSequence([
        eraseDab,
        stampDab(
          left: 5,
          top: 5,
          stamp: BrushStampImage(
            id: 'lift-3',
            width: 2,
            height: 2,
            rgba: lifted,
          ),
        ),
      ]),
    );

    // Origin: the masked column erased, the other column intact.
    expect(pixelAt(result.surface, 1, 1), [0, 0, 0, 0]);
    expect(pixelAt(result.surface, 1, 2), [0, 0, 0, 0]);
    expect(pixelAt(result.surface, 2, 1), [255, 0, 0, 255]);
    expect(pixelAt(result.surface, 2, 2), [255, 0, 0, 255]);
    // Target: the lifted pixels landed byte-exactly.
    expect(pixelAt(result.surface, 5, 5), [255, 0, 0, 255]);
    expect(pixelAt(result.surface, 5, 6), [255, 0, 0, 255]);
    expect(pixelAt(result.surface, 6, 5), [0, 0, 0, 0]);
  });

  test('a stamp-ERASE dab removes exactly the mask bytes — no resampled '
      'fringe ring (R15-④)', () {
    // Opaque red 3x3 block at (2,2).
    final red = Uint8List.fromList([
      for (var i = 0; i < 9; i += 1) ...[255, 0, 0, 255],
    ]);
    var surface = materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: 4),
      sequence: BrushDabSequence([
        stampDab(
          left: 2,
          top: 2,
          stamp: BrushStampImage(id: 'base', width: 3, height: 3, rgba: red),
        ),
      ]),
    ).surface;

    // Erase the CENTER column with a stamp-alpha erase.
    final eraseRgba = Uint8List.fromList([
      0,
      0,
      0,
      0,
      /**/ 0,
      0,
      0,
      255,
      /**/ 0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      /**/ 0,
      0,
      0,
      255,
      /**/ 0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      /**/ 0,
      0,
      0,
      255,
      /**/ 0,
      0,
      0,
      0,
    ]);
    final result = materializeBrushDabSequenceOnBitmapSurface(
      surface: surface,
      sequence: BrushDabSequence([
        stampDab(
          left: 2,
          top: 2,
          stamp: BrushStampImage(
            id: 'erase',
            width: 3,
            height: 3,
            rgba: eraseRgba,
          ),
        ).copyWith(erase: true),
      ]),
    );

    for (var y = 2; y <= 4; y += 1) {
      expect(pixelAt(result.surface, 3, y), [
        0,
        0,
        0,
        0,
      ], reason: 'masked pixels erase to byte zero');
      expect(
        pixelAt(result.surface, 2, y),
        [255, 0, 0, 255],
        reason: 'unmasked neighbors keep FULL alpha — no fringe ring',
      );
      expect(pixelAt(result.surface, 4, y), [255, 0, 0, 255]);
    }
  });
}
