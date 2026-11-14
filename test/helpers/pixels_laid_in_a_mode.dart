import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart'
    show bitmapSurfaceRegionPixels;

/// [src] — straight RGBA, a pixel after another — laid in [mode] over
/// [dst], a cel's pixels as many, as the commit lays a stroke's buffer: one
/// row on the engine's grid, read back straight.
///
/// What a test of a blend's numbers holds them to — the road the app lays
/// a stroke by. ↩️Till 2026-11-14 they were held to the stroke blend
/// written in doubles beside it (`blendStrokeRegionPixels`), which the app
/// never ran (board `the-off-engine-cpu-commit-lives-only-for-tests`).
List<int> pixelsLaidInAMode(
  BrushBlendMode mode, {
  required List<int> src,
  required List<int> dst,
}) {
  const side = defaultCelTileSize;
  final count = src.length ~/ 4;
  if (dst.length != src.length || count > side) {
    throw ArgumentError('one row of as many cel pixels as stroke pixels');
  }
  final cel = BitmapSurface(
    canvasSize: const CanvasSize(width: side, height: side),
    tileSize: side,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: side,
        pixels: Uint8List(side * side * 4)..setAll(0, dst),
      ),
    },
  );
  final row = DirtyRegion(
    left: 0,
    top: 0,
    rightExclusive: count,
    bottomExclusive: 1,
  );
  final laid = compositeStrokePixelsOntoBitmapSurface(
    surface: cel,
    strokePixels: Uint8List.fromList(src),
    bounds: row,
    erase: mode == BrushBlendMode.erase,
    blendMode: mode,
  );
  return bitmapSurfaceRegionPixels(laid.surface, row);
}
