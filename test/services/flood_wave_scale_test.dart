import 'dart:io';


import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';

/// NOT tagged `benchmark`: the tag skips the WHOLE file, and the
/// assertions here (the flooded region's exact bounds, the mask length,
/// the gap-close region's corner) are geometry the clock cannot move —
/// they are the only 8K-scale correctness pins the wave flood has. The
/// times it prints are indicative under a suite run; read them from a
/// deliberate lone run instead.
///
/// R22-E3 wave-flood scaling bench: floods a fully-composed 8000x8000
/// raster (the worst single-call case — every compose tile is in the
/// wave) and prints wall times. Run twice to see thread scaling:
///   flutter test ... (full pool)  vs  QA_ENGINE_THREADS=2 ... (1 worker)
/// Assertions pin the RESULT (full-canvas bounds), not the clock.
void main() {
  test('8K fully-composed flood wall time (prints; pool-scaled)', () {
    final dllPath =
        '${Directory.current.path}/build/native_standalone/Release/qa_engine.dll';
    if (!File(dllPath).existsSync()) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    final engine = QaNativeEngine.instance;
    expect(engine, isNotNull);

    const width = 8000;
    const height = 8000;
    final handles = engine!.acquireFloodRaster(
      width: width,
      height: height,
      composeTileSize: 256,
    );
    engine.fillPaperRect(
      handles: handles,
      left: 0,
      top: 0,
      rightExclusive: width,
      bottomExclusive: height,
      paperR: 250,
      paperG: 250,
      paperB: 250,
    );
    // A border ring so the flood has real walls.
    final rgb = handles.rgbView;
    for (var x = 0; x < width; x += 1) {
      for (final y in [0, height - 1]) {
        final base = (y * width + x) * 4;
        rgb[base] = 0;
        rgb[base + 1] = 0;
        rgb[base + 2] = 0;
      }
    }
    for (var y = 0; y < height; y += 1) {
      for (final x in [0, width - 1]) {
        final base = (y * width + x) * 4;
        rgb[base] = 0;
        rgb[base + 1] = 0;
        rgb[base + 2] = 0;
      }
    }
    handles.composedView.fillRange(0, handles.composedView.length, 1);

    final threads = Platform.environment['QA_ENGINE_THREADS'] ?? 'default';
    for (var run = 0; run < 3; run += 1) {
      final watch = Stopwatch()..start();
      final result = engine.floodFillRun(
        handles: handles,
        seedX: width ~/ 2,
        seedY: height ~/ 2,
        seedR: 250,
        seedG: 250,
        seedB: 250,
        tolerance: 32,
        ensureComposed: (_) {},
      )!;
      watch.stop();
      expect(result.minX, 1);
      expect(result.maxX, width - 2);
      expect(result.minY, 1);
      expect(result.maxY, height - 2);
      // ignore: avoid_print
      print(
        'WAVE8K threads=$threads run#$run '
        '${watch.elapsedMilliseconds}ms',
      );
    }

    // R24-A1: the finish passes (expand + anti-alias over the 64MP
    // mask) band-parallelized — run against a full-canvas mask.
    for (var run = 0; run < 3; run += 1) {
      final watch = Stopwatch()..start();
      final mask = engine.finishFillMask(
        canvasWidth: width,
        cropLeft: 0,
        cropTop: 0,
        regionWidth: width,
        regionHeight: height,
        expandPx: 1,
        antiAlias: true,
      );
      watch.stop();
      expect(mask.length, width * height);
      // ignore: avoid_print
      print(
        'FINISH8K threads=$threads run#$run '
        '${watch.elapsedMilliseconds}ms',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('8K GAP-CLOSE fill wall time (prints; R24-A2 measurement)', () {
    final dllPath =
        '${Directory.current.path}/build/native_standalone/Release/qa_engine.dll';
    if (!File(dllPath).existsSync()) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    final engine = QaNativeEngine.instance;
    expect(engine, isNotNull);

    const width = 8000;
    const height = 8000;
    final handles = engine!.acquireFloodRaster(
      width: width,
      height: height,
      composeTileSize: 256,
    );
    engine.fillPaperRect(
      handles: handles,
      left: 0,
      top: 0,
      rightExclusive: width,
      bottomExclusive: height,
      paperR: 250,
      paperG: 250,
      paperB: 250,
    );
    // A border ring WITH GAPS: forces the real gap-close pipeline
    // (erode -> flood -> regrow), not the degenerate path.
    final rgb = handles.rgbView;
    void ink(int x, int y) {
      final base = (y * width + x) * 4;
      rgb[base] = 0;
      rgb[base + 1] = 0;
      rgb[base + 2] = 0;
    }

    for (var x = 0; x < width; x += 1) {
      if (x % 977 < 3) {
        continue; // Small gaps along the walls.
      }
      ink(x, 1000);
      ink(x, height - 1000);
    }
    for (var y = 1000; y < height - 1000; y += 1) {
      if (y % 977 < 3) {
        continue;
      }
      ink(1000, y);
      ink(width - 1000, y);
    }
    handles.composedView.fillRange(0, handles.composedView.length, 1);

    final threads = Platform.environment['QA_ENGINE_THREADS'] ?? 'default';
    for (var run = 0; run < 2; run += 1) {
      final watch = Stopwatch()..start();
      final region = floodFillRegion(
        rgb: rgb,
        width: width,
        height: height,
        seedX: width ~/ 2,
        seedY: height ~/ 2,
        options: const FloodFillOptions(tolerance: 32, gapClosePx: 4),
        ensureComposed: (_) {},
        nativeHandles: handles,
      );
      watch.stop();
      expect(region, isNotNull);
      // Gap-close must have BLOCKED the leaks: the region stays inside
      // the ring despite the wall gaps.
      expect(region!.left, greaterThanOrEqualTo(900));
      expect(region.top, greaterThanOrEqualTo(900));
      // ignore: avoid_print
      print(
        'GAPCLOSE8K threads=$threads gap=4 run#$run '
        '${watch.elapsedMilliseconds}ms',
      );
    }

    // Reference point: the same fill WITHOUT gap close (leaks through).
    final watch = Stopwatch()..start();
    floodFillRegion(
      rgb: rgb,
      width: width,
      height: height,
      seedX: width ~/ 2,
      seedY: height ~/ 2,
      options: const FloodFillOptions(tolerance: 32),
      ensureComposed: (_) {},
      nativeHandles: handles,
    );
    watch.stop();
    // ignore: avoid_print
    print('GAPCLOSE8K gap=0 reference ${watch.elapsedMilliseconds}ms');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
