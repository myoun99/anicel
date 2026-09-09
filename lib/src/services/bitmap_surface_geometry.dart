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
/// 🚨★★★**IT USED TO RESCAN EVERY PIXEL THE CEL HELD, ON EVERY COMMIT.**
/// Both callers memoize — but on the SURFACE INSTANCE, and a commit makes
/// a new one, so the memo missed exactly while the user drew. The work
/// was nearly all repeated: a commit replaces a handful of tiles and
/// every other tile is the SAME OBJECT, whose ink cannot have moved
/// because tiles are immutable. So the box is memoized per TILE
/// ([BitmapTile.inkBounds]) and only the tiles that still owe an answer
/// are scanned. The surface-level memo above it stays — it saves the
/// walk itself, this saves the pixels.
///
/// ⚠️The old note here also warned that `surface.tiles` copied the whole
/// map before the scan started. It no longer does (2026-09-09) — the
/// getter hands the field over.
({int left, int top, int rightExclusive, int bottomExclusive})?
bitmapSurfaceContentBounds(BitmapSurface surface) {
  final box = _InkBox();
  final tileSize = surface.tileSize;
  // Tiles that already know their own box cost a lookup each; only the
  // rest reach a pixel scan.
  final unscanned = <MapEntry<TileCoord, BitmapTile>>[];
  for (final entry in surface.tiles.entries) {
    if (!entry.value.inkBoundsKnown) {
      unscanned.add(entry);
      continue;
    }
    _includeTileBox(box, entry.key, entry.value.inkBounds, tileSize);
  }
  if (unscanned.isNotEmpty) {
    // BB-N1 (ABI 22): with the engine loaded, the word scan runs in C,
    // fanned across the worker pool — the Dart loop stays as the
    // reference and the fallback (integer logic, so parity is
    // structural; the parity test pins it anyway).
    final native = QaNativeEngine.instance;
    if (native != null) {
      _scanNativeInto(box, unscanned, tileSize, native);
    } else {
      _scanDartInto(box, unscanned, tileSize);
    }
  }
  if (box.maxX < box.minX) {
    return null;
  }
  return (
    left: box.minX,
    top: box.minY,
    rightExclusive: box.maxX + 1,
    bottomExclusive: box.maxY + 1,
  );
}

/// Folds one tile's LOCAL box onto the canvas axis. A null box is an
/// ink-free tile, which contributes nothing.
void _includeTileBox(
  _InkBox box,
  TileCoord coord,
  TileInkBounds? bounds,
  int tileSize,
) {
  if (bounds == null) {
    return;
  }
  final originX = coord.x * tileSize;
  final originY = coord.y * tileSize;
  box.include(
    left: originX + bounds.left,
    top: originY + bounds.top,
    right: originX + bounds.rightExclusive - 1,
    bottom: originY + bounds.bottomExclusive - 1,
  );
}

/// The running extent of the ink found so far. Empty is stated as an
/// INVERTED box — max below min — which is the one value no real box can
/// take, so "nothing yet" needs no flag beside it.
class _InkBox {
  int minX = 0x7fffffff;
  int minY = 0x7fffffff;
  int maxX = -0x7fffffff;
  int maxY = -0x7fffffff;

  void include({
    required int left,
    required int top,
    required int right,
    required int bottom,
  }) {
    if (left < minX) minX = left;
    if (top < minY) minY = top;
    if (right > maxX) maxX = right;
    if (bottom > maxY) maxY = bottom;
  }
}

/// Stages the tiles that still owe a box for ONE batched C scan, folds
/// the answers onto the canvas axis, and MEMOIZES each on its tile.
void _scanNativeInto(
  _InkBox box,
  List<MapEntry<TileCoord, BitmapTile>> entries,
  int tileSize,
  QaNativeEngine native,
) {
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
      // Ink-free tile. Nothing to remember: `inkBounds` answers null off
      // `hasInk`, which this tile will have computed for itself.
      continue;
    }
    final local = (
      left: localMinX,
      top: bounds[i * 4 + 1],
      rightExclusive: bounds[i * 4 + 2] + 1,
      bottomExclusive: bounds[i * 4 + 3] + 1,
    );
    entries[i].value.rememberInkBounds(local);
    _includeTileBox(box, entries[i].key, local, tileSize);
  }
}

/// The reference route: each tile scans its own words and memoizes the
/// answer ([BitmapTile.inkBounds]) — the twin the native parity test
/// measures the C path against.
void _scanDartInto(
  _InkBox box,
  List<MapEntry<TileCoord, BitmapTile>> entries,
  int tileSize,
) {
  for (final entry in entries) {
    _includeTileBox(box, entry.key, entry.value.inkBounds, tileSize);
  }
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
    // 🚨★★★**ONE PASS, AND ONE CLIP LAW.** This built a whole map, handed
    // it to the public constructor (which COPIES it and re-validates
    // every tile), then handed THAT to `resizeBitmapSurfaceCanvas`, which
    // built a second map and re-validated a second time: three maps and
    // two full validations per cel, on a command that runs over every cel
    // of a cut.
    //
    // ⛔**AND THE TWO BRANCHES OF THIS FUNCTION DISAGREED ABOUT CLIPPING.**
    // The fractional branch below clips against the TARGET canvas's
    // pasteboard, as this function's own doc says it does. This branch
    // built its intermediate surface at the SOURCE canvas size, so a
    // rebase that carried a tile past the OLD pasteboard threw an
    // ArgumentError where the other branch would have clipped it. One
    // law, applied here too.
    final tileDx = dx ~/ tileSize;
    final tileDy = dy ~/ tileSize;
    final tileXMin = canvasSize.pasteboardTileXMin(tileSize);
    final tileYMin = canvasSize.pasteboardTileYMin(tileSize);
    final tileXEnd = canvasSize.pasteboardTileXEndExclusive(tileSize);
    final tileYEnd = canvasSize.pasteboardTileYEndExclusive(tileSize);
    final rebased = <TileCoord, BitmapTile>{};
    for (final entry in surface.tiles.entries) {
      final x = entry.key.x + tileDx;
      final y = entry.key.y + tileDy;
      if (x < tileXMin || y < tileYMin || x >= tileXEnd || y >= tileYEnd) {
        continue;
      }
      final coord = TileCoord(x: x, y: y);
      // 🎯**THE SHIFT IS A KEY REWRITE.** The tile does not know where it
      // sits, so moving it is renaming its map entry — the very same
      // object, which means zero pixels copied AND every decoded picture
      // the image cache holds under that object still found.
      rebased[coord] = entry.value;
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: rebased,
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

  for (final entry in surface.tiles.entries) {
    final tile = entry.value;
    final pixels = tile.pixels;
    final sourceLeft = entry.key.x * tileSize + dx;
    final sourceTop = entry.key.y * tileSize + dy;
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

  // The blank ones are dropped by the SAME law the commit tails keep —
  // this pass wrote the filter itself until 2026-09-08, and being first
  // is not a reason to keep a second copy of a rule.
  return BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
  ).putMaterializedTiles([
    for (final entry in buffers.entries)
      (
        coord: entry.key,
        tile: BitmapTile(
          size: tileSize,
          pixels: entry.value,
        ),
      ),
  ]);
}
