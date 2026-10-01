import 'dart:ffi' show Pointer, Uint16, Uint16Pointer, Uint8;
import 'dart:typed_data';

import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/tile_coord.dart';
import '../native/qa_native_engine.dart';
import 'brush_dab_kernel.dart';

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
///
/// 🚨A DAB PILES UP ON THE TILE'S 16-BIT PLANE (ABI 40 — the law beside
/// `qa_dab_store`), and everything else writes the BYTES alone: the stamp
/// blitter and the stroke blend. So a tile's plane is WIDENED from its bytes
/// (a byte * 257, which reads back as exactly the byte) whenever a dab asks
/// for it after the bytes moved without it — on first use, and after every
/// [bufferFor] hand-out. ⛔A plane that missed a stamp would pile the next
/// dab over a picture the stamp had already changed.
abstract interface class CommitTileScratch {
  /// The mutable bytes for [coord], staged on first request (the tile's
  /// pixels copied in, or zeroes when the surface has no tile there) and
  /// the SAME buffer on every request after — a second dab on the tile
  /// blends over the first. A writer of the bytes alone asks here.
  Uint8List bufferFor(TileCoord coord);

  /// [bufferFor]'s bytes with the 16-bit plane beside them — what the dab
  /// kernel blends into ([BrushDabTileBuffers]).
  BrushDabTileBuffers planesFor(TileCoord coord);

  /// The finished tile for a coordinate that changed. The buffer leaves
  /// the scratch: it is the tile now.
  BitmapTile finish(TileCoord coord);

  /// Gives back every staged buffer nobody finished.
  void releaseUnfinished();
}

/// Writes `bytes[i] * 257` into [wide] — the plane a byte reads back from
/// as exactly itself (`qa_dab_store`).
void widenStrokeBytes(Uint8List bytes, Uint16List wide) {
  for (var index = 0; index < bytes.length; index += 1) {
    wide[index] = bytes[index] * 257;
  }
}

/// With the native engine loaded (R18 A-1 / R19-Z) the scratch lives in
/// pooled NATIVE memory: staging is a C memcpy from the tile's native
/// buffer, Dart works through a typed-data view (the fallback and stamp
/// loops run unchanged) while the kernel gets the raw pointer, and the
/// commit tail ADOPTS the changed buffers as the finished tiles — the
/// whole sequence materializes with zero pixel copies out.
final class NativeCommitScratch implements CommitTileScratch {
  NativeCommitScratch(this.native, this._surface)
    : _tileByteLength = _surface.tileBytes;

  final QaNativeEngine native;
  final BitmapSurface _surface;
  final int _tileByteLength;
  final Map<TileCoord, QaNativeTileBuffer> _buffers = {};
  final Map<TileCoord, QaNativeTileBuffer> _wides = {};

  /// The tiles whose plane holds what their bytes hold.
  final Set<TileCoord> _wideCurrent = {};

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

  QaNativeTileBuffer _stageWide(TileCoord coord) {
    final bytes = stage(coord);
    final wide = _wides.putIfAbsent(
      coord,
      () => native.acquireTileBuffer(_tileByteLength * 2, zeroed: false),
    );
    if (_wideCurrent.add(coord)) {
      widenStrokeBytes(bytes.view, _wideView(wide));
    }
    return wide;
  }

  Uint16List _wideView(QaNativeTileBuffer wide) =>
      wide.pointer.cast<Uint16>().asTypedList(_tileByteLength);

  /// [stage]'s raw pointer — what a span batch of a bytes-only kernel (the
  /// stamp, the stroke blend) is handed per span.
  Pointer<Uint8> pointerFor(TileCoord coord) {
    _wideCurrent.remove(coord);
    return stage(coord).pointer;
  }

  /// Both planes' raw pointers — what the dab batch is handed per span.
  BrushDabTilePointers pointersFor(TileCoord coord) {
    final wide = _stageWide(coord);
    return (pixels: stage(coord).pointer, wide: wide.pointer.cast<Uint16>());
  }

  @override
  Uint8List bufferFor(TileCoord coord) {
    _wideCurrent.remove(coord);
    return stage(coord).view;
  }

  @override
  BrushDabTileBuffers planesFor(TileCoord coord) {
    final wide = _stageWide(coord);
    return (bytes: stage(coord).view, wide: _wideView(wide));
  }

  @override
  BitmapTile finish(TileCoord coord) {
    _releaseWide(coord);
    return BitmapTile.adoptNative(
      size: _surface.tileSize,
      pixels: _buffers.remove(coord)!.pointer,
    );
  }

  void _releaseWide(TileCoord coord) {
    final wide = _wides.remove(coord);
    if (wide != null) {
      native.releaseTileBuffer(wide);
    }
    _wideCurrent.remove(coord);
  }

  @override
  void releaseUnfinished() {
    for (final buffer in _buffers.values) {
      native.releaseTileBuffer(buffer);
    }
    for (final wide in _wides.values) {
      native.releaseTileBuffer(wide);
    }
    _buffers.clear();
    _wides.clear();
    _wideCurrent.clear();
  }
}

/// The no-engine scratch: Dart byte lists, and the finished tile takes
/// the constructor copy.
final class DartCommitScratch implements CommitTileScratch {
  DartCommitScratch(this._surface)
    : _tileByteLength = _surface.tileBytes;

  final BitmapSurface _surface;
  final int _tileByteLength;
  final Map<TileCoord, Uint8List> _buffers = {};
  final Map<TileCoord, Uint16List> _wides = {};
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

  @override
  Uint8List bufferFor(TileCoord coord) {
    _wideCurrent.remove(coord);
    return _stage(coord);
  }

  @override
  BrushDabTileBuffers planesFor(TileCoord coord) {
    final bytes = _stage(coord);
    final wide = _wides.putIfAbsent(
      coord,
      () => Uint16List(_tileByteLength),
    );
    if (_wideCurrent.add(coord)) {
      widenStrokeBytes(bytes, wide);
    }
    return (bytes: bytes, wide: wide);
  }

  @override
  BitmapTile finish(TileCoord coord) {
    _wides.remove(coord);
    _wideCurrent.remove(coord);
    return BitmapTile(size: _surface.tileSize, pixels: _buffers.remove(coord)!);
  }

  @override
  void releaseUnfinished() {
    _buffers.clear();
    _wides.clear();
    _wideCurrent.clear();
  }
}
