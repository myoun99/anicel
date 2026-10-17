import 'dart:typed_data';

import '../core/floor_math.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/cel_photo.dart';
import '../models/cel_text.dart';
import '../models/dirty_region.dart';
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
  final laid = _laidMoved(surface, dx: 0, dy: 0);
  return BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      for (final entry in surface.tiles.entries)
        if (pictureKeepsTileAt(
          entry.key,
          canvas: canvasSize,
          tileSize: tileSize,
          laid: laid,
        ))
          entry.key: entry.value,
    },
    texts: _textsMoved(surface, dx: 0, dy: 0, canvasSize: canvasSize),
    photos: _photosMoved(surface, dx: 0, dy: 0),
    laidBounds: laid,
  );
}

/// [surface]'s texts as a move of its pixels by ([dx], [dy]) onto
/// [canvasSize] leaves them: each where the picture now is.
///
/// 🚨★★★A TEXT MOVES AS THE PICTURE IT IS PART OF (유저 2026-10-06: 「셀의
/// 그림이랑 정확히 동일」). Its plate is pixels, so it takes the very pass the
/// drawing's tiles take — [translateBitmapSurface], run on the plate as a
/// surface of its own — and is cut at the same pasteboard wall. Its anchor
/// is the number those pixels were set from, so it moves by the same
/// offset: left where it was, the next edit would set the letters back at
/// the place the resize moved them away from.
///
/// ⛔Nothing is clamped or brought back when a text ends up off the page —
/// the tool law (유저 2026-09-20: 「그건 유저가 그렇게 하고싶지않으면 생각해서
/// 할일이야」).
List<CelText> _textsMoved(
  BitmapSurface surface, {
  required int dx,
  required int dy,
  required CanvasSize canvasSize,
}) => [
  for (final text in surface.texts)
    CelText(
      id: text.id,
      content: celTextContentMoved(text.content, dx: dx, dy: dy),
      plate: translateBitmapSurface(
        celTextPlateSurface(
          text.plate,
          canvasSize: surface.canvasSize,
          tileSize: surface.tileSize,
        ),
        dx: dx,
        dy: dy,
        canvasSize: canvasSize,
      ).tiles,
    ),
];

/// A text's [plate] as a surface of its own on the grid of its cel —
/// [canvasSize], in tiles of [tileSize]: what lets its pixels take the
/// passes a drawing's tiles take, and be read as theirs are.
BitmapSurface celTextPlateSurface(
  Map<TileCoord, BitmapTile> plate, {
  required CanvasSize canvasSize,
  required int tileSize,
}) => BitmapSurface(canvasSize: canvasSize, tileSize: tileSize, tiles: plate);

/// [surface]'s photos as a move of its pixels by ([dx], [dy]) leaves them:
/// each where the picture now is. A photo stands on the picture's grid
/// (I-97), so it moves by the very offset the drawing does — and nothing is
/// clamped, as nothing is for a text (the tool law above).
///
/// ⚠️The reference row's resize moves its pose by the same arithmetic
/// (`translateLayerForResize`): two spellings of 「a reference moves with
/// the content」, left two by the rule of three until a third appears.
List<CelPhoto> _photosMoved(
  BitmapSurface surface, {
  required int dx,
  required int dy,
}) => [
  for (final photo in surface.photos)
    photo.withReference(
      photo.reference.copyWith(
        pose: photo.reference.pose.copyWith(
          center: CanvasPoint(
            x: photo.reference.pose.center.x + dx,
            y: photo.reference.pose.center.y + dy,
          ),
        ),
      ),
    ),
];

