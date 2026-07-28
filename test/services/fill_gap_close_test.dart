import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';

/// R20-C1 close-gap fill: line-art gaps narrower than ~2× the gap radius
/// stop leaks; the region still grows back to the REAL barriers. The C
/// kernel must reproduce the Dart reference pipeline exactly.
void main() {
  final dllPath =
      '${Directory.current.path}\\build\\native_standalone\\Release\\qa_engine.dll';
  final dllAvailable = File(dllPath).existsSync();

  setUp(() {
    QaNativeEngine.debugResetForTests();
    QaNativeEngine.debugForceDartFallback = true;
  });

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  /// A white canvas with a black box outline that has a [gap]-px hole in
  /// its right wall. Seed inside the box.
  Uint8List boxWithGap({
    required int width,
    required int height,
    required int gap,
  }) {
    final rgb = Uint8List(width * height * 4);
    rgb.fillRange(0, rgb.length, 255);
    void black(int x, int y) {
      final base = (y * width + x) * 4;
      rgb[base] = 0;
      rgb[base + 1] = 0;
      rgb[base + 2] = 0;
    }

    const boxLeft = 8, boxTop = 8;
    final boxRight = width - 9, boxBottom = height - 9;
    for (var x = boxLeft; x <= boxRight; x += 1) {
      black(x, boxTop);
      black(x, boxBottom);
    }
    final gapStart = (boxTop + boxBottom - gap) ~/ 2;
    for (var y = boxTop; y <= boxBottom; y += 1) {
      black(boxLeft, y);
      if (y < gapStart || y >= gapStart + gap) {
        black(boxRight, y);
      }
    }
    return rgb;
  }

  FloodFillRegion? fill(
    Uint8List rgb, {
    required int width,
    required int height,
    required int gapClosePx,
  }) {
    return floodFillRegion(
      rgb: rgb,
      width: width,
      height: height,
      seedX: width ~/ 2,
      seedY: height ~/ 2,
      options: FloodFillOptions(
        tolerance: 32,
        expandPx: 0,
        antiAlias: false,
        gapClosePx: gapClosePx,
      ),
    );
  }

  bool coversOutside(FloodFillRegion region, int width, int height) {
    // Any coverage in the top-left canvas corner = the fill leaked out.
    for (var y = 0; y < 4; y += 1) {
      for (var x = 0; x < 4; x += 1) {
        if (x >= region.left &&
            x < region.left + region.width &&
            y >= region.top &&
            y < region.top + region.height &&
            region.mask[(y - region.top) * region.width + (x - region.left)] !=
                0) {
          return true;
        }
      }
    }
    return false;
  }

  test('gap close BLOCKS a leak through a hole narrower than ~2×radius; '
      'plain fill leaks', () {
    const width = 64, height = 64;
    final rgb = boxWithGap(width: width, height: height, gap: 5);

    final leaked = fill(rgb, width: width, height: height, gapClosePx: 0)!;
    expect(
      coversOutside(leaked, width, height),
      isTrue,
      reason: 'without gap close the fill escapes through the hole',
    );

    final closed = fill(rgb, width: width, height: height, gapClosePx: 4)!;
    expect(
      coversOutside(closed, width, height),
      isFalse,
      reason: 'gap close 4px must contain a 5px hole',
    );

    // The contained region still reaches the REAL walls (grow-back):
    // the pixel just inside the left wall is covered.
    final xInside = 9, yInside = height ~/ 2;
    expect(
      closed.mask[(yInside - closed.top) * closed.width +
          (xInside - closed.left)],
      isNot(0),
      reason: 'after grow-back the fill touches the real barrier again',
    );
  });

  test('a seed in a corridor narrower than the gap radius still fills '
      '(deterministic gap halving)', () {
    const width = 32, height = 32;
    final rgb = Uint8List(width * height * 4);
    rgb.fillRange(0, rgb.length, 255);
    // Two horizontal walls 3px apart around the seed row.
    for (var x = 0; x < width; x += 1) {
      for (final y in [14, 18]) {
        final base = (y * width + x) * 4;
        rgb[base] = 0;
        rgb[base + 1] = 0;
        rgb[base + 2] = 0;
      }
    }
    final region = floodFillRegion(
      rgb: rgb,
      width: width,
      height: height,
      seedX: 16,
      seedY: 16,
      options: const FloodFillOptions(
        tolerance: 32,
        expandPx: 0,
        antiAlias: false,
        gapClosePx: 8,
      ),
    );
    expect(region, isNotNull, reason: 'erosion must not swallow the seed');
    expect(
      region!.mask[(16 - region.top) * region.width + (16 - region.left)],
      isNot(0),
    );
  });

  test('C kernel == Dart reference, mask for mask (randomized walls)', () {
    if (!dllAvailable) {
      markTestSkipped(
        'qa_engine.dll not built — run: cmake -S packages/qa_native/src -B '
        'build/native_standalone && cmake --build build/native_standalone '
        '--config Release',
      );
      return;
    }
    final random = Random(20260714);
    for (var round = 0; round < 8; round += 1) {
      final width = 48 + random.nextInt(40);
      final height = 48 + random.nextInt(40);
      final rgb = Uint8List(width * height * 4);
      rgb.fillRange(0, rgb.length, 255);
      // Random walls with random holes.
      for (var wall = 0; wall < 6; wall += 1) {
        final vertical = random.nextBool();
        final position =
            6 + random.nextInt(vertical ? width - 12 : height - 12);
        final holeStart = random.nextInt(vertical ? height : width);
        final holeLength = 1 + random.nextInt(8);
        final limit = vertical ? height : width;
        for (var along = 0; along < limit; along += 1) {
          if (along >= holeStart && along < holeStart + holeLength) {
            continue;
          }
          final x = vertical ? position : along;
          final y = vertical ? along : position;
          final base = (y * width + x) * 4;
          rgb[base] = 0;
          rgb[base + 1] = 0;
          rgb[base + 2] = 0;
        }
      }
      final gapClosePx = 1 + random.nextInt(8);
      final seedX = width ~/ 2;
      final seedY = height ~/ 2;
      final options = FloodFillOptions(
        tolerance: 32,
        expandPx: random.nextInt(3),
        antiAlias: random.nextBool(),
        gapClosePx: gapClosePx,
      );

      // Dart reference.
      QaNativeEngine.debugResetForTests();
      QaNativeEngine.debugForceDartFallback = true;
      final reference = floodFillRegion(
        rgb: rgb,
        width: width,
        height: height,
        seedX: seedX,
        seedY: seedY,
        options: options,
      );

      // Native path: stage the SAME rgb into the engine's flood raster.
      QaNativeEngine.debugResetForTests();
      debugQaEngineLibraryPathOverride = dllPath;
      QaNativeEngine.debugForceDartFallback = false;
      final engine = QaNativeEngine.instance;
      expect(engine, isNotNull, reason: 'the locally built engine must load');
      final handles = engine!.acquireFloodRaster(
        width: width,
        height: height,
        composeTileSize: 256,
      );
      handles.rgbView.setAll(0, rgb);
      handles.composedView.fillRange(0, handles.composedView.length, 1);
      final native = floodFillRegion(
        rgb: handles.rgbView,
        width: width,
        height: height,
        seedX: seedX,
        seedY: seedY,
        options: options,
        ensureComposed: (_) {},
        nativeHandles: handles,
      );

      expect(native == null, reference == null, reason: 'round $round');
      if (reference == null || native == null) {
        continue;
      }
      expect(native.left, reference.left, reason: 'round $round left');
      expect(native.top, reference.top, reason: 'round $round top');
      expect(native.width, reference.width, reason: 'round $round width');
      expect(native.height, reference.height, reason: 'round $round height');
      expect(native.mask, reference.mask, reason: 'round $round mask bytes');
    }
  });
}
