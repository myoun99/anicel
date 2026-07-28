import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/native_engine_path.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';

/// BB-N1 (ABI 22): the native stroke-blend tile kernel and the alpha-
/// bounds scan must be BYTE-IDENTICAL to their Dart references — every
/// blend mode, randomized destinations (existing, missing and partially
/// covered tiles) and stroke buffers (edge-biased alphas, uninked spans),
/// materialized through both paths and compared per tile. Skips (loudly)
/// when no locally built binary is found.
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

  void skipNoBinary() {
    markTestSkipped(
      'qa_engine.dll not built — run: cmake -S packages/qa_native/src -B '
      'build/native_standalone && cmake --build build/native_standalone '
      '--config Release',
    );
  }

  Uint8List randomPixels(Random random, int byteLength) {
    final bytes = Uint8List(byteLength);
    for (var i = 0; i < byteLength; i += 1) {
      // Edge-biased: plenty of 0s and 255s plus the full range — the
      // blend equations branch on both extremes.
      final roll = random.nextInt(10);
      bytes[i] = roll == 0
          ? 0
          : roll == 1
          ? 255
          : random.nextInt(256);
    }
    return bytes;
  }

  BitmapSurface randomSurface(Random random, CanvasSize canvasSize) {
    const tileSize = 32;
    final tiles = <TileCoord, BitmapTile>{};
    // A mix of present and MISSING tiles across the canvas (plus one off-
    // canvas pasteboard tile) — the kernel's da==0 fast path and the
    // zeroed staging both get real coverage.
    for (var tileY = -1; tileY * tileSize < canvasSize.height; tileY += 1) {
      for (var tileX = -1; tileX * tileSize < canvasSize.width; tileX += 1) {
        if (random.nextInt(3) == 0) {
          continue;
        }
        final coord = TileCoord(x: tileX, y: tileY);
        tiles[coord] = BitmapTile(
          coord: coord,
          size: tileSize,
          pixels: randomPixels(random, tileSize * tileSize * 4),
        );
      }
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: tiles,
    );
  }

  void expectSurfacesByteEqual(
    BitmapSurface actual,
    BitmapSurface reference,
    String label,
  ) {
    final tileSize = reference.tileSize;
    final empty = Uint8List(tileSize * tileSize * 4);
    final coords = <TileCoord>{...actual.tiles.keys, ...reference.tiles.keys};
    for (final coord in coords) {
      final actualBytes = actual.tileAt(coord)?.pixels ?? empty;
      final referenceBytes = reference.tileAt(coord)?.pixels ?? empty;
      expect(
        actualBytes,
        referenceBytes,
        reason: '$label: tile $coord diverged',
      );
    }
  }

  test('native stroke blend == Dart reference for EVERY mode (randomized)', () {
    if (!available) {
      skipNoBinary();
      return;
    }
    expect(QaNativeEngine.instance, isNotNull);

    const canvasSize = CanvasSize(width: 96, height: 64);
    final modes = [
      for (final mode in BrushBlendMode.values)
        if (mode != BrushBlendMode.color && mode != BrushBlendMode.erase) mode,
    ];
    for (final mode in modes) {
      // Per-mode deterministic seed so a failure names its mode exactly.
      final random = Random(526_000 + mode.index);
      for (var round = 0; round < 3; round += 1) {
        final surface = randomSurface(random, canvasSize);
        // Bounds cross tile boundaries and (round 2) the canvas edge onto
        // the pasteboard.
        final bounds = round == 2
            ? DirtyRegion(
                left: -17,
                top: -9,
                rightExclusive: 40,
                bottomExclusive: 30,
              )
            : DirtyRegion(
                left: 3 + random.nextInt(20),
                top: 2 + random.nextInt(12),
                rightExclusive: 50 + random.nextInt(40),
                bottomExclusive: 40 + random.nextInt(20),
              );
        final width = bounds.rightExclusive - bounds.left;
        final height = bounds.bottomExclusive - bounds.top;
        final stroke = randomPixels(random, width * height * 4);
        // Un-ink a horizontal band: alpha-0 pixels must copy the
        // destination through verbatim on both paths.
        for (var y = height ~/ 3; y < height ~/ 2; y += 1) {
          for (var x = 0; x < width; x += 1) {
            stroke[(y * width + x) * 4 + 3] = 0;
          }
        }

        QaNativeEngine.debugForceDartFallback = false;
        final nativeResult = compositeStrokePixelsOntoBitmapSurface(
          surface: surface,
          strokePixels: stroke,
          bounds: bounds,
          blendMode: mode,
        );
        QaNativeEngine.debugForceDartFallback = true;
        final referenceResult = compositeStrokePixelsOntoBitmapSurface(
          surface: surface,
          strokePixels: stroke,
          bounds: bounds,
          blendMode: mode,
        );
        QaNativeEngine.debugForceDartFallback = false;

        expectSurfacesByteEqual(
          nativeResult.surface,
          referenceResult.surface,
          '${mode.name} round $round',
        );
        // The native dirty set is the TRUE change set — it must be a
        // subset of the fallback's (which over-reports: its erase+rewrite
        // passes mark every bounds tile), and the strokes here do ink.
        expect(nativeResult.hasChanges, isTrue, reason: mode.name);
        for (final coord in nativeResult.dirtyTiles.coords) {
          expect(
            referenceResult.dirtyTiles.coords,
            contains(coord),
            reason: '${mode.name}: native marked $coord clean-path dirty',
          );
        }
      }
    }
  });

  test('native alpha bounds scan == Dart reference (randomized)', () {
    if (!available) {
      skipNoBinary();
      return;
    }
    expect(QaNativeEngine.instance, isNotNull);

    const canvasSize = CanvasSize(width: 96, height: 64);
    final random = Random(526_100);
    for (var round = 0; round < 12; round += 1) {
      const tileSize = 32;
      final tiles = <TileCoord, BitmapTile>{};
      final tileCount = random.nextInt(5);
      for (var i = 0; i < tileCount; i += 1) {
        final coord = TileCoord(
          x: random.nextInt(4) - 1,
          y: random.nextInt(3) - 1,
        );
        final pixels = Uint8List(tileSize * tileSize * 4);
        // Sparse ink, including exact tile-edge pixels on some rounds.
        final inkCount = random.nextInt(6);
        for (var k = 0; k < inkCount; k += 1) {
          final x = round.isEven ? random.nextInt(tileSize) : 0;
          final y = round % 3 == 0 ? tileSize - 1 : random.nextInt(tileSize);
          pixels[(y * tileSize + x) * 4 + 3] = 1 + random.nextInt(255);
        }
        tiles[coord] = BitmapTile(coord: coord, size: tileSize, pixels: pixels);
      }
      final surface = BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: tiles,
      );

      QaNativeEngine.debugForceDartFallback = false;
      final nativeBounds = bitmapSurfaceContentBounds(surface);
      QaNativeEngine.debugForceDartFallback = true;
      final referenceBounds = bitmapSurfaceContentBounds(surface);
      QaNativeEngine.debugForceDartFallback = false;

      expect(nativeBounds, referenceBounds, reason: 'round $round');
    }
  });
}
