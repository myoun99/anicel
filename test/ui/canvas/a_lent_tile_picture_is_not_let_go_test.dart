import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/canvas/tile_predecessors.dart';

/// 🚨A PICTURE THE SCREEN MAY STILL BORROW IS NOT LET GO
/// (undo-held-tile-pictures, stage 2, 2026-09-15).
///
/// Stage 2 lets the pictures of undo entries deeper than the next step go.
/// Nothing SHOWS those tiles — but a tile whose own picture is not ready
/// yet is drawn through ANOTHER tile's picture, by two doors: the stand-in
/// composed from its predecessor, and the last picture decoded at its
/// coordinate. [BitmapTileImageCache.releasePicture] refuses both.
///
/// ⚠️Pinned at the door, not on a canvas: a widget walk cannot reach these
/// without real time — no decode lands and nothing schedules the paint that
/// would borrow — so its frame reads the same with the release on and off
/// (measured on `undo_into_the_room_is_whole_test`'s walk).
void main() {
  final coord = TileCoord(x: 2, y: 3);
  var made = 0;

  /// A tile of its own: a distinct object with distinct bytes.
  BitmapTile tile() {
    made += 1;
    final pixels = Uint8List(4 * 4 * BitmapTile.bytesPerPixel)
      ..fillRange(0, 4, made);
    return BitmapTile(size: 4, pixels: pixels);
  }

  ui.Image picture() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 4, 4),
      Paint()..color = const Color(0xFF3366CC),
    );
    final recorded = recorder.endRecording();
    final image = recorded.toImageSync(4, 4);
    recorded.dispose();
    return image;
  }

  /// [tile]'s picture landed, filed under [scope] — nowhere by default.
  void land(BitmapTileImageCache cache, BitmapTile tile, {Object? scope}) =>
      cache.adoptDecoded(
        (coord: coord, tile: tile),
        picture(),
        staleScope: scope ?? BitmapTileImageCache.unfiled,
      );

  testWidgets('control: a picture nobody borrows goes, counted out, and is '
      'made again when asked', (tester) async {
    final cache = BitmapTileImageCache();
    final lone = tile();
    land(cache, lone);
    final held = BitmapTileImageCache.liveImageBytes;
    cache.releasePicture(coord, lone);
    expect(cache.imageFor(lone), isNull);
    expect(BitmapTileImageCache.liveImageBytes, held - 4 * 4 * 4);
    expect(cache.needsDecodeStart(lone), isTrue);
  });

  testWidgets('a stand-in nothing shows goes too — the one a confirm composes '
      'for a tile whose truth never lands', (tester) async {
    final cache = BitmapTileImageCache();
    final lone = tile();
    cache.putProvisional(lone, picture());
    final held = BitmapTileImageCache.liveImageBytes;
    // ⛔Mutation: the release lets go of truth only → the stand-in stays for
    // as long as the tile lives.
    cache.releasePicture(coord, lone);
    expect(cache.hasProvisional(lone), isFalse);
    expect(BitmapTileImageCache.liveImageBytes, held - 4 * 4 * 4);
  });

  testWidgets('a stand-in a tile not ready yet composes from stays', (
    tester,
  ) async {
    final cache = BitmapTileImageCache();
    final before = tile();
    final after = tile();
    cache.putProvisional(before, picture());
    TilePredecessors.instance.note(after, before);
    cache.releasePicture(coord, before);
    expect(
      cache.hasProvisional(before),
      isTrue,
      reason: 'a successor composes from a stand-in as readily as from truth',
    );
  });

  testWidgets('🚨a picture a tile not ready yet composes from stays', (
    tester,
  ) async {
    final cache = BitmapTileImageCache();
    final before = tile();
    final after = tile();
    land(cache, before);
    TilePredecessors.instance.note(after, before);
    // ⛔Mutation: the lending check gone → the picture goes, and `after`
    // has nothing left to compose its first frame from.
    cache.releasePicture(coord, before);
    expect(cache.imageFor(before), isNotNull);
  });

  testWidgets('a record that was dropped lends nothing', (tester) async {
    final cache = BitmapTileImageCache();
    final before = tile();
    final after = tile();
    land(cache, before);
    TilePredecessors.instance.note(after, before);
    TilePredecessors.instance.drop(after);
    // ⛔Mutation: a dropped record still counted → kept for as long as
    // `after` lives.
    cache.releasePicture(coord, before);
    expect(cache.imageFor(before), isNull);
  });

  testWidgets('a tile that already has a picture borrows nothing, even while '
      'its record stands', (tester) async {
    final cache = BitmapTileImageCache();
    final before = tile();
    final after = tile();
    land(cache, before);
    land(cache, after);
    // Noted AFTER its picture landed, so nothing will drop this record:
    // only a landing picture or a composed stand-in does.
    TilePredecessors.instance.note(after, before);
    // ⛔Mutation: a successor with a picture still counted → kept.
    cache.releasePicture(coord, before);
    expect(cache.imageFor(before), isNull);
  });

  testWidgets('🚨a picture filed as the latest at its coordinate stays, until '
      'a newer one is filed there', (tester) async {
    final cache = BitmapTileImageCache();
    final scope = Object();
    final before = tile();
    final after = tile();
    land(cache, before, scope: scope);
    // ⛔Mutation: the filed check gone → the fallback's picture goes.
    cache.releasePicture(coord, before);
    expect(cache.imageFor(before), isNotNull);
    expect(cache.latestImageForCoord(coord, scope: scope), isNotNull);
    land(cache, after, scope: scope);
    cache.releasePicture(coord, before);
    expect(
      cache.imageFor(before),
      isNull,
      reason: 'the fallback lends the newer picture now',
    );
  });
}
