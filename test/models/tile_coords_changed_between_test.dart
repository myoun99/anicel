import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';

/// 유저 2026-09-10 (F-68): 「기존보다 축소시 축소 바깥의 기존그림영역의 그림이
/// 1프레임 생겼다가 사라지는듯. 심지어 안사라질때도있음.」
///
/// The confirm asked `landing.tileRange(...)` — where the pixels went — and
/// seeded a picture of themselves only for those coordinates. The ones the
/// transform EMPTIED got none, so the painter fell through to the tile
/// cache's last-decoded fallback and drew the artwork that had just been
/// erased. This file pins the question that replaced it.
void main() {
  const canvas = CanvasSize(width: 256, height: 256);
  const size = 64;

  BitmapTile tileOf(int fill) => BitmapTile(
    size: size,
    pixels: Uint8List(size * size * 4)..fillRange(0, size * size * 4, fill),
  );

  BitmapSurface surfaceOf(Map<TileCoord, BitmapTile> tiles) =>
      BitmapSurface(canvasSize: canvas, tileSize: size, tiles: tiles);

  final source = TileCoord(x: 0, y: 0);
  final shared = TileCoord(x: 1, y: 0);
  final destination = TileCoord(x: 2, y: 0);

  test('🐛the coordinate a shrink EMPTIED is named, and the old range did '
      'not name it', () {
    // The shape of 유저's case: artwork lifted from tile 0 lands, smaller,
    // in tile 2. Tile 1 is untouched scenery.
    final untouched = tileOf(40);
    final before = surfaceOf({
      source: tileOf(200),
      shared: untouched,
    });
    final after = surfaceOf({
      shared: untouched,
      destination: tileOf(200),
    });

    expect(
      tileCoordsChangedBetween(before, after),
      unorderedEquals(<TileCoord>[source, destination]),
    );

    // ⛔AND THE PROXY IT REPLACED, measured beside it — otherwise this test
    // only says the new answer is A answer, not that it is a DIFFERENT one.
    // The landing rect covers tile 2 and nothing else.
    final landing = DirtyRegion(
      left: 128,
      top: 0,
      rightExclusive: 192,
      bottomExclusive: 64,
    );
    final byLanding = tileCoordsIn(landing.tileRange(tileSize: size));
    expect(byLanding, contains(destination));
    expect(
      byLanding,
      isNot(contains(source)),
      reason: 'this is the miss — the vacated tile was never asked about',
    );
  });

  test('an ENLARGING landing covered its own source, which is why nobody '
      'saw this', () {
    // Same lift, but the destination now includes the source coordinate.
    // The old range happened to name it, so the fallback never showed.
    final before = surfaceOf({source: tileOf(200)});
    final after = surfaceOf({source: tileOf(90), destination: tileOf(90)});

    final landing = DirtyRegion(
      left: 0,
      top: 0,
      rightExclusive: 192,
      bottomExclusive: 64,
    );
    expect(
      tileCoordsIn(landing.tileRange(tileSize: size)),
      contains(source),
      reason: 'the enlarged landing swept the vacated tile up by accident',
    );
    expect(
      tileCoordsChangedBetween(before, after),
      unorderedEquals(<TileCoord>[source, destination]),
    );
  });

  test('an untouched coordinate is not named — tiles are shared by identity',
      () {
    final tile = tileOf(11);
    final before = surfaceOf({source: tile, shared: tileOf(22)});
    final after = surfaceOf({source: tile, shared: tileOf(22)});

    expect(
      tileCoordsChangedBetween(before, after),
      <TileCoord>[shared],
      reason: 'the shared tile is the SAME object; the other is an equal '
          'copy, and an equal copy is a new picture to decode',
    );
  });

  test('a surface compared with itself changed nothing', () {
    final surface = surfaceOf({source: tileOf(7), shared: tileOf(8)});
    expect(tileCoordsChangedBetween(surface, surface), isEmpty);
  });

  test('absence counts, in both directions', () {
    final tile = tileOf(5);
    expect(
      tileCoordsChangedBetween(surfaceOf({source: tile}), surfaceOf({})),
      <TileCoord>[source],
      reason: 'a tile that went away changed that coordinate',
    );
    expect(
      tileCoordsChangedBetween(surfaceOf({}), surfaceOf({source: tile})),
      <TileCoord>[source],
      reason: 'and so did one that arrived',
    );
  });
}
