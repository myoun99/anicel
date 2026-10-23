import 'dart:math' as math;
import 'dart:typed_data';

import 'package:anicel/src/core/rgba_premultiply.dart';
import 'package:anicel/src/models/bitmap_surface.dart';

/// What a canvas-sized picture of [surface] holds, as an image reads back
/// (`ImageByteFormat.rawRgba`, premultiplied): each tile's own bytes where
/// the tile stands, cropped to the canvas — a pasteboard tile past an edge
/// is not on it — premultiplied by the app's one law
/// ([premultipliedRgbaCopy]).
///
/// ⛔A test's own reckoning, not the compose's road: no region read through
/// `bitmapSurfaceRegionPixels`, which the compose's pictures are made of —
/// a reference walking that road agrees with any mistake on it.
/// ↩️It was the app's CPU assembly (`bitmapSurfaceToImage`), which nothing
/// in the app had called since 09-09 (card `cpu-assembly-has-no-caller`).
Uint8List premultipliedCanvasBytes(BitmapSurface surface) {
  final width = surface.canvasSize.width;
  final height = surface.canvasSize.height;
  final canvas = Uint8List(width * height * 4);
  for (final MapEntry(key: coord, value: tile) in surface.tiles.entries) {
    final pixels = premultipliedRgbaCopy(tile.pixels);
    final left = coord.x * tile.size;
    final top = coord.y * tile.size;
    final fromX = math.max(0, -left);
    final toX = math.min(tile.size, width - left);
    final fromY = math.max(0, -top);
    final toY = math.min(tile.size, height - top);
    for (var y = fromY; y < toY && fromX < toX; y += 1) {
      final at = ((top + y) * width + left + fromX) * 4;
      canvas.setRange(
        at,
        at + (toX - fromX) * 4,
        pixels,
        (y * tile.size + fromX) * 4,
      );
    }
  }
  return canvas;
}
