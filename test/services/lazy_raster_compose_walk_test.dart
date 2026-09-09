import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';

import '../helpers/native_engine_path.dart';

/// The fill raster's compose walk under a NEGATIVE origin (an extended
/// fill): which surface tile a raster pixel reads, and where a surface
/// tile that straddles a compose-tile wall is clipped. The three walks
/// that used to write this out — per-tile Dart, per-tile native, batch
/// native — must agree byte for byte, and the Dart one is the reference.
void main() {
  final dllPath = nativeEngineLibraryPathOrNull();
  final available = dllPath != null;

  setUp(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
  });

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);
  Layer layerWith(String id, double opacity) => Layer(
    id: LayerId(id),
    name: id,
    opacity: opacity,
    frames: [frame('$id-frame')],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-frame'), length: 1)},
  );

  /// A surface with one pixel per entry of [pixels]: world (x, y) →
  /// straight RGBA. Tiles at negative coordinates are made as needed.
  BitmapSurface surfaceWith(
    CanvasSize canvasSize,
    int tileSize,
    Map<(int, int), List<int>> pixels,
  ) {
    final buffers = <TileCoord, Uint8List>{};
    for (final entry in pixels.entries) {
      final (x, y) = entry.key;
      final coord = TileCoord.fromPixel(
        pixelX: x,
        pixelY: y,
        tileSize: tileSize,
      );
      final buffer = buffers.putIfAbsent(
        coord,
        () => Uint8List(tileSize * tileSize * 4),
      );
      final index =
          ((y - coord.y * tileSize) * tileSize + (x - coord.x * tileSize)) * 4;
      buffer.setRange(index, index + 4, entry.value);
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: {
        for (final entry in buffers.entries)
          entry.key: BitmapTile(
            coord: entry.key,
            size: tileSize,
            pixels: entry.value,
          ),
      },
    );
  }

  List<int> rgbAt(LazyCanvasRasterRgb raster, int rasterX, int rasterY) {
    final base = (rasterY * raster.width + rasterX) * 4;
    return raster.rgb.sublist(base, base + 3);
  }

  group('an 8×8 canvas with two layers, extended one canvas each way', () {
    const canvasSize = CanvasSize(width: 8, height: 8);
    final below = surfaceWith(canvasSize, 4, {
      (-1, -1): [255, 0, 0, 255],
      (1, 2): [0, 255, 0, 128],
    });
    final above = surfaceWith(canvasSize, 4, {
      (-2, -1): [0, 0, 255, 255],
    });
    final cut = Cut(
      id: const CutId('cut'),
      name: 'Cut',
      layers: [layerWith('below', 0.5), layerWith('above', 1.0)],
      duration: 24,
      canvasSize: canvasSize,
    );
    final surfaces = {
      const LayerId('below'): below,
      const LayerId('above'): above,
    };
    LazyCanvasRasterRgb rasterFor() => LazyCanvasRasterRgb(
      cut: cut,
      frameIndex: 0,
      surfaceResolver: (layer, _) => surfaces[layer.id],
      extendBeyondCanvas: true,
    );

    void expectReferenceBytes(LazyCanvasRasterRgb raster) {
      expect((raster.originX, raster.originY), (-8, -8));
      expect((raster.width, raster.height), (24, 24));
      // World (-1, -1) is the pasteboard tile (-1, -1): red at half
      // opacity over paper → (255, 127, 127) by the integer source-over.
      expect(rgbAt(raster, 7, 7), [255, 127, 127]);
      // World (-2, -1): the layer above is opaque blue.
      expect(rgbAt(raster, 6, 7), [0, 0, 255]);
      // World (1, 2): green at alpha 128 × opacity 0.5.
      expect(rgbAt(raster, 9, 10), [191, 255, 191]);
      // Nowhere a tile exists: paper.
      expect(rgbAt(raster, 0, 0), [255, 255, 255]);
      expect(rgbAt(raster, 23, 23), [255, 255, 255]);
    }

    test('🚨the Dart compose reads tile -1 under a negative origin, not '
        'tile 0', () {
      QaNativeEngine.debugForceDartFallback = true;
      final raster = rasterFor();
      raster.ensureComposedAt(0);
      expectReferenceBytes(raster);
    });

    test('ensureComposedBatch without an engine composes the same bytes', () {
      QaNativeEngine.debugForceDartFallback = true;
      final raster = rasterFor();
      raster.ensureComposedBatch(Int32List.fromList([0, 7 * 24 + 7]));
      expectReferenceBytes(raster);
    });

    test('the native compose, per tile and batched, matches the Dart '
        'reference byte for byte', () {
      if (!available) {
        markTestSkipped(nativeEngineMissingSkipReason);
        return;
      }
      QaNativeEngine.debugForceDartFallback = true;
      final reference = rasterFor();
      reference.ensureComposedAt(0);
      QaNativeEngine.debugForceDartFallback = false;

      final perTile = rasterFor();
      expect(perTile.nativeHandles, isNotNull, reason: 'setup: engine');
      perTile.ensureComposedAt(0);
      expectReferenceBytes(perTile);
      expect(
        Uint8List.fromList(perTile.rgb),
        Uint8List.fromList(reference.rgb),
      );

      final batched = rasterFor();
      batched.ensureComposedBatch(Int32List.fromList([0]));
      expectReferenceBytes(batched);
      expect(
        Uint8List.fromList(batched.rgb),
        Uint8List.fromList(reference.rgb),
      );
    });
  });

  group('a surface tile straddling a compose-tile wall', () {
    // Canvas 300 → apron 300 → raster 900 = 4×4 compose tiles of 256.
    // The world tile (0, 0) sits at raster 300..556, across the wall at
    // 512: the clip has to split it between two compose tiles.
    const canvasSize = CanvasSize(width: 300, height: 300);
    int shade(int x, int y) => (x * 7 + y * 13) & 0xFF;
    BitmapSurface stripes() {
      Uint8List tileBytes(int worldLeft, int worldTop) {
        final bytes = Uint8List(256 * 256 * 4);
        for (var y = 0; y < 256; y += 1) {
          for (var x = 0; x < 256; x += 1) {
            final base = (y * 256 + x) * 4;
            bytes[base] = shade(worldLeft + x, worldTop + y);
            bytes[base + 1] = 255 - bytes[base];
            bytes[base + 2] = (worldLeft + x) & 1;
            bytes[base + 3] = 255;
          }
        }
        return bytes;
      }

      return BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 256,
        tiles: {
          TileCoord(x: 0, y: 0): BitmapTile(
            coord: TileCoord(x: 0, y: 0),
            size: 256,
            pixels: tileBytes(0, 0),
          ),
          TileCoord(x: -1, y: -1): BitmapTile(
            coord: TileCoord(x: -1, y: -1),
            size: 256,
            pixels: tileBytes(-256, -256),
          ),
        },
      );
    }

    final surface = stripes();
    final cut = Cut(
      id: const CutId('cut'),
      name: 'Cut',
      layers: [layerWith('ink', 1.0)],
      duration: 24,
      canvasSize: canvasSize,
    );
    LazyCanvasRasterRgb rasterFor() => LazyCanvasRasterRgb(
      cut: cut,
      frameIndex: 0,
      surfaceResolver: (_, _) => surface,
      extendBeyondCanvas: true,
    );
    void composeAll(LazyCanvasRasterRgb raster) {
      for (var y = 0; y < raster.height; y += 256) {
        for (var x = 0; x < raster.width; x += 256) {
          raster.ensureComposedAt(y * raster.width + x);
        }
      }
    }

    void expectClippedBytes(LazyCanvasRasterRgb raster) {
      expect((raster.originX, raster.originY), (-300, -300));
      // Either side of the wall at raster 512 (world 212), same tile.
      for (final (worldX, worldY) in [(211, 5), (212, 5), (255, 255), (0, 0)]) {
        expect(rgbAt(raster, worldX + 300, worldY + 300), [
          shade(worldX, worldY),
          255 - shade(worldX, worldY),
          worldX & 1,
        ], reason: 'world ($worldX, $worldY)');
      }
      // The pasteboard tile (-1, -1), raster 44..300.
      expect(rgbAt(raster, 44, 44), [
        shade(-256, -256),
        255 - shade(-256, -256),
        0,
      ]);
      expect(rgbAt(raster, 299, 299), [shade(-1, -1), 255 - shade(-1, -1), 1]);
      // No tile at world (256, 0): paper.
      expect(rgbAt(raster, 556, 300), [255, 255, 255]);
      expect(rgbAt(raster, 43, 44), [255, 255, 255]);
    }

    test('the Dart compose clips the tile at the wall and keeps its bytes', () {
      QaNativeEngine.debugForceDartFallback = true;
      final raster = rasterFor();
      composeAll(raster);
      expectClippedBytes(raster);
    });

    test('the native compose, per tile and batched, matches the Dart '
        'reference across the wall', () {
      if (!available) {
        markTestSkipped(nativeEngineMissingSkipReason);
        return;
      }
      QaNativeEngine.debugForceDartFallback = true;
      final reference = rasterFor();
      composeAll(reference);
      QaNativeEngine.debugForceDartFallback = false;

      final perTile = rasterFor();
      expect(perTile.nativeHandles, isNotNull, reason: 'setup: engine');
      composeAll(perTile);
      expectClippedBytes(perTile);
      expect(
        Uint8List.fromList(perTile.rgb),
        Uint8List.fromList(reference.rgb),
      );

      final batched = rasterFor();
      batched.ensureComposedBatch(
        Int32List.fromList([
          for (var y = 0; y < batched.height; y += 256)
            for (var x = 0; x < batched.width; x += 256) y * batched.width + x,
        ]),
      );
      expectClippedBytes(batched);
      expect(
        Uint8List.fromList(batched.rgb),
        Uint8List.fromList(reference.rgb),
      );
    });
  });
}
