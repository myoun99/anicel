@Tags(['benchmark'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';

import '../helpers/native_engine_path.dart';

/// A MEASUREMENT (not a correctness test): what a tile's premultiply costs
/// on the engine the suite resolves — run it against two binaries
/// (`QA_ENGINE_PATH`) to compare their kernels. A cel's worth of tiles,
/// colder than the cache, as playback's making reads them.
///
/// Prints; asserts only that the work happened.
void main() {
  final dllPath = nativeEngineLibraryPathOrNull();

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  test('premultiplying a cel of 256px tiles, one call a tile', () {
    if (dllPath == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    final native = QaNativeEngine.instance!;

    const size = 256;
    // A drawn cel's tiles: clear, solid and edge pixels mixed, so every
    // alpha the formula meets is met.
    final tiles = [
      for (var t = 0; t < 128; t += 1)
        BitmapTile(
          size: size,
          pixels: Uint8List.fromList([
            for (var p = 0; p < size * size; p += 1) ...[
              (p * 7 + t) & 0xFF,
              (p * 13) & 0xFF,
              (p * 3 + t * 5) & 0xFF,
              switch ((p + t) % 5) {
                0 || 1 => 0,
                2 => 255,
                _ => (p * 11) & 0xFF,
              },
            ],
          ]),
        ),
    ];

    int pass() {
      final watch = Stopwatch()..start();
      for (final tile in tiles) {
        tile
            .readPixels(
              (pointer, _) =>
                  native.premultipliedTileScratch(pointer, size * size),
            )
            .free();
      }
      return watch.elapsedMicroseconds;
    }

    pass();
    var best = 1 << 62;
    final all = <int>[];
    for (var round = 0; round < 9; round += 1) {
      final micros = pass();
      all.add(micros);
      best = micros < best ? micros : best;
    }
    all.sort();
    // ignore: avoid_print
    print(
      'premultiply ${tiles.length} tiles of ${size}px on $dllPath: '
      'best ${(best / tiles.length).toStringAsFixed(1)} us/tile, '
      'p50 ${(all[all.length ~/ 2] / tiles.length).toStringAsFixed(1)} '
      'us/tile',
    );
    expect(best, greaterThan(0));
  });
}
