import 'dart:math' as math;

import '../../services/memory_pressure_budget.dart';
import '../../services/playback/frame_demand.dart';
import 'cut_frame_composite_cache.dart';
import 'layer_frame_image_cache.dart';

/// Playback render-cache policy constants (single source of truth).
///
/// Combined GPU-image byte budget across the layer-frame and cut-composite
/// caches. A cut's picture is the canvas's own size — ~15.5 MB for a
/// 2340×1654 canvas — so a whole cut can approach the budget by itself.
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
/// Composites are the playback hot path, so they claim the budget first —
/// letting go, when it is full, of the ones wanted latest
/// ([FrameDemand]) — and the layer-frame images shrink into whatever
/// remains.
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

  /// [lentBytes] is what a borrower holds on this line — an export run's
  /// row pictures (F-289-Q21) — and comes off the caches' share first:
  /// they give way to it, and take it back when it is lent no more.
  ///
  /// [demand] is the order pictures are wanted in: under a full budget the
  /// composites wanted latest go first. Without one the least recently used
  /// do.
  void enforce({
    FrameDemand? demand,
    int reservedForDisplayBytes = 0,
    int lentBytes = 0,
  }) {
    // ⚠️Half, and no more: a 500-layer stack asks for gigabytes, and a
    // reserve that big would starve the warm to buy cache nothing can hold
    // anyway. Past the clamp the layer cache's own LRU decides which of the
    // stack stays, which is the right answer to "more than fits".
    final reserve = reservedForDisplayBytes.clamp(0, maxBytes ~/ 2);
    composites.enforceBudget(
      maxBytes: maxBytes - reserve - lentBytes,
      stepOf: demand?.stepOf,
      // The picture under the playhead stays whatever the cap: it is as
      // good as on a screen — the one about to be shown, made a moment
      // before any view could pin it.
      laterThan: demand == null ? null : 0,
    );
    final remaining = maxBytes - lentBytes - composites.estimatedBytes;
    layerImages.evictLeastRecentlyUsed(
      targetBytes: remaining < reserve ? reserve : remaining,
    );
  }

  /// The bytes the composites may hold while pictures are being MADE: the
  /// line, less what is lent, what a screen's layer images reserve, and the
  /// layer images the picture composed last was made of
  /// ([CutFrameCompositeCache.lastComposeLayerBytes]).
  ///
  /// ⚠️That last share is the maker's alone — [enforce] does not take it
  /// off. A full window that left the layer images no room would rebuild
  /// the background for every picture it made; a window that is not being
  /// added to has no use for them.
  int roomForComposites({int reservedForDisplayBytes = 0, int lentBytes = 0}) {
    final layers =
        (reservedForDisplayBytes + composites.lastComposeLayerBytes).clamp(
          0,
          maxBytes ~/ 2,
        );
    return math.max(0, maxBytes - lentBytes - layers);
  }

  /// Makes room among the composites for one more of [bytes], wanted [step]
  /// frames on, by letting go of composites wanted LATER than it — never of
  /// one wanted sooner, nor of one a screen shows. False when that leaves
  /// no room: what is held is the window.
  bool makeRoomFor({
    required int bytes,
    required int step,
    FrameDemand? demand,
    int reservedForDisplayBytes = 0,
    int lentBytes = 0,
  }) => composites.enforceBudget(
    maxBytes:
        roomForComposites(
          reservedForDisplayBytes: reservedForDisplayBytes,
          lentBytes: lentBytes,
        ) -
        bytes,
    stepOf: demand?.stepOf,
    laterThan: step,
  );

  /// How much of the line a borrower may hold: all of it, less what
  /// [enforce] never takes back — the composites and the layer images a
  /// screen shows. ↩️The composites of a kept RANGE came off it too, while
  /// there was one (see [CutFrameCompositeCache.enforceBudget]).
  int lendableBytes() => math.max(
    0,
    maxBytes - composites.pinnedBytes - layerImages.pinnedBytes,
  );
}
