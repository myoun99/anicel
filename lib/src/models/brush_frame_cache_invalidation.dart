import 'brush_frame_key.dart';
import 'dirty_tile_set.dart';

/// Lightweight brush-frame cache/storage invalidation event.
///
/// This identifies the brush source frame that changed so future derived
/// preview/playback/renderer caches can be rebuilt from BrushFrameStore data.
/// It intentionally carries only dirty metadata, not cache images or bitmap
/// source payloads.
///
/// 🪦From 2026-09-11 to 2026-09-17 it also carried the two surfaces the
/// change went between (F-68), so the display side could compose a
/// truthful stand-in for each changed tile before its decode landed. A
/// tile pictures itself inside the paint now, so nothing composes and
/// nothing needs the pair — and a record kept for the life of a host no
/// longer holds two whole surfaces alive through it.
class BrushFrameCacheInvalidation {
  const BrushFrameCacheInvalidation({
    required this.frameKey,
    this.dirtyTiles,
    this.wholeFrame = false,
  });

  factory BrushFrameCacheInvalidation.wholeFrame(BrushFrameKey frameKey) {
    return BrushFrameCacheInvalidation(frameKey: frameKey, wholeFrame: true);
  }

  final BrushFrameKey frameKey;
  final DirtyTileSet? dirtyTiles;
  final bool wholeFrame;

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
      'dirtyTiles: $dirtyTiles, wholeFrame: $wholeFrame)';
}
