import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';

void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  /// An 8×8 surface (2×2 tiles of 4) with straight-RGBA [pixels] set at
  /// canvas points.
  BitmapSurface surfaceWithPixels(Map<(int, int), List<int>> pixels) {
    final tiles = <TileCoord, Uint8List>{};
    for (final entry in pixels.entries) {
      final (x, y) = entry.key;
      final coord = TileCoord(x: x ~/ 4, y: y ~/ 4);
      final buffer = tiles.putIfAbsent(coord, () => Uint8List(4 * 4 * 4));
      final index = ((y % 4) * 4 + (x % 4)) * 4;
      buffer.setAll(index, entry.value);
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 4,
      tiles: {
        for (final entry in tiles.entries)
          entry.key: BitmapTile(coord: entry.key, size: 4, pixels: entry.value),
      },
    );
  }

  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);

  Layer layer(
    String id, {
    double opacity = 1,
    TransformTrack? transformTrack,
  }) => Layer(
    id: LayerId(id),
    name: id,
    frames: [frame('$id-frame')],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-frame'), length: 1)},
    opacity: opacity,
    transformTrack: transformTrack ?? TransformTrack.empty(),
  );

  Cut cut(List<Layer> layers) => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    layers: layers,
    duration: 24,
    canvasSize: canvasSize,
  );

  group('surfacePixelRgba', () {
    test('reads a pixel through the tile grid', () {
      final surface = surfaceWithPixels({
        (5, 2): [0x11, 0x22, 0x33, 0xFF],
      });
      expect(surfacePixelRgba(surface, 5, 2), 0x112233FF);
    });

    test('missing tiles are transparent; only beyond the PASTEBOARD wall '
        'is null (off-canvas pixels are pickable, Flash-style)', () {
      final surface = surfaceWithPixels({
        (0, 0): [1, 2, 3, 4],
      });
      expect(surfacePixelRgba(surface, 6, 6), 0);
      expect(surfacePixelRgba(surface, -1, 0), 0,
          reason: 'off-canvas but on the pasteboard = transparent, not null');
      expect(surfacePixelRgba(surface, 8, 0), 0);
      // The 8×8 stage's 5x5 pasteboard: x,y ∈ [-16, 24).
      expect(surfacePixelRgba(surface, -17, 0), isNull);
      expect(surfacePixelRgba(surface, 24, 0), isNull);
    });

    test('reads OFF-canvas pixels through negative tiles (floorDiv — the '
        'eyedropper picks pasteboard artwork)', () {
      // Canvas point (-3, 2) lives on tile (-1, 0) at local (1, 2)
      // (Dart % is Euclidean: -3 % 4 == 1).
      final buffer = Uint8List(4 * 4 * 4);
      buffer.setAll((2 * 4 + 1) * 4, [0xAA, 0xBB, 0xCC, 0xFF]);
      final surface = BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 4,
        tiles: {
          TileCoord(x: -1, y: 0): BitmapTile(
            coord: TileCoord(x: -1, y: 0),
            size: 4,
            pixels: buffer,
          ),
        },
      );
      expect(surfacePixelRgba(surface, -3, 2), 0xAABBCCFF);
    });
  });

  group('sampleCompositeColor', () {
    test('empty canvas samples the paper color', () {
      final color = sampleCompositeColor(
        cut: cut([layer('a')]),
        frameIndex: 0,
        surfaceResolver: (_, _) => null,
        point: CanvasPoint(x: 3, y: 3),
      );
      expect(color, canvasPaperColor);
    });

    test('an opaque pixel samples exactly', () {
      final surface = surfaceWithPixels({
        (3, 3): [0xFF, 0x00, 0x00, 0xFF],
      });
      final color = sampleCompositeColor(
        cut: cut([layer('a')]),
        frameIndex: 0,
        surfaceResolver: (_, _) => surface,
        point: CanvasPoint(x: 3.4, y: 3.9),
      );
      expect(color, 0xFFFF0000);
    });

    test('layer opacity blends over the paper', () {
      final surface = surfaceWithPixels({
        (3, 3): [0xFF, 0x00, 0x00, 0xFF],
      });
      final color = sampleCompositeColor(
        cut: cut([layer('a', opacity: 0.5)]),
        frameIndex: 0,
        surfaceResolver: (_, _) => surface,
        point: CanvasPoint(x: 3, y: 3),
      );
      // R28 #9: the paper is pure white now.
      // r = 255·0.5 + 255·0.5 = 255; g = b = 255·0.5 = 127.5 → 128.
      expect(color, 0xFFFF8080);
    });

    test('pixel alpha blends over the paper', () {
      final surface = surfaceWithPixels({
        (3, 3): [0xFF, 0x00, 0x00, 0x80],
      });
      final color = sampleCompositeColor(
        cut: cut([layer('a')]),
        frameIndex: 0,
        surfaceResolver: (_, _) => surface,
        point: CanvasPoint(x: 3, y: 3),
      );
      // α = 128/255: r = 255·α + 255·(1−α) = 255, g = b = 255·(1−α) ≈ 127.
      expect(color, 0xFFFF7F7F);
    });

    test('the top layer wins where opaque', () {
      final red = surfaceWithPixels({
        (3, 3): [0xFF, 0x00, 0x00, 0xFF],
      });
      final blue = surfaceWithPixels({
        (3, 3): [0x00, 0x00, 0xFF, 0xFF],
      });
      final color = sampleCompositeColor(
        cut: cut([layer('bottom'), layer('top')]),
        frameIndex: 0,
        surfaceResolver: (layer, _) => layer.id.value == 'bottom' ? red : blue,
        point: CanvasPoint(x: 3, y: 3),
      );
      expect(color, 0xFF0000FF);
    });

    test('R28 #7: a POSED layer samples through the inverse of its pose — '
        'the pick matches what the screen shows', () {
      final surface = surfaceWithPixels({
        (3, 3): [0x00, 0xFF, 0x00, 0xFF],
      });
      // 2× about the canvas centre (4,4): artwork (3,3) is painted over
      // the canvas square starting at (2,2).
      final posed = cut([
        layer(
          'a',
          transformTrack: TransformTrack.empty().copyWith(
            scale: PropertyTrack<double>.empty().withKey(0, 2.0),
          ),
        ),
      ]);

      expect(
        sampleCompositeColor(
          cut: posed,
          frameIndex: 0,
          surfaceResolver: (_, _) => surface,
          point: CanvasPoint(x: 2, y: 2),
        ),
        0xFF00FF00,
        reason: 'the posed pixel is pickable where it is DRAWN; the old v1 '
            'skipped posed layers entirely and returned paper',
      );
      // Where the scaled artwork has nothing, the paper still shows.
      expect(
        sampleCompositeColor(
          cut: posed,
          frameIndex: 0,
          surfaceResolver: (_, _) => surface,
          point: CanvasPoint(x: 6, y: 6),
        ),
        canvasPaperColor,
      );
      // With the layer's fx bypassed the pose drops out, so the pixel sits
      // at its untransformed home again.
      expect(
        sampleCompositeColor(
          cut: posed,
          frameIndex: 0,
          surfaceResolver: (_, _) => surface,
          point: CanvasPoint(x: 3, y: 3),
          fxBypassedLayerIds: {const LayerId('a')},
        ),
        0xFF00FF00,
      );
      expect(
        sampleCompositeColor(
          cut: posed,
          frameIndex: 0,
          surfaceResolver: (_, _) => surface,
          point: CanvasPoint(x: 2, y: 2),
          fxBypassedLayerIds: {const LayerId('a')},
        ),
        canvasPaperColor,
      );
    });

    test('R28 #6: the LAYER source reads the active layer alone; DISPLAY '
        'reads the whole stack', () {
      final red = surfaceWithPixels({
        (3, 3): [0xFF, 0x00, 0x00, 0xFF],
      });
      final blue = surfaceWithPixels({
        (3, 3): [0x00, 0x00, 0xFF, 0xFF],
      });
      final stack = cut([layer('bottom'), layer('top')]);
      BitmapSurface? resolve(layer, _) =>
          layer.id.value == 'bottom' ? red : blue;

      // Display: the top layer wins, as it does on screen.
      expect(
        sampleCompositeColor(
          cut: stack,
          frameIndex: 0,
          surfaceResolver: resolve,
          point: CanvasPoint(x: 3, y: 3),
        ),
        0xFF0000FF,
      );
      // Layer: the ACTIVE row's own pixel, even though another layer
      // covers it.
      expect(
        sampleCompositeColor(
          cut: stack,
          frameIndex: 0,
          surfaceResolver: resolve,
          point: CanvasPoint(x: 3, y: 3),
          source: CanvasColorSampleSource.layer,
          activeLayerId: const LayerId('bottom'),
        ),
        0xFFFF0000,
      );
      // A row with nothing drawn there (or nothing drawable at all — an SE
      // row) reads the canvas color, per the user's description.
      expect(
        sampleCompositeColor(
          cut: stack,
          frameIndex: 0,
          surfaceResolver: resolve,
          point: CanvasPoint(x: 1, y: 1),
          source: CanvasColorSampleSource.layer,
          activeLayerId: const LayerId('bottom'),
        ),
        canvasPaperColor,
      );
    });

    test('points outside the canvas sample the paper', () {
      final surface = surfaceWithPixels({
        (0, 0): [0xFF, 0x00, 0x00, 0xFF],
      });
      final color = sampleCompositeColor(
        cut: cut([layer('a')]),
        frameIndex: 0,
        surfaceResolver: (_, _) => surface,
        point: CanvasPoint(x: -2, y: 11),
      );
      expect(color, canvasPaperColor);
    });
  });
}
