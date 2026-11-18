import 'dart:math' as math;
import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_ground_color_mixing.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';

/// The cel's tiles' side.
const int _tileSize = 128;

/// A cel of [size] whose pixel at (x, y) is [argbAt]'s — a tile only where
/// one of its pixels holds anything, as a cel keeps them.
BitmapSurface aGroundOf(CanvasSize size, int Function(int x, int y) argbAt) {
  final tiles = <({TileCoord coord, BitmapTile tile})>[];
  for (var tileY = 0; tileY * _tileSize < size.height; tileY += 1) {
    for (var tileX = 0; tileX * _tileSize < size.width; tileX += 1) {
      final pixels = Uint8List(_tileSize * _tileSize * 4);
      var inked = false;
      for (var y = 0; y < _tileSize; y += 1) {
        for (var x = 0; x < _tileSize; x += 1) {
          final argb = argbAt(tileX * _tileSize + x, tileY * _tileSize + y);
          if (argb == 0) {
            continue;
          }
          inked = true;
          pixels.setAll((y * _tileSize + x) * 4, [
            (argb >> 16) & 0xFF,
            (argb >> 8) & 0xFF,
            argb & 0xFF,
            (argb >> 24) & 0xFF,
          ]);
        }
      }
      if (inked) {
        tiles.add((
          coord: TileCoord(x: tileX, y: tileY),
          tile: BitmapTile(size: _tileSize, pixels: pixels),
        ));
      }
    }
  }
  return BitmapSurface(canvasSize: size, tileSize: _tileSize).putTiles(tiles);
}

/// A mixing brush of [shape] drawing over [ground] as the canvas draws one:
/// its dabs made steps by its mixer, laid on the engine a batch at a time
/// as a pointer's moves come, and read back as pen-up bakes them
/// (`BrushLiveStrokeRasterizer.mixedAsResolved`).
final class AMixingStroke {
  AMixingStroke(BrushShape shape, {required this.ground, math.Random? random})
    : mixer = BrushGroundColorMixer(shape: shape, random: random),
      _rasterizer = BrushLiveStrokeRasterizer(
        pasteboard: ground.canvasSize.pasteboardAt(PasteboardReach.whole),
        tileSize: _tileSize,
      )..mixOver(ground);

  final BitmapSurface ground;
  final BrushGroundColorMixer mixer;
  final BrushLiveStrokeRasterizer _rasterizer;
  final List<BrushDab> _laid = [];

  /// [dabs], a batch, laid after the ones before: each as it lays its
  /// colour — with the copies [copied] makes of them once mixed, as
  /// symmetry and a second tip copy a stroke's dabs (`replicateDabs`).
  List<BrushDab> lay(
    List<BrushDab> dabs, {
    List<BrushDab> Function(List<BrushDab> mixed)? copied,
  }) {
    final from = _laid.length;
    final mixed = mixer.apply(dabs);
    _laid.addAll(copied == null ? mixed : copied(mixed));
    _rasterizer.blendFrom(_laid, from: from);
    return _rasterizer.mixedAsResolved(_laid).sublist(from);
  }

  /// Lets the stroke go.
  void end() => _rasterizer.clear();
}
