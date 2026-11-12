@Tags(['benchmark'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/rgba_premultiply.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';

/// A MEASUREMENT (not a correctness test): what staging a tile's
/// premultiplied bytes costs ([BitmapTileImageCache.premultipliedTileUpload])
/// — the block asked, the engine library's premultiplied copy into it, the
/// block freed — beside what the app's law costs on the same tile lifted
/// into a list ([premultiplyRgbaInPlace], the road the upload took where no
/// C engine was loaded, till C ABI 83). A cel's worth of tiles, colder than
/// the cache, as a sheet's making reads them.
///
/// The two are one formula spelled twice (board card
/// `the-premultiply-is-spelled-twice-on-the-cpu`); this is the measure that
/// card reads.
///
/// Prints; asserts only that the work happened.
void main() {
  for (final size in [128, 256]) {
    test('premultiplying a cel of ${size}px tiles, one call a tile', () {
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

      ({int best, int p50}) timed(void Function(BitmapTile tile) each) {
        int pass() {
          final watch = Stopwatch()..start();
          tiles.forEach(each);
          return watch.elapsedMicroseconds;
        }

        pass();
        final all = [for (var round = 0; round < 9; round += 1) pass()]
          ..sort();
        return (best: all.first, p50: all[all.length ~/ 2]);
      }

      String each(int micros) => (micros / tiles.length).toStringAsFixed(1);

      final staged = timed(
        (tile) => BitmapTileImageCache.premultipliedTileUpload(tile).free(),
      );
      final lifted = timed((tile) => premultiplyRgbaInPlace(tile.pixels));
      // ignore: avoid_print
      print(
        'premultiply ${tiles.length} tiles of ${size}px: staged best '
        '${each(staged.best)} us/tile, p50 ${each(staged.p50)} us/tile · '
        'the law on a lifted list best ${each(lifted.best)} us/tile, p50 '
        '${each(lifted.p50)} us/tile',
      );
      expect(staged.best, greaterThan(0));
      expect(lifted.best, greaterThan(0));
    });
  }
}
