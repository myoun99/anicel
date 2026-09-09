import 'dart:typed_data';

import 'bitmap_tile.dart';

/// THE copy-on-write tile rewrite: runs [body] over the tile's own bytes
/// and returns a NEW tile only if [body] wrote anything, otherwise null.
///
/// Reads come from the tile's own bytes and writes go to the copy, so "the
/// original value" stays available even after the pixel beside it has been
/// overwritten. The copy is made LAZILY, at the first pixel that actually
/// changes: a tile the walk crosses but never writes keeps its ORIGINAL
/// object and, the tile map being immutable, is then shared with the old
/// surface — the single biggest reason a whole-canvas pass over line art
/// costs almost nothing, and what lets the tile image cache keep the image
/// already decoded for it.
///
/// [body] receives the read-only view and returns the buffer it lazily
/// copied (`out ??= Uint8List.fromList(view)` at the first write), or null
/// when it touched nothing. It is called ONCE PER TILE, so the per-pixel
/// loop inside it stays a plain loop — that loop is each caller's own law
/// and does not move here.
BitmapTile? rewriteTileLazily(
  BitmapTile tile,
  int tileSize,
  Uint8List? Function(Uint8List view) body,
) {
  final written = tile.readPixels<Uint8List?>((_, view) => body(view));
  return written == null
      ? null
      : BitmapTile(size: tileSize, pixels: written);
}
