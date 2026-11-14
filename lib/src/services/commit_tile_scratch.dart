import 'dart:typed_data';

import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/tile_coord.dart';
import 'brush_dab_kernel.dart';

/// Writes `bytes[i] * 257` into [wide] — the plane a byte reads back from
/// as exactly itself (`StrokePixel.widened`).
void widenStrokeBytes(Uint8List bytes, Uint16List wide) {
  for (var index = 0; index < bytes.length; index += 1) {
    wide[index] = bytes[index] * 257;
  }
}

/// The per-tile scratch a commit blends into off the engine's grid: stage
/// a tile's bytes, blend, then finish the changed ones as tiles.
///
/// Mutable scratch pixels per touched tile. `BitmapTile.pixels` already
/// returns a defensive copy, so it can be mutated freely; blank tiles
/// start as zeroed buffers without allocating a BitmapTile.
///
/// 🚨A DAB PILES UP ON THE TILE'S 16-BIT PLANE (ABI 40 — the law beside
/// `StrokePixel`), and everything else writes the BYTES alone: the stamp
/// blitter and the stroke blend. So a tile's plane is WIDENED from its bytes
/// (a byte * 257, which reads back as exactly the byte) whenever a dab asks
/// for it after the bytes moved without it — on first use, and after every
/// [bufferFor] hand-out. ⛔A plane that missed a stamp would pile the next
/// dab over a picture the stamp had already changed.
///
/// A stroke with a SECOND TIP (ABI 60) carries a second plane a tile too,
/// alpha * 65535 a pixel, zeroed when the tile is first asked for — its
/// bytes are then the view of the two (`dualViewAlpha`). ⚠️Such a stroke's
/// bytes are no widening of its first plane, and nothing that writes bytes
/// alone lands inside one: a brush stroke is dabs.
///
/// ↩️Till 2026-11-12 there were two of these, chosen by type: this one,
/// and one in the C engine's pooled memory whose changed buffers the
/// finished tiles adopted with no copy out (R18 A-1 / R19-Z). The app's
/// commits land on the engine since, and only a test's grid comes here.
final class CommitTileScratch {
  CommitTileScratch(this._surface, {this.secondTip = false})
    : _tileByteLength = _surface.tileBytes;

  final BitmapSurface _surface;
  final int _tileByteLength;

  /// Whether the stroke has a second tip, and so a second plane a tile.
  final bool secondTip;
  final Map<TileCoord, Uint8List> _buffers = {};
  final Map<TileCoord, Uint16List> _wides = {};
  final Map<TileCoord, Uint16List> _seconds = {};

  /// The tiles whose plane holds what their bytes hold.
  final Set<TileCoord> _wideCurrent = {};

  Uint8List _stage(TileCoord coord) {
    return _buffers.putIfAbsent(coord, () {
      final tile = _surface.tileAt(coord);
      if (tile == null) {
        return Uint8List(_tileByteLength);
      }
      return tile.pixels;
    });
  }

  /// The mutable bytes for [coord], staged on first request (the tile's
  /// pixels copied in, or zeroes when the surface has no tile there) and
  /// the SAME buffer on every request after — a second dab on the tile
  /// blends over the first. A writer of the bytes alone asks here.
  Uint8List bufferFor(TileCoord coord) {
    _wideCurrent.remove(coord);
    return _stage(coord);
  }

  /// [bufferFor]'s bytes with the 16-bit plane beside them — what the dab
  /// kernel blends into ([BrushDabTileBuffers]).
  BrushDabTileBuffers planesFor(TileCoord coord) {
    final bytes = _stage(coord);
    final wide = _wides.putIfAbsent(
      coord,
      () => Uint16List(_tileByteLength),
    );
    if (_wideCurrent.add(coord)) {
      widenStrokeBytes(bytes, wide);
    }
    return (
      bytes: bytes,
      wide: wide,
      second: !secondTip
          ? null
          : _seconds.putIfAbsent(
              coord,
              () => Uint16List(_tileByteLength ~/ 4),
            ),
    );
  }

  /// The finished tile for a coordinate that changed — its buffer, copied
  /// by the tile's constructor, and gone from the scratch.
  BitmapTile finish(TileCoord coord) {
    _wides.remove(coord);
    _seconds.remove(coord);
    _wideCurrent.remove(coord);
    return BitmapTile(size: _surface.tileSize, pixels: _buffers.remove(coord)!);
  }
}
