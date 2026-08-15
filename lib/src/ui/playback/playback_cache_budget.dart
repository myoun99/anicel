import '../../models/playback_quality.dart';
import 'cut_frame_composite_cache.dart';
import 'layer_frame_image_cache.dart';

/// Playback render-cache policy constants (single source of truth).
///
/// Half is the default playback quality, like the Premiere/AE monitors:
/// full-resolution frames of a 2340×1654 canvas cost ~15.5 MB each, so a
/// whole cut at Full can approach the budget by itself.
const PlaybackQuality defaultPlaybackQuality = PlaybackQuality.half;

/// Combined GPU-image byte budget across the layer-frame and cut-composite
/// caches.
const int playbackCacheBudgetBytes = 600 * 1024 * 1024;

/// Estimated GPU bytes of an RGBA image of the given dimensions.
int estimatedImageBytes(int width, int height) => width * height * 4;

/// Keeps the two playback caches inside one combined byte budget.
///
/// Composites are the playback hot path, so they claim the budget first
/// (never evicting the protected playing range) and the layer-frame images
/// shrink into whatever remains.
///
/// 🚨★★★ WHAT IS ON SCREEN RESERVES ITS OWN PIXELS FIRST.
///
/// That ordering rested on 「the layer-frame images are cheap to rebuild
/// when needed again」, and #26 retired it: a ruler scrub shows the EDITING
/// canvas now, and the editing canvas IS the layer-frame images. They
/// stopped being a disposable intermediate the moment they became the
/// picture.
///
/// ⛔The old code read as if recency covered this — 「what is on screen was
/// just touched, so it survives its own trim」. It does not: a warm run that
/// fills the budget with composites drives the remainder to ZERO, and
/// [LayerFrameImageCache.evictLeastRecentlyUsed] at a target of zero drops
/// every entry, most-recent included. So the harder the warm worked, the
/// emptier the scrub's own cache got — measured by the user, who raised
/// playback quality to Full (4× the composite bytes) and watched the scrub
/// get SLOWER to fill in.
///
/// ★[reservedForDisplayBytes] is the floor the trim may not go under, and
/// it comes off the composites' claim rather than being taken back
/// afterwards — a floor applied after the fact would evict and immediately
/// rebuild the same images. Pass 0 while playing: the composite IS the
/// screen then, and this reserve would be holding pixels nobody looks at.
class PlaybackCacheBudgetEnforcer {
  const PlaybackCacheBudgetEnforcer({
    required this.layerImages,
    required this.composites,
    this.maxBytes = playbackCacheBudgetBytes,
  });

  final LayerFrameImageCache layerImages;
  final CutFrameCompositeCache composites;
  final int maxBytes;

  void enforce({
    List<PlaybackProtectedRange> protect = const [],
    int reservedForDisplayBytes = 0,
  }) {
    // ⚠️Half, and no more: a 500-layer stack asks for gigabytes, and a
    // reserve that big would starve the warm to buy cache nothing can hold
    // anyway. Past the clamp the layer cache's own LRU decides which of the
    // stack stays, which is the right answer to "more than fits".
    final reserve = reservedForDisplayBytes.clamp(0, maxBytes ~/ 2);
    composites.enforceBudget(maxBytes: maxBytes - reserve, protect: protect);
    final remaining = maxBytes - composites.estimatedBytes;
    layerImages.evictLeastRecentlyUsed(
      targetBytes: remaining < reserve ? reserve : remaining,
    );
  }
}
