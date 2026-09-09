import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';

/// 🚨★★★**AN ANCHORED CANVAS RESIZE RE-DECODED EVERY CEL THOUGH NOT A
/// BYTE MOVED.** A shift by a whole number of tiles renames a tile
/// ([BitmapTile.rebasedTo]) — same bytes, same picture, new object — and
/// this cache is `Expando`-keyed, so every decoded `ui.Image` was lost and
/// the whole cel decoded again (31 ms per cel at 128px, on a command that
/// runs over the whole cut).
///
/// The key is the tile's PIXELS now, which is what a picture is of. It
/// cannot go stale — a tile is immutable, so the same bytes are the same
/// picture forever — and it cannot dangle, because a rebase holds a
/// strong reference to its source, so the Expando's key outlives every
/// tile that could still ask under it.
void main() {
  BitmapTile inkedTile(TileCoord coord) => BitmapTile(
    coord: coord,
    size: 4,
    pixels: Uint8List(4 * 4 * 4)..[3] = 255,
  );

  /// ⚠️ONE test, not two, and the reason is the cache's own lifetime: a
  /// disposed cache's already-scheduled notify lands on the NEXT test's
  /// first frame and fails it, so a second `testWidgets` here reports its
  /// neighbour's cleanup rather than its own subject. The anti-vacuity
  /// half lives inside this one instead.
  testWidgets('a rebased tile finds the picture its source decoded — and a '
      'tile with its own pixels does not', (tester) async {
    await tester.runAsync(() async {
      final cache = BitmapTileImageCache();
      addTearDown(cache.dispose);
      final original = inkedTile(TileCoord(x: 0, y: 0));

      cache.ensureDecoded(original);
      for (var attempt = 0; attempt < 100; attempt += 1) {
        if (cache.imageFor(original) != null) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final decoded = cache.imageFor(original);
      expect(decoded, isNotNull, reason: 'setup: the source must have decoded');

      // What a whole-tile shift does.
      final moved = original.rebasedTo(TileCoord(x: 1, y: 0));
      expect(identical(moved, original), isFalse);

      expect(
        identical(cache.imageFor(moved), decoded),
        isTrue,
        reason: 'the same bytes are the same picture',
      );
      expect(cache.needsDecodeStart(moved), isFalse);

      // Anti-vacuity: identical BYTES, but its own buffer — a different
      // picture as far as this cache is concerned, because nothing keeps
      // the two in step. Without this the assertions above would also
      // pass for a cache that handed every tile the same image.
      final twin = inkedTile(TileCoord(x: 1, y: 0));
      expect(cache.imageFor(twin), isNull);
      expect(cache.needsDecodeStart(twin), isTrue);
    });
  });
}
