import 'dart:typed_data';

import '../core/floor_math.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/canvas_size.dart';
import '../models/pasteboard_bounds.dart';
import '../models/tile_coord.dart';
import '../native/qa_native_engine.dart';

/// Raster geometry ops for baked surfaces (R19 bake-only): canvas resize
/// and anchored-content translation operate on PIXELS now — the raster
/// is the truth. A resize is top-left anchored: in-bounds tiles keep
/// their coords, tiles beyond the new PASTEBOARD drop (raster crop, PS
/// semantics — the pasteboard shrinks with the canvas). The resize
/// COMMAND keeps a reference snapshot of the pre-resize baked surfaces,
/// so its undo restores cropped pixels exactly.
/// The tight pixel bounding box of the surface's INK (any pixel with a
/// non-zero alpha), in canvas coordinates — or null when no visible
/// pixel exists. R26 #13 follow-up (user rule 07-22): the whole-picture
/// transform box frames exactly the picture, PS-style, not the canvas.
///
/// One full scan per call, and `surface.tiles` copies the cel's whole
/// tile map before the scan even starts. The word loop fast-skips fully
/// transparent pixels (most of an animation cel), so the common cost is
/// memory bandwidth — but it is still far too much to spend per frame.
/// ⚠️ This comment used to promise "callers open a session with it,
/// never a per-frame path" and that was already false: the selection
/// layer frames the always-on move box from `build`. Callers on a build
/// path MUST memoize on the surface instance (BrushCanvasPanel does).
({int left, int top, int rightExclusive, int bottomExclusive})?
bitmapSurfaceContentBounds(BitmapSurface surface) {
  final tileSize = surface.tileSize;
  var minX = 0x7fffffff, minY = 0x7fffffff;
  var maxX = -0x7fffffff, maxY = -0x7fffffff;
  // BB-N1 (ABI 22): with the engine loaded, every tile's word scan runs
  // in C, fanned across the worker pool — the Dart loop below stays as
  // the reference and the fallback (integer logic, so parity is
  // structural; the parity test pins it anyway).
  final native = QaNativeEngine.instance;
  if (native != null && surface.tiles.isNotEmpty) {
    final entries = surface.tiles.entries.toList();
    native.ensureTileSpanBatch(entries.length);
    for (var i = 0; i < entries.length; i += 1) {
      // Only tilePixels is consumed — the scan is whole-tile. The staged
      // pointers outlive this loop (the batch call below reads them), so
      // what keeps the buffers alive is `entries` holding every tile —
      // and it is used again after the call.
      entries[i].value.readPixels(
        (pointer, _) => native.setTileSpan(
          i,
          tilePixels: pointer,
          tileLeft: 0,
          tileTop: 0,
          spanLeft: 0,
          spanRightExclusive: tileSize,
          spanTop: 0,
          spanBottomExclusive: tileSize,
        ),
      );
    }
    final bounds = native.alphaBoundsTiles(
      count: entries.length,
      tileSize: tileSize,
    );
    for (var i = 0; i < entries.length; i += 1) {
      final localMinX = bounds[i * 4];
      if (localMinX == 0x7fffffff) {
        continue; // Ink-free tile.
      }
      final originX = entries[i].key.x * tileSize;
      final originY = entries[i].key.y * tileSize;
      final tileMinX = originX + localMinX;
      final tileMinY = originY + bounds[i * 4 + 1];
      final tileMaxX = originX + bounds[i * 4 + 2];
      final tileMaxY = originY + bounds[i * 4 + 3];
      if (tileMinX < minX) minX = tileMinX;
      if (tileMinY < minY) minY = tileMinY;
      if (tileMaxX > maxX) maxX = tileMaxX;
      if (tileMaxY > maxY) maxY = tileMaxY;
    }
    if (maxX < minX) {
      return null;
    }
    return (
      left: minX,
      top: minY,
      rightExclusive: maxX + 1,
      bottomExclusive: maxY + 1,
    );
  }
  for (final entry in surface.tiles.entries) {
    final originX = entry.key.x * tileSize;
    final originY = entry.key.y * tileSize;
    // RGBA little-endian: alpha is the word's top byte. The native view
    // reads in place — the [BitmapTile.pixels] getter would copy every
    // tile just to scan it — and readPixels keeps the tile alive for the
    // scan (see BitmapTile.readPixels).
    entry.value.readPixels((_, bytes) {
      final words = bytes.buffer.asUint32List(0, tileSize * tileSize);
      for (var y = 0; y < tileSize; y += 1) {
        final rowStart = y * tileSize;
        for (var x = 0; x < tileSize; x += 1) {
          final word = words[rowStart + x];
          if (word == 0 || (word & 0xff000000) == 0) {
            continue;
          }
          final worldX = originX + x;
          final worldY = originY + y;
          if (worldX < minX) {
            minX = worldX;
          }
          if (worldX > maxX) {
            maxX = worldX;
          }
          if (worldY < minY) {
            minY = worldY;
          }
          if (worldY > maxY) {
            maxY = worldY;
          }
        }
      }
    });
  }
  if (maxX < minX) {
    return null;
  }
  return (
    left: minX,
    top: minY,
    rightExclusive: maxX + 1,
    bottomExclusive: maxY + 1,
  );
}

