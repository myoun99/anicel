import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';

/// A tile of the side the app cuts its cels in ([defaultCelTileSize]), its
/// bytes as [paint] leaves them — they start transparent.
///
/// 🚨THE APP'S SIDE, NEVER A TEST'S OWN: the engine stores tiles of that
/// side alone and refuses a cel of another (`_refuseOtherGrids`,
/// aeec8c6e3) the moment a frame on it is drawn or weighed ahead. Tests of
/// the timeline's paste, trade and link built their cels at 256 or 8, each
/// its own way, and stayed green only while the engine had not opened yet
/// — CI's Linux opened it within a file and the synced-row trade went red
/// (run 44754294330, 11-21); opened first, eleven files went red.
BitmapTile aTileOfTheAppsSide(void Function(Uint8List bytes) paint) {
  const side = defaultCelTileSize;
  final bytes = Uint8List(side * side * 4);
  paint(bytes);
  return BitmapTile(size: side, pixels: bytes);
}

/// A cel's picture at [canvasSize]: one tile, at its corner
/// ([aTileOfTheAppsSide]), its bytes as [paint] leaves them.
BitmapSurface aCelOfOneTile(
  CanvasSize canvasSize,
  void Function(Uint8List bytes) paint,
) => BitmapSurface(
  canvasSize: canvasSize,
  tiles: {TileCoord(x: 0, y: 0): aTileOfTheAppsSide(paint)},
);

/// [aCelOfOneTile] with every pixel of its tile [rgba].
BitmapSurface aCelFilled(CanvasSize canvasSize, List<int> rgba) =>
    aCelOfOneTile(canvasSize, (bytes) {
      for (var at = 0; at < bytes.length; at += 4) {
        bytes.setRange(at, at + 4, rgba);
      }
    });
