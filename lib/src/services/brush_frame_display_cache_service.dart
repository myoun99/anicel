import '../models/bitmap_surface.dart';
import '../models/brush_frame_display_cache.dart';
import '../models/brush_frame_key.dart';
import '../models/canvas_size.dart';
import 'brush_frame_store.dart';

/// Coordinates explicit, non-pointer-move preview cache rebuilds.
///
/// R19 P3b: with the baked raster as the sole truth (no command replay),
/// a "rebuild" is a reference reseed — the valid cache, else the baked
/// surface, else a blank surface for an empty cel.
class BrushFrameDisplayCacheService {
  const BrushFrameDisplayCacheService({
    required this.frameStore,
    required this.canvasSize,
    this.tileSize = 256,
  });

  final BrushFrameStore frameStore;
  final CanvasSize canvasSize;
  final int tileSize;

  BrushFrameDisplayCache prepareFramePreview(BrushFrameKey key) {
    frameStore.getOrCreateFrame(key);
    final existing = frameStore.displayCacheOrNull(key);
    if (existing != null &&
        existing.isValid &&
        existing.previewSurface.canvasSize == canvasSize) {
      return existing;
    }

    final current = frameStore.currentSurfaceWithoutReplay(
      key,
      canvasSize: canvasSize,
    );
    if (current == null && frameStore.celHasRenderableContent(key)) {
      // 🚨A MISS, not an empty cel. The pixels exist in some tier at a
      // DIFFERENT canvas size, and the blank stand-in below would be
      // stored as a VALID cache — so the layer composites fully
      // transparent AND STAYS THAT WAY, because a valid cache is exactly
      // what stops anyone looking again. The row reads as "never loaded"
      // for the rest of the session while its artwork sits in the store.
      //
      // Hand back a DIRTY cache instead. This frame paints nothing either
      // way, but nothing is cached as the answer, so the next attempt
      // gets to try again — a resize reseed, the open heal, or the cel
      // materializing at the size it was actually recorded at.
      return BrushFrameDisplayCache(
        frameKey: key,
        previewSurface: BitmapSurface(
          canvasSize: canvasSize,
          tileSize: tileSize,
        ),
        sourceRevision: frameStore.getOrCreateFrame(key).sourceRevision,
        dirty: true,
      );
    }
    final surface =
        current ?? BitmapSurface(canvasSize: canvasSize, tileSize: tileSize);
    return frameStore.storeRebuiltDisplayCache(
      key: key,
      previewSurface: surface,
    );
  }
}
