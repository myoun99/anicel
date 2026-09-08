import 'bitmap_surface.dart';
import 'brush_frame_key.dart';

/// Derived bitmap preview for displaying a brush frame without replaying all
/// source paint commands in scrub/inactive display paths.
///
/// This cache is rebuildable from BrushFrameDrawingState source commands and is
/// never the source of truth for artwork.
///
/// 🪦It used to carry a `dirtyTiles` set beside [dirty], so a repaint could
/// have redrawn only the tiles that went stale. Nothing ever read it — the
/// cache is valid or it is not ([isValid]), and the tile-granular answer
/// travels a different road entirely (`BrushFrameCacheInvalidation`, which
/// has readers). A set that is unioned into and never asked is not a
/// half-built optimisation, it is a place for two writers to disagree.
class BrushFrameDisplayCache {
  BrushFrameDisplayCache({
    required this.frameKey,
    required this.previewSurface,
    required this.sourceRevision,
    this.dirty = false,
  });

  final BrushFrameKey frameKey;
  final BitmapSurface previewSurface;
  final int sourceRevision;
  final bool dirty;

  bool get isValid => !dirty;

  BrushFrameDisplayCache copyWith({
    BitmapSurface? previewSurface,
    int? sourceRevision,
    bool? dirty,
  }) {
    return BrushFrameDisplayCache(
      frameKey: frameKey,
      previewSurface: previewSurface ?? this.previewSurface,
      sourceRevision: sourceRevision ?? this.sourceRevision,
      dirty: dirty ?? this.dirty,
    );
  }
}
