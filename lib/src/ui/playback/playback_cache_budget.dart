import '../../models/playback_quality.dart';
import '../../services/memory_pressure_budget.dart';
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

/// 🚨WHERE PRESSURE PUTS IT — and until 2026-08-30 the answer was
/// "nowhere", which made this the LARGEST cache in the app and the only
/// one that never stood down.
///
/// `respondToMemoryPressure` did call [PlaybackCacheBudgetEnforcer.enforce],
/// and the session's comment said the playback caches "re-run their budget
/// against the shrunken world" — but nothing shrank their world. They
/// re-applied the same 600MB while the cel store halved beside them.
///
/// ⚠️Four frames, derived from the number this file already states: a
/// full-resolution 2340×1654 frame costs ~15.5MB, so 64MB is roughly four
/// of them. Below that a scrub around the playhead rebuilds every frame it
/// touches, and the cache has stopped being a cache.
///
/// ⛔Not a device-class check, and not a rescaling of the 600MB either:
/// what a desktop holds when memory is FINE is unchanged, because that
/// number was measured and this one is only about the warning.
const int playbackCacheBudgetUnderPressureBytes = 64 * 1024 * 1024;

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
  PlaybackCacheBudgetEnforcer({
    required this.layerImages,
    required this.composites,
    int maxBytes = playbackCacheBudgetBytes,
  }) : _budget = MemoryPressureBudget.halving(
         normal: maxBytes,
         floor: playbackCacheBudgetUnderPressureBytes,
       );

  final LayerFrameImageCache layerImages;
  final CutFrameCompositeCache composites;

  /// The combined cap in force — [playbackCacheBudgetBytes] until the OS
  /// warns. The lowers-only rule is [MemoryPressureBudget]'s, shared with
  /// the cel store, the undo stack and the media viewer.
  final MemoryPressureBudget _budget;

  int get maxBytes => _budget.bytes;

  /// A new normal — the memory tab's allowance ([CacheBudgets.playback]).
  set maxBytes(int value) => _budget.bytes = value;

  /// The OS said memory is tight: halve the combined budget, floored at
  /// [playbackCacheBudgetUnderPressureBytes]. Answers whether it moved.
  ///
  /// ⚠️Lowering alone frees nothing — the caller runs [enforce] after, the
  /// way the cel store cools after halving.
  bool respondToMemoryPressure() => _budget.respondToMemoryPressure();

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
