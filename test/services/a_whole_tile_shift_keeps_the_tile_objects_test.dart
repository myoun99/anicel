import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';

/// 🚨★★★**AN ANCHORED RESIZE MUST NOT REBUILD THE PIXELS IT IS ONLY
/// RENAMING.** A shift by a whole number of tiles moves nothing WITHIN a
/// tile — it moves the tile's map key. It used to allocate a fresh native
/// buffer and memcpy every tile (64 KB each at 128px, over every cel of
/// the cut), and because the decoded-image cache is keyed by the tile
/// OBJECT, the new objects also lost every `ui.Image` and the whole cel
/// decoded again (31 ms per cel).
///
/// ⚠️**THIS PIN REPLACES TWO THAT DIED WITH THEIR SUBJECT** (2026-09-09):
/// `a_rebase_keeps_the_decoded_picture_test` and
/// `the_entry_and_its_finalizer_hang_together_test`, which pinned a
/// buffer-sharing `rebasedTo` and the Expando-key normalisation it forced.
/// Both are gone because a tile no longer carries a coordinate, so a shift
/// keeps the very same object and there is nothing left to share or
/// normalise. This asks the property the user can see instead of the
/// mechanism: the objects survive, so their pictures do.
void main() {
  const tileSize = 8;
  const canvasSize = CanvasSize(width: 32, height: 16);

  BitmapTile inked() => BitmapTile(
    size: tileSize,
    pixels: Uint8List(BitmapTile.bytesFor(tileSize))..[3] = 255,
  );

  test('🚨a whole-tile shift moves the SAME tile objects', () {
    final before = BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: {
        TileCoord(x: 0, y: 0): inked(),
        TileCoord(x: 1, y: 0): inked(),
      },
    );

    final after = translateBitmapSurface(
      before,
      dx: tileSize,
      dy: 0,
      canvasSize: canvasSize,
    );

    expect(
      identical(after.tileAt(TileCoord(x: 1, y: 0)), before.tileAt(TileCoord(x: 0, y: 0))),
      isTrue,
      reason: 'the tile was renamed, not rebuilt',
    );
    expect(
      identical(after.tileAt(TileCoord(x: 2, y: 0)), before.tileAt(TileCoord(x: 1, y: 0))),
      isTrue,
    );
  });

  test('a FRACTIONAL shift does rebuild — the pixels really move', () {
    final before = BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: {TileCoord(x: 0, y: 0): inked()},
    );

    final after = translateBitmapSurface(
      before,
      dx: 3,
      dy: 0,
      canvasSize: canvasSize,
    );

    // Anti-vacuity: if the shift branch above had simply returned its
    // input, this case would pass too.
    expect(
      identical(after.tileAt(TileCoord(x: 0, y: 0)), before.tileAt(TileCoord(x: 0, y: 0))),
      isFalse,
    );
  });
}