/// Where [surface]'s laid picture lies ([BitmapSurface.laidBounds]) once a
/// move of its pixels by ([dx], [dy]) has carried it — the whole of it,
/// never cut at the new pasteboard (F-374-Q8: 「참조 그림은 벽 밖까지
/// 통째로」).
DirtyRegion? _laidMoved(
  BitmapSurface surface, {
  required int dx,
  required int dy,
}) {
  final laid = surface.laidBounds;
  return laid == null || (dx == 0 && dy == 0)
      ? laid
      : DirtyRegion(
          left: laid.left + dx,
          top: laid.top + dy,
          rightExclusive: laid.rightExclusive + dx,
          bottomExclusive: laid.bottomExclusive + dy,
        );
}

/// [content] standing ([dx], [dy]) whole pixels from where it stood — the
/// number its plate's pixels were set from, moved as they are
/// ([celTextPlateMoved]).
CelTextContent celTextContentMoved(
  CelTextContent content, {
  required int dx,
  required int dy,
}) => dx == 0 && dy == 0
    ? content
    : content.copyWith(
        anchor: CanvasPoint(x: content.anchor.x + dx, y: content.anchor.y + dy),
      );

/// A text's [pixels] — its plate moved by whole pixels — cut onto the grid
/// of its cel, [canvasSize] in tiles of [tileSize]: the very pass a
/// drawing's tiles take ([translateBitmapSurface]), run on the plate as a
/// surface of its own ([celTextPlateSurface]), and cut at the same
/// pasteboard wall.
///
/// The text tool moves a text by this (R9-rest) — a text dragged a whole
/// number of pixels is its pixels dragged, with nothing set again.
Map<TileCoord, BitmapTile> celTextPlateMoved(
  CelTextPixels pixels, {
  required CanvasSize canvasSize,
  required int tileSize,
}) => translateBitmapSurface(
  celTextPlateSurface(pixels.plate, canvasSize: canvasSize, tileSize: tileSize),
  dx: pixels.dx,
  dy: pixels.dy,
  canvasSize: canvasSize,
).tiles;

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
    final laid = _laidMoved(surface, dx: dx, dy: dy);
    final rebased = <TileCoord, BitmapTile>{};
    for (final entry in surface.tiles.entries) {
      final coord = TileCoord(x: entry.key.x + tileDx, y: entry.key.y + tileDy);
      if (!pictureKeepsTileAt(
        coord,
        canvas: canvasSize,
        tileSize: tileSize,
        laid: laid,
      )) {
        continue;
      }
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
      texts: _textsMoved(surface, dx: dx, dy: dy, canvasSize: canvasSize),
      photos: _photosMoved(surface, dx: dx, dy: dy),
      laidBounds: laid,
    );
  }

  final blit = _MovedBlit(tileSize: tileSize, dx: dx, dy: dy);

  // The output is bounded by the TARGET canvas's pasteboard; pixels
  // shifted beyond it clip — the anchored-resize command snapshots baked
  // references for its undo, so nothing is lost across an undo round
  // trip.
  blit.into(
    surface.tiles.entries,
    clip: (
      left: canvasSize.pasteboardLeft,
      top: canvasSize.pasteboardTop,
      rightExclusive: null,
      bottomExclusive: null,
    ),
    keeps: canvasSize.pasteboardTileRange(tileSize),
  );
  // A laid picture goes where its pixels went, whole (F-374-Q8: 「참조
  // 그림은 벽 밖까지 통째로」) — the same blit, into the rect it covers now,
  // from the tiles that held it.
  final laid = _laidMoved(surface, dx: dx, dy: dy);
  final laidBefore = surface.laidBounds;
  if (laid != null && laidBefore != null) {
    final held = laidBefore.tileRange(tileSize: tileSize);
    blit.into(
      surface.tiles.entries.where((entry) => tileRangeHolds(held, entry.key)),
      clip: (
        left: laid.left,
        top: laid.top,
        rightExclusive: laid.rightExclusive,
        bottomExclusive: laid.bottomExclusive,
      ),
      keeps: laid.tileRange(tileSize: tileSize),
    );
  }

  // The blank ones are dropped by the SAME law the commit tails keep —
  // this pass wrote the filter itself until 2026-09-08, and being first
  // is not a reason to keep a second copy of a rule.
  return BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    texts: _textsMoved(surface, dx: dx, dy: dy, canvasSize: canvasSize),
    photos: _photosMoved(surface, dx: dx, dy: dy),
    laidBounds: laid,
  ).putMaterializedTiles([
    for (final entry in blit.buffers.entries)
      (
        coord: entry.key,
        tile: BitmapTile(
          size: tileSize,
          pixels: entry.value,
        ),
      ),
  ]);
}

