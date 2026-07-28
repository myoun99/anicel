@Tags(['benchmark'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';

import '../../helpers/native_engine_path.dart';

/// What a DECODE START costs, and what the Dart-heap copy used to add.
///
/// Starting a tile's decode premultiplies its bytes for the raw rgba8888
/// upload, on the UI thread, up to [BitmapTileImageCache.decodeStartBudget]
/// times per paint — 32 x 256KB on a 256px grid, the largest
/// single-threaded pixel job left in a frame.
///
/// The fused C kernel writes premultiplied bytes into a per-call native
/// buffer, and the decoder reads that buffer directly
/// ([PremultipliedTileUpload]). It used to be lifted into a Dart-heap
/// list first, and that copy dominated: the A/B below adds it back on the
/// same inputs in the same run, which is the only comparison worth
/// trusting (verify-discipline).
///
/// Prints; asserts only that the work happened.
void main() {
  final dllPath = nativeEngineLibraryPathOrNull();

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  BitmapTile tileOf(int size) {
    final pixels = Uint8List(size * size * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = i % 251;
      pixels[i + 1] = i % 241;
      pixels[i + 2] = i % 239;
      // Mixed alpha: 255 and 0 take the early-outs, the rest does the math.
      pixels[i + 3] = (i ~/ 4) % 3 == 0 ? 255 : ((i ~/ 4) % 3 == 1 ? 0 : 128);
    }
    return BitmapTile(coord: TileCoord(x: 0, y: 0), size: size, pixels: pixels);
  }

  double microsPer(int rounds, void Function() body) {
    for (var i = 0; i < rounds ~/ 4; i += 1) {
      body(); // warmup, discarded
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < rounds; i += 1) {
      body();
    }
    watch.stop();
    return watch.elapsedMicroseconds / rounds;
  }

  test('decode start: the upload handoff vs lifting it into the Dart heap', () {
    if (dllPath == null) {
      markTestSkipped(nativeEngineMissingSkipReason);
      return;
    }
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
    expect(QaNativeEngine.instance, isNotNull);

    // ignore: avoid_print
    print('--- decode start (debug build; the A/B ratio, not the absolutes)');
    const rounds = 400;
    for (final size in const [64, 128, 256]) {
      final tile = tileOf(size);

      // SHIPPED: the decoder reads the kernel's own buffer.
      final handoff = microsPer(rounds, () {
        BitmapTileImageCache.premultipliedTileUpload(tile).free();
      });

      // The copy that used to sit in front of it.
      final withVmCopy = microsPer(rounds, () {
        final upload = BitmapTileImageCache.premultipliedTileUpload(tile);
        Uint8List.fromList(upload.view);
        upload.free();
      });

      // ignore: avoid_print
      print(
        '${size}px tile (${(size * size * 4 / 1024).round()}KB): '
        'handoff ${handoff.toStringAsFixed(1)}us | '
        'with the VM copy ${withVmCopy.toStringAsFixed(1)}us '
        '(${(withVmCopy / handoff).toStringAsFixed(1)}x)',
      );
      expect(handoff, greaterThan(0));
      expect(withVmCopy, greaterThan(0));
    }

    // A full paint's worth at the production budget and tile size.
    final tile = tileOf(256);
    final perStart = microsPer(200, () {
      BitmapTileImageCache.premultipliedTileUpload(tile).free();
    });
    // ignore: avoid_print
    print(
      'one paint at the budget '
      '(${BitmapTileImageCache.decodeStartBudget} starts x 256px): '
      '${(perStart * BitmapTileImageCache.decodeStartBudget / 1000).toStringAsFixed(2)}ms',
    );
  });
}
