/// Rows of a picture cut into a cel's tile blocks where the rows are — on
/// the isolate that decoded them. Its own file because two isolates cut:
/// an import's worker ([cutFileInWorker]) and the one that decodes a movie
/// (`VideoDecodeBackend.cutFrame`), which the pictures an import lays name
/// in their turn.
library;

import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/floor_math.dart';
import '../../core/zero_bytes.dart';
import '../../models/bitmap_tile.dart';
import '../../models/canvas_size.dart';
import '../../models/dirty_region.dart';
import '../../models/tile_coord.dart';
import '../../native/tile_blocks.dart';
import '../persistence/brush_drawing_binary_codec.dart'
    show AnicelLaidCel, LaidPixels;

/// Where a lay puts a picture on a [canvas]-sized cel of [tileSize] tiles:
/// over the [tiles] the placed picture covers inside the pasteboard wall
/// (tiles beyond it are refused by the surface) — or, laid whole, over the
/// picture's own rect on whole pixels, which the surface keeps tiles over
/// and is told of ([laid], `BitmapSurface.laidBounds`).
typedef CelLayout = ({
  CanvasSize canvas,
  int tileSize,
  TileRange tiles,
  DirtyRegion? laid,
});

/// Where a picture laid 1:1 is cut into a cel's tiles: its top-left on the
/// canvas, on whole pixels, and the [layout] its lay makes.
typedef PictureCut = ({int left, int top, CelLayout layout});

/// What a [TileCutter] reads of a [PictureCut]: the picture's top-left and
/// the [tiles] of [tileSize] its rows go into. Records and primitives only —
/// it crosses to the isolate that decodes a movie, whose requests carry
/// nothing else.
typedef TileCut = ({int left, int top, int tileSize, TileRange tiles});

/// The tiles a cut made: each one's place and its pixels as they cross to
/// the asking isolate, which adopts them — the native block that holds
/// them, or their one word ([LaidPixels]).
typedef CutTiles = List<({int x, int y, LaidPixels pixels})>;

/// What [cut] hands a [TileCutter].
TileCut tileCutOf(PictureCut cut) => (
  left: cut.left,
  top: cut.top,
  tileSize: cut.layout.tileSize,
  tiles: cut.layout.tiles,
);

/// The cel [layout] lays, of the [tiles] a cut made of it — to adopt
/// (`laidCelSurface`).
AnicelLaidCel laidCelOf(CelLayout layout, CutTiles tiles) => (
  canvasSize: layout.canvas,
  tileSize: layout.tileSize,
  tiles: tiles,
  texts: const [],
  photos: const [],
  laidBounds: layout.laid,
);

/// Where a picture's rows go, one at a time, top to bottom: row [y] of it,
/// straight RGBA8.
typedef RowSink = void Function(int y, Uint8List rgba);

/// Each row of [rgba] — straight, [width] × [height], row after row — handed
/// to [row] where it lies.
void eachRgbaRow(Uint8List rgba, int width, int height, RowSink row) {
  final stride = width * 4;
  for (var y = 0; y < height; y += 1) {
    row(y, Uint8List.sublistView(rgba, y * stride, (y + 1) * stride));
  }
}

/// [rgba] — straight, [width] × [height], row after row — cut into [cut]'s
/// tile blocks.
CutTiles cutRgbaRows(
  Uint8List rgba, {
  required int width,
  required int height,
  required TileCut cut,
}) => TileCutter.cutting(
  cut,
  width,
  (row) => eachRgbaRow(rgba, width, height, row),
);

/// Rows of a picture laid 1:1 ([TileCut]) written into tile blocks
/// ([TileBlocks]) as they arrive: the tiles of one tile row are open at a
/// time, a tile the picture left clear goes back as it closes, and a tile
/// of one colour closes as its word ([LaidPixels.keeping]).
final class TileCutter {
  TileCutter(this.cut, this.width)
    : _open = List.filled(cut.tiles.lastX - cut.tiles.firstX + 1, null);

  /// The tiles [feed] makes, handing its rows to a cutter of [cut] — every
  /// block it took given back when it throws.
  static CutTiles cutting(TileCut cut, int width, void Function(RowSink) feed) {
    final cutter = TileCutter(cut, width);
    try {
      feed(cutter.row);
      return cutter.finish();
    } on Object {
      cutter.giveBack();
      rethrow;
    }
  }

  final TileCut cut;
  final int width;

  final CutTiles _done = [];

  /// The blocks of the tile row under way, by column from the first —
  /// 🔬a map asked through a fresh closure for every row and tile was a
  /// fifth of an 8K picture's cut (2026-11-16).
  final List<({Pointer<Uint8> block, Uint8List view})?> _open;
  int? _openRow;

  int get _side => cut.tileSize;

  TileRange get _tiles => cut.tiles;

  void row(int y, Uint8List rgba) {
    final canvasY = cut.top + y;
    final tileY = floorDiv(canvasY, _side);
    if (tileY < _tiles.firstY || tileY > _tiles.lastY) {
      return;
    }
    if (_openRow != tileY) {
      _close();
      _openRow = tileY;
    }
    final inTile = canvasY - tileY * _side;
    final first = math.max(_tiles.firstX, floorDiv(cut.left, _side));
    final last = math.min(_tiles.lastX, floorDiv(cut.left + width - 1, _side));
    for (var tileX = first; tileX <= last; tileX += 1) {
      final from = math.max(tileX * _side, cut.left);
      final to = math.min(tileX * _side + _side, cut.left + width);
      final at = (inTile * _side + from - tileX * _side) * 4;
      _blockAt(tileX).view.setRange(
        at,
        at + (to - from) * 4,
        rgba,
        (from - cut.left) * 4,
      );
    }
  }

  ({Pointer<Uint8> block, Uint8List view}) _blockAt(int tileX) =>
      _open[tileX - _tiles.firstX] ??= _taken();

  /// A block of the lists, zeroed: a tile the rows leave part of is clear
  /// there, whatever the block held before.
  ({Pointer<Uint8> block, Uint8List view}) _taken() {
    final length = BitmapTile.bytesFor(_side);
    final block = TileBlocks.alloc(length);
    final view = block.asTypedList(length);
    zeroBytes(view);
    return (block: block, view: view);
  }

  void _close() {
    final tileY = _openRow;
    for (var column = 0; column < _open.length; column += 1) {
      final open = _open[column];
      if (open == null) {
        continue;
      }
      _open[column] = null;
      if (tileY != null && _anyInk(open.view)) {
        _done.add((
          x: _tiles.firstX + column,
          y: tileY,
          pixels: LaidPixels.keeping(open.block, open.view),
        ));
      } else {
        TileBlocks.free(open.block);
      }
    }
  }

  static bool _anyInk(Uint8List pixels) {
    for (var i = 3; i < pixels.length; i += 4) {
      if (pixels[i] != 0) {
        return true;
      }
    }
    return false;
  }

  /// The tiles the rows made: their blocks, to adopt ([laidCelOf]).
  CutTiles finish() {
    _close();
    return _done;
  }

  /// Every block taken, given back — a cut that failed part-way.
  void giveBack() {
    for (var column = 0; column < _open.length; column += 1) {
      if (_open[column] case final open?) {
        TileBlocks.free(open.block);
      }
      _open[column] = null;
    }
    giveBackCut(_done);
    _done.clear();
  }
}

/// Every block of [tiles] given back — a cut nobody will adopt.
void giveBackCut(CutTiles tiles) {
  for (final tile in tiles) {
    tile.pixels.giveBack();
  }
}
