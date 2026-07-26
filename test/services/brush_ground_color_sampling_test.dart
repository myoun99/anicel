import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/bitmap_surface.dart';
import 'package:quick_animaker_v2/src/models/bitmap_tile.dart';
import 'package:quick_animaker_v2/src/models/canvas_size.dart';
import 'package:quick_animaker_v2/src/models/tile_coord.dart';
import 'package:quick_animaker_v2/src/services/brush_ground_color_sampling.dart';

const int _tileSize = 32;

/// A surface whose single tile is filled by [paint], which returns straight
/// RGBA for a pixel or null to leave it bare.
BitmapSurface surfaceWith(List<int>? Function(int x, int y) paint) {
  final pixels = Uint8List(_tileSize * _tileSize * 4);
  for (var y = 0; y < _tileSize; y += 1) {
    for (var x = 0; x < _tileSize; x += 1) {
      final rgba = paint(x, y);
      if (rgba == null) {
        continue;
      }
      pixels.setRange((y * _tileSize + x) * 4, (y * _tileSize + x) * 4 + 4, rgba);
    }
  }
  return BitmapSurface(
    canvasSize: const CanvasSize(width: _tileSize, height: _tileSize),
    tileSize: _tileSize,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        coord: TileCoord(x: 0, y: 0),
        size: _tileSize,
        pixels: pixels,
      ),
    },
  );
}

void main() {
  test('a bare surface reports no ground', () {
    final surface = surfaceWith((_, _) => null);

    final sample = sampleBitmapSurfaceGround(
      surface,
      centerX: 16,
      centerY: 16,
      radius: 8,
    );

    expect(sample.coverage, 0.0);
  });

  test('a solid area reports its colour at full coverage', () {
    final surface = surfaceWith((_, _) => [200, 100, 50, 255]);

    final sample = sampleBitmapSurfaceGround(
      surface,
      centerX: 16,
      centerY: 16,
      radius: 8,
    );

    expect(sample.rgb, (200 << 16) | (100 << 8) | 50);
    expect(sample.coverage, closeTo(1.0, 1e-9));
  });

  test('transparent pixels lower coverage without darkening the colour', () {
    // The trap this guards: transparent pixels carry RGB 0, so a plain mean
    // would report a dark grey instead of the white that is actually there.
    // Paint the left half only, so the disc straddles painted and bare.
    // (A per-pixel checker would be a bad fixture here: the fixed sample
    // grid can land entirely on one phase of it and prove nothing.)
    final surface = surfaceWith(
      (x, _) => x < 16 ? [255, 255, 255, 255] : null,
    );

    final sample = sampleBitmapSurfaceGround(
      surface,
      centerX: 16,
      centerY: 16,
      radius: 8,
    );

    expect(sample.rgb, 0xFFFFFF, reason: 'colour comes from painted pixels');
    expect(sample.coverage, lessThan(1.0));
    expect(sample.coverage, greaterThan(0.0));
  });

  test('partial alpha weights the average', () {
    // Half-alpha white over nothing: the colour is still white, but only
    // half the disc counts as painted.
    final surface = surfaceWith((_, _) => [255, 255, 255, 128]);

    final sample = sampleBitmapSurfaceGround(
      surface,
      centerX: 16,
      centerY: 16,
      radius: 8,
    );

    expect(sample.rgb, 0xFFFFFF);
    expect(sample.coverage, closeTo(128 / 255, 0.01));
  });

  test('sampling off the canvas reports no ground', () {
    final surface = surfaceWith((_, _) => [255, 255, 255, 255]);

    final sample = sampleBitmapSurfaceGround(
      surface,
      centerX: 500,
      centerY: 500,
      radius: 8,
    );

    expect(sample.coverage, 0.0);
  });

  test('the sample count is fixed, whatever the brush size', () {
    // The point of the fixed grid: a huge dab must not turn into a per-pixel
    // read. The cost of that is real and worth stating — the grid spreads
    // with the radius, so a dab far larger than the painted area can step
    // right over it. That is acceptable for an average colour, and it is why
    // the sampler reports coverage rather than pretending it found paint.
    final surface = surfaceWith((_, _) => [10, 20, 30, 255]);

    final small = sampleBitmapSurfaceGround(
      surface,
      centerX: 16,
      centerY: 16,
      radius: 2,
    );
    expect(small.rgb, (10 << 16) | (20 << 8) | 30);
    expect(small.coverage, closeTo(1.0, 1e-9));

    // 250px between samples on a 32px canvas: every point lands outside.
    final huge = sampleBitmapSurfaceGround(
      surface,
      centerX: 16,
      centerY: 16,
      radius: 1000,
    );
    expect(huge.coverage, 0.0);
  });
}
