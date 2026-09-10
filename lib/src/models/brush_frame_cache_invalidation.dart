import 'bitmap_surface.dart';
import 'brush_frame_key.dart';
import 'dirty_tile_set.dart';

/// The two surfaces a change went between — one value, because they are
/// only ever meaningful together (a "before" with no "after" says nothing
/// about what any tile became).
typedef SurfaceTransition = ({BitmapSurface before, BitmapSurface after});

/// Lightweight brush-frame cache/storage invalidation event.
///
/// This identifies the brush source frame that changed so future derived
/// preview/playback/renderer caches can be rebuilt from BrushFrameStore data.
/// It intentionally carries only dirty metadata, not cache images or bitmap
/// source payloads.
///
/// 🚨★★★AND THE TRANSITION THE CHANGE WENT THROUGH, when the emitter has
/// it (F-68 root fix, 2026-09-11). A commit is the ONE moment anything
/// knows both the tile a coordinate held and the tile it holds now. The
/// display side needs exactly that pair to give the new tile a truthful
/// picture before its decode lands — and every surface replacement in the
/// app reaches this record through two funnels, so carrying the pair here
/// is what makes that picture impossible to forget on a new path. Not a
/// payload copy: surfaces are immutable and shared by reference.
///
/// ⛔Not part of equality. Equality names WHICH change was announced;
/// the transition is what it went between, and two announcements of the
/// same dirty set are the same announcement whichever objects carried it.
class BrushFrameCacheInvalidation {
  const BrushFrameCacheInvalidation({
    required this.frameKey,
    this.dirtyTiles,
    this.wholeFrame = false,
    this.transition,
  });

  factory BrushFrameCacheInvalidation.wholeFrame(BrushFrameKey frameKey) {
    return BrushFrameCacheInvalidation(frameKey: frameKey, wholeFrame: true);
  }

  final BrushFrameKey frameKey;
  final DirtyTileSet? dirtyTiles;
  final bool wholeFrame;

  /// The cel's surface before and after the change, or null when the
  /// emitter did not have both (a raster import has no "before").
  final SurfaceTransition? transition;

  bool get hasDirtyTiles => dirtyTiles != null && dirtyTiles!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushFrameCacheInvalidation &&
          other.frameKey == frameKey &&
          other.dirtyTiles == dirtyTiles &&
          other.wholeFrame == wholeFrame;

  @override
  int get hashCode => Object.hash(frameKey, dirtyTiles, wholeFrame);

  @override
  String toString() =>
      'BrushFrameCacheInvalidation(frameKey: $frameKey, '
      'dirtyTiles: $dirtyTiles, wholeFrame: $wholeFrame, '
      'transition: ${transition == null ? 'none' : 'carried'})';
}
