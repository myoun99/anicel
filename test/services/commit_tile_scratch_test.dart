import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/commit_tile_scratch.dart';

/// The commit scratch (round 8 of the audit): stage a tile's bytes to blend
/// into, then finish the changed ones as tiles — the promises it keeps for
/// the commit off the engine's grid.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const tileSize = 4;
  const byteLength = tileSize * tileSize * 4;
  final present = TileCoord(x: 1, y: 1);
  final missing = TileCoord(x: 0, y: 0);

  BitmapSurface surfaceWithTile(TileCoord coord, int fill) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      coord: BitmapTile(
        size: tileSize,
        pixels: Uint8List(byteLength)..fillRange(0, byteLength, fill),
      ),
    },
  );

  test('a MISSING tile stages zeroed bytes', () {
    final scratch = CommitTileScratch(surfaceWithTile(present, 0x7F));
    expect(scratch.bufferFor(missing), everyElement(0));
  });

  test('an existing tile stages its bytes as a COPY the tile does not '
      'see', () {
    final surface = surfaceWithTile(present, 0x7F);
    final scratch = CommitTileScratch(surface);
    final buffer = scratch.bufferFor(present);
    expect(buffer, everyElement(0x7F));
    buffer[0] = 0x11;
    expect(
      surface.tileAt(present)!.pixels[0],
      0x7F,
      reason: 'tiles are immutable; the scratch is the mutable copy',
    );
  });

  test('the same coordinate stages ONCE: a second dab sees the first '
      'dab\'s bytes', () {
    final scratch = CommitTileScratch(surfaceWithTile(present, 0));
    scratch.bufferFor(present)[5] = 0xAB;
    expect(scratch.bufferFor(present)[5], 0xAB);
  });

  test('finish hands back a tile carrying the blended bytes at the '
      'coordinate', () {
    final scratch = CommitTileScratch(surfaceWithTile(present, 0));
    final buffer = scratch.bufferFor(present);
    buffer.fillRange(0, byteLength, 0xC3);
    scratch.bufferFor(missing);
    final tile = scratch.finish(present);

    expect(tile.size, tileSize);
    expect(tile.pixels, everyElement(0xC3));
  });

  // ABI 40: a dab piles up on the tile's 16-bit plane (`StrokePixel`).
  test('the 16-bit plane starts as the bytes WIDENED — every value reads '
      'back as exactly its byte', () {
    final scratch = CommitTileScratch(surfaceWithTile(present, 0x7F));
    final planes = scratch.planesFor(present);
    expect(planes.bytes, everyElement(0x7F));
    expect(planes.wide, everyElement(0x7F * 257));
  });

  test('the plane is not widened again between dabs — a dab reads the '
      'plane the dab before it left', () {
    final scratch = CommitTileScratch(surfaceWithTile(present, 0));
    scratch.planesFor(present).wide[0] = 1234;
    expect(scratch.planesFor(present).wide[0], 1234);
  });

  test('a write of the bytes alone makes the plane stale — the next dab '
      'widens what the bytes hold now', () {
    // The stamp blitter and the stroke blend write bytes only: a plane
    // that missed one would pile the next dab over the old picture.
    final scratch = CommitTileScratch(surfaceWithTile(present, 0));
    scratch.planesFor(present).wide[0] = 1234;
    scratch.bufferFor(present)[0] = 0x40;
    expect(scratch.planesFor(present).wide[0], 0x40 * 257);
  });
}