/// Where a moved pixel may land, in canvas pixels: right of [left] and
/// below [top], and left of and above the other two edges where it has
/// them — the pasteboard cuts its right and bottom at the tile ([keeps]).
typedef _BlitClip = ({
  int left,
  int top,
  int? rightExclusive,
  int? bottomExclusive,
});

/// The fractional-of-a-tile move of [translateBitmapSurface]: each input
/// tile's rows blitted into the up to four output tiles they land in,
/// gathered in [buffers].
class _MovedBlit {
  _MovedBlit({required this.tileSize, required this.dx, required this.dy})
    : _rowBytes = tileSize * BitmapTile.bytesPerPixel;

  final int tileSize;
  final int dx;
  final int dy;
  final int _rowBytes;

  /// The output tiles, by where they sit.
  final buffers = <TileCoord, Uint8List>{};

  /// [tiles] moved, each pixel kept where it lands inside [clip] on a tile
  /// [keeps] holds. A pixel two blits keep is written twice, the same bytes
  /// both times.
  void into(
    Iterable<MapEntry<TileCoord, BitmapTile>> tiles, {
    required _BlitClip clip,
    required TileRange keeps,
  }) {
    final bottom = clip.bottomExclusive;
    final right = clip.rightExclusive;
    for (final entry in tiles) {
      final pixels = entry.value.pixels;
      final sourceLeft = entry.key.x * tileSize + dx;
      final sourceTop = entry.key.y * tileSize + dy;
      final width = right == null || right >= sourceLeft + tileSize
          ? tileSize
          : right - sourceLeft;
      for (var row = 0; row < tileSize; row += 1) {
        final worldY = sourceTop + row;
        if (worldY < clip.top || (bottom != null && worldY >= bottom)) {
          continue;
        }
        _row(
          pixels,
          (row: row, worldY: worldY, from: sourceLeft, width: width),
          left: clip.left,
          keeps: keeps,
        );
      }
    }
  }

  /// One row of a source tile's [pixels] — its [_SourceRow.width] pixels
  /// from x [_SourceRow.from], landing at [_SourceRow.worldY] — in up to two
  /// horizontal output tiles, from [left] on.
  void _row(
    Uint8List pixels,
    _SourceRow source, {
    required int left,
    required TileRange keeps,
  }) {
    final (:row, :worldY, from: sourceLeft, :width) = source;
    final tileY = floorDiv(worldY, tileSize);
    final localY = worldY - tileY * tileSize;
    var worldX = sourceLeft;
    var sourceOffset = row * _rowBytes;
    var remaining = width;
    while (remaining > 0) {
      if (worldX < left) {
        final skip = left - worldX;
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
      final target = _bufferFor(TileCoord(x: tileX, y: tileY), keeps);
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

  /// The output tile at [coord], made blank the first time — or null where
  /// [keeps] holds no tile there.
  Uint8List? _bufferFor(TileCoord coord, TileRange keeps) =>
      tileRangeHolds(keeps, coord)
      ? buffers.putIfAbsent(coord, () => Uint8List(tileSize * _rowBytes))
      : null;
}

/// A row of a source tile as [_MovedBlit] lands it: which [row] of the
/// tile, the canvas row [worldY] it lands on, and the [width] pixels kept
/// of it from the x it lands at, [from].
typedef _SourceRow = ({int row, int worldY, int from, int width});