BitmapSurface resizeBitmapSurfaceCanvas(
  BitmapSurface surface,
  CanvasSize canvasSize,
) {
  if (surface.canvasSize == canvasSize) {
    return surface;
  }
  final tileSize = surface.tileSize;
  final tileXMin = canvasSize.pasteboardTileXMin(tileSize);
  final tileYMin = canvasSize.pasteboardTileYMin(tileSize);
  final tileXEnd = canvasSize.pasteboardTileXEndExclusive(tileSize);
  final tileYEnd = canvasSize.pasteboardTileYEndExclusive(tileSize);
  return BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      for (final entry in surface.tiles.entries)
        if (entry.key.x >= tileXMin &&
            entry.key.y >= tileYMin &&
            entry.key.x < tileXEnd &&
            entry.key.y < tileYEnd)
          entry.key: entry.value,
    },
  );
}

/// Translates the surface's pixels by integer ([dx], [dy]) and adopts
/// [canvasSize] — the anchored-resize blit. Whole-tile shifts rebase
/// coordinates for free; fractional-of-a-tile shifts blit each input
/// tile's rows into up to four output tiles. Fully transparent output
/// tiles are dropped.
BitmapSurface translateBitmapSurface(
  BitmapSurface surface, {
  required int dx,
  required int dy,
  required CanvasSize canvasSize,
}) {
  if (dx == 0 && dy == 0) {
    return resizeBitmapSurfaceCanvas(surface, canvasSize);
  }
  final tileSize = surface.tileSize;

  if (dx % tileSize == 0 && dy % tileSize == 0) {
    final tileDx = dx ~/ tileSize;
    final tileDy = dy ~/ tileSize;
    final rebased = <TileCoord, BitmapTile>{};
    for (final entry in surface.tiles.entries) {
      final coord = TileCoord(x: entry.key.x + tileDx, y: entry.key.y + tileDy);
      rebased[coord] = entry.value.copyWith(coord: coord);
    }
    return resizeBitmapSurfaceCanvas(
      BitmapSurface(
        canvasSize: surface.canvasSize,
        tileSize: tileSize,
        tiles: rebased,
      ),
      canvasSize,
    );
  }

  final rowBytes = tileSize * BitmapTile.bytesPerPixel;
  final buffers = <TileCoord, Uint8List>{};

  // The output is bounded by the TARGET canvas's pasteboard; pixels
  // shifted beyond it clip — the anchored-resize command snapshots baked
  // references for its undo, so nothing is lost across an undo round
  // trip.
  final outTileXMin = canvasSize.pasteboardTileXMin(tileSize);
  final outTileYMin = canvasSize.pasteboardTileYMin(tileSize);
  final outTileXEnd = canvasSize.pasteboardTileXEndExclusive(tileSize);
  final outTileYEnd = canvasSize.pasteboardTileYEndExclusive(tileSize);
  final pasteboardLeft = canvasSize.pasteboardLeft;
  final pasteboardTop = canvasSize.pasteboardTop;
  Uint8List? bufferFor(int tileX, int tileY) {
    if (tileX < outTileXMin ||
        tileY < outTileYMin ||
        tileX >= outTileXEnd ||
        tileY >= outTileYEnd) {
      return null;
    }
    return buffers.putIfAbsent(
      TileCoord(x: tileX, y: tileY),
      () => Uint8List(tileSize * rowBytes),
    );
  }

  for (final tile in surface.tiles.values) {
    final pixels = tile.pixels;
    final sourceLeft = tile.coord.x * tileSize + dx;
    final sourceTop = tile.coord.y * tileSize + dy;
    for (var row = 0; row < tileSize; row += 1) {
      final worldY = sourceTop + row;
      if (worldY < pasteboardTop) {
        continue;
      }
      final tileY = floorDiv(worldY, tileSize);
      final localY = worldY - tileY * tileSize;
      // The row lands in up to two horizontal output tiles.
      var worldX = sourceLeft;
      var sourceOffset = row * rowBytes;
      var remaining = tileSize;
      while (remaining > 0) {
        if (worldX < pasteboardLeft) {
          final skip = pasteboardLeft - worldX;
          final clipped = skip > remaining ? remaining : skip;
          worldX += clipped;
          sourceOffset += clipped * BitmapTile.bytesPerPixel;
          remaining -= clipped;
          continue;
        }
        final tileX = floorDiv(worldX, tileSize);
        final localX = worldX - tileX * tileSize;
        final span = (tileSize - localX) < remaining
            ? (tileSize - localX)
            : remaining;
        final target = bufferFor(tileX, tileY);
        if (target != null) {
          target.setRange(
            (localY * tileSize + localX) * BitmapTile.bytesPerPixel,
            (localY * tileSize + localX + span) * BitmapTile.bytesPerPixel,
            pixels,
            sourceOffset,
          );
        }
        worldX += span;
        sourceOffset += span * BitmapTile.bytesPerPixel;
        remaining -= span;
      }
    }
  }

  final tiles = <TileCoord, BitmapTile>{};
  for (final entry in buffers.entries) {
    final tile = BitmapTile(
      coord: entry.key,
      size: tileSize,
      pixels: entry.value,
    );
    if (!tile.isFullyTransparent) {
      tiles[entry.key] = tile;
    }
  }
  return BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: tiles,
  );
}
