import 'bitmap_surface.dart';
import 'dirty_tile_set.dart';

/// One committed stroke's surface transition (R19 P3b surface-snapshot
/// undo): the immutable pre/post surfaces ARE the undo payload — holding
/// both references retains only the stroke's changed tiles (structural
/// sharing), and a chain of strokes shares each link (post(n) is
/// identical to pre(n+1)).
class BrushStrokeCommitOutcome {
  const BrushStrokeCommitOutcome({
    required this.preSurface,
    required this.postSurface,
    required this.dirtyTiles,
  });

  final BitmapSurface preSurface;
  final BitmapSurface postSurface;
  final DirtyTileSet dirtyTiles;

  /// The approximate bytes this outcome UNIQUELY retains on an undo
  /// stack: the changed tiles' pre-images (everything else is shared
  /// with neighbouring entries or the live surface).
  int get estimatedRetainedBytes =>
      dirtyTiles.length * preSurface.tileBytes;
}
