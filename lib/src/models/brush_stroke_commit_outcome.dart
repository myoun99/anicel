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

  /// 🪦An `estimatedRetainedBytes` used to sit here forwarding to
  /// [BitmapSurface.bytesNotSharedWith]. It was a SECOND statement of the
  /// undo-weight law — the pair it passed was the only thing it added,
  /// and the entry that holds this outcome now names that pair itself
  /// (`UndoSurfaceSnapshot`, which has to know it anyway to spill).
}
