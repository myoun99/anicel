import 'dart:ui' show Rect;

import '../../models/bitmap_surface.dart';
import '../../models/dirty_region.dart';
import '../../models/tiles_covering.dart';

/// Every EXISTING tile under a canvas-space [rect]: the floor/ceil hull of
/// the rect handed to [tilesCovering], so a fractional edge still reaches
/// the tile it touches. The surface paint pass (the visible rect, per
/// frame) and the provisional ink pictures (the float's own rect, per
/// commit) both walk this — per TILE, never per pixel.
///
/// An empty rect covers nothing: [DirtyRegion] refuses an empty span
/// where the double range this replaced silently iterated zero times.
Iterable<CoveredTile> tilesUnderRect(BitmapSurface surface, Rect rect) {
  if (rect.isEmpty) {
    return const [];
  }
  return tilesCovering(
    surface,
    DirtyRegion(
      left: rect.left.floor(),
      top: rect.top.floor(),
      rightExclusive: rect.right.ceil(),
      bottomExclusive: rect.bottom.ceil(),
    ),
  );
}
