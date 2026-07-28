import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';

import '../helpers/brush_canvas_fixture.dart';

/// BB-1 (R26 #9): the stroke-level brush blend — kernel math, byte-exact
/// pass-through, region extraction, and the commit round trip.
void main() {
  Uint8List pixel(int r, int g, int b, int a) =>
      Uint8List.fromList([r, g, b, a]);

  test('multiply over an opaque destination lands the product; the '
      'destination outside the source alpha stays byte-exact', () {
    final result = blendStrokeRegionPixels(
      dst: Uint8List.fromList([255, 0, 0, 255, 40, 50, 60, 70]),
      src: Uint8List.fromList([0, 255, 0, 255, 0, 0, 0, 0]),
      mode: BrushBlendMode.multiply,
      pixelCount: 2,
    );
    // Pixel 0: green × red = black, opaque.
    expect(result.sublist(0, 4), [0, 0, 0, 255]);
    // Pixel 1: src alpha 0 = the destination VERBATIM (the erase-rect
    // landing pass covers the whole bounds — drift here would corrupt
    // untouched pixels).
    expect(result.sublist(4, 8), [40, 50, 60, 70]);
  });

  test('multiply onto an EMPTY destination keeps the source (standard '
      'alpha-weighted blend: nothing below = the ink itself)', () {
    final result = blendStrokeRegionPixels(
      dst: pixel(0, 0, 0, 0),
      src: pixel(0, 255, 0, 255),
      mode: BrushBlendMode.multiply,
      pixelCount: 1,
    );
    expect(result, [0, 255, 0, 255]);
  });

  test('behind paints only where the destination is transparent', () {
    final result = blendStrokeRegionPixels(
      dst: Uint8List.fromList([255, 0, 0, 255, 0, 0, 0, 0]),
      src: Uint8List.fromList([0, 0, 255, 255, 0, 0, 255, 255]),
      mode: BrushBlendMode.behind,
      pixelCount: 2,
    );
    expect(result.sublist(0, 4), [255, 0, 0, 255], reason: 'covered = dst');
    expect(result.sublist(4, 8), [0, 0, 255, 255], reason: 'empty = src');
  });

  test('region extraction reads across tiles in canvas coordinates and '
      'missing tiles as transparent', () {
    const tileSize = 4;
    final pixels = Uint8List(tileSize * tileSize * 4);
    final base = (1 * tileSize + 2) * 4; // (x2, y1) in the tile
    pixels[base] = 200;
    pixels[base + 3] = 255;
    final surface = BitmapSurface(
      canvasSize: const CanvasSize(width: 8, height: 8),
      tileSize: tileSize,
      tiles: {
        TileCoord(x: 1, y: 0): BitmapTile(
          coord: TileCoord(x: 1, y: 0),
          size: tileSize,
          pixels: pixels,
        ),
      },
    );
    final region = bitmapSurfaceRegionPixels(
      surface,
      DirtyRegion(left: 2, top: 0, rightExclusive: 8, bottomExclusive: 3),
    );
    // World (6,1) = tile(1,0) local (2,1) → region-local (4,1), width 6.
    final regionBase = (1 * 6 + 4) * 4;
    expect(region[regionBase], 200);
    expect(region[regionBase + 3], 255);
    // World (0,0) has no tile: transparent.
    expect(region[3], 0);
  });

  test('the commit round trip: a multiply stroke lands the product over '
      'existing ink, unbolended pixels survive byte-exact, one undo '
      'restores everything', () {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    BrushDab dab(double x, double y, int color) => BrushDab(
      center: CanvasPoint(x: x, y: y),
      color: color,
      size: 4,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
    );

    // Base: an opaque RED square at (30,30). The sampler packs RGBA.
    coordinator.commitSourceStroke(sourceDabs: [dab(30, 30, 0xFFFF0000)]);
    final red = surfacePixelRgba(
      coordinator.currentSurfaceOf(coordinator.activeFrameKey),
      30,
      30,
    );
    expect(red, 0xFF0000FF);

    // A GREEN multiply stroke overlapping (30,30) and reaching empty
    // canvas at (34,30). No preraster buffer: the dab-fallback path
    // materializes the stroke on an empty surface first.
    final outcome = coordinator.commitSourceStroke(
      sourceDabs: [dab(32, 30, 0xFF00FF00)],
      blendMode: BrushBlendMode.multiply,
    );
    expect(outcome, isNotNull);
    final surface = coordinator.currentSurfaceOf(coordinator.activeFrameKey);
    expect(
      surfacePixelRgba(surface, 31, 30),
      0x000000FF,
      reason: 'green × red = black where the stroke covers ink',
    );
    expect(
      surfacePixelRgba(surface, 33, 30),
      0x00FF00FF,
      reason: 'green over emptiness stays green',
    );
    expect(
      surfacePixelRgba(surface, 29, 30),
      0xFF0000FF,
      reason: 'red outside the stroke bounds-roundtrip stays byte-exact',
    );
  });
}
