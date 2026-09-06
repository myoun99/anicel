import 'dart:ffi' show Pointer, Uint8;
import 'dart:typed_data';

import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/tile_coord.dart';
import '../native/qa_native_engine.dart';

/// The per-tile scratch a commit blends into: acquire a tile's bytes,
/// blend, then either ADOPT the buffer as the finished tile or give it
/// back — the acquire / blend / adopt-or-release shape.
///
/// 🚨ONE scratch for the dab-sequence commit and the native stroke-blend
/// landing (round 8 of the audit, 2026-09-06). The two implementations
/// are chosen by TYPE — [NativeCommitScratch] when the engine is loaded,
/// [DartCommitScratch] otherwise — so no flag inside a loop asks which
/// world it is in.
///
/// Mutable scratch pixels per touched tile. `BitmapTile.pixels` already
/// returns a defensive copy, so it can be mutated freely; blank tiles
/// start as zeroed buffers without allocating a BitmapTile.
abstract interface class CommitTileScratch {
  /// The mutable bytes for [coord], staged on first request (the tile's
  /// pixels copied in, or zeroes when the surface has no tile there) and
  /// the SAME buffer on every request after — a second dab on the tile
  /// blends over the first.
  Uint8List bufferFor(TileCoord coord);

  /// The finished tile for a coordinate that changed. The buffer leaves
  /// the scratch: it is the tile now.
  BitmapTile finish(TileCoord coord);

  /// Gives back every staged buffer nobody finished.
  void releaseUnfinished();
}

/// With the native engine loaded (R18 A-1 / R19-Z) the scratch lives in
/// pooled NATIVE memory: staging is a C memcpy from the tile's native
/// buffer, Dart works through a typed-data view (the fallback and stamp
/// loops run unchanged) while the kernel gets the raw pointer, and the
/// commit tail ADOPTS the changed buffers as the finished tiles — the
/// whole sequence materializes with zero pixel copies out.
final class NativeCommitScratch implements CommitTileScratch {
  NativeCommitScratch(this.native, this._surface)
    : _tileByteLength =
          _surface.tileSize * _surface.tileSize * BitmapTile.bytesPerPixel;

  final QaNativeEngine native;
  final BitmapSurface _surface;
  final int _tileByteLength;
  final Map<TileCoord, QaNativeTileBuffer> _buffers = {};

  /// The staged native buffer for [coord] — the kernels' side of
  /// [bufferFor].
  QaNativeTileBuffer stage(TileCoord coord) {
    return _buffers.putIfAbsent(coord, () {
      final tile = _surface.tileAt(coord);
      final buffer = native.acquireTileBuffer(
        _tileByteLength,
        zeroed: tile == null,
      );
      if (tile != null) {
        // readPixels keeps the tile alive across the copy — a bare
        // pointer would let its finalizer recycle the block mid-memcpy
        // (see BitmapTile.readPixels).
        tile.readPixels(
          (pointer, _) =>
              native.copyBytes(buffer.pointer, pointer, _tileByteLength),
        );
      }
      return buffer;
    });
  }

  /// [stage]'s raw pointer — what a span batch is handed per span.
  Pointer<Uint8> pointerFor(TileCoord coord) => stage(coord).pointer;

  @override
  Uint8List bufferFor(TileCoord coord) => stage(coord).view;

  @override
  BitmapTile finish(TileCoord coord) => BitmapTile.adoptNative(
    coord: coord,
    size: _surface.tileSize,
    pixels: _buffers.remove(coord)!.pointer,
  );

  @override
  void releaseUnfinished() {
    for (final buffer in _buffers.values) {
      native.releaseTileBuffer(buffer);
    }
    _buffers.clear();
  }
}

/// The no-engine scratch: Dart byte lists, and the finished tile takes
/// the constructor copy.
final class DartCommitScratch implements CommitTileScratch {
  DartCommitScratch(this._surface)
    : _tileByteLength =
          _surface.tileSize * _surface.tileSize * BitmapTile.bytesPerPixel;

  final BitmapSurface _surface;
  final int _tileByteLength;
  final Map<TileCoord, Uint8List> _buffers = {};

  @override
  Uint8List bufferFor(TileCoord coord) {
    return _buffers.putIfAbsent(coord, () {
      final tile = _surface.tileAt(coord);
      if (tile == null) {
        return Uint8List(_tileByteLength);
      }
      return tile.pixels;
    });
  }

  @override
  BitmapTile finish(TileCoord coord) => BitmapTile(
    coord: coord,
    size: _surface.tileSize,
    pixels: _buffers.remove(coord)!,
  );

  @override
  void releaseUnfinished() {
    _buffers.clear();
  }
}
