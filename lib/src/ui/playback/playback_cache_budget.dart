import 'dart:math' as math;

import '../../services/memory_pressure_budget.dart';
import 'layer_frame_image_cache.dart';

/// Playback render-cache policy constants (single source of truth).
///
/// The byte budget of the canvas's row images, every screen's pictures
/// (the playback cache). A row's picture is at most the canvas's own size —
/// ~15.5 MB for a 2340×1654 canvas.
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

/// Keeps the playback cache — the canvas's row images, the pictures every
/// screen shows a frame from — inside its byte budget, letting go of the
/// ones wanted latest ([CanvasPictures.wantedAt]: 「허용치 = 레이어 그림 수요
/// 순서」).
///
/// ⛔No display reserve: what a screen holds is pinned, and a pin is never
/// let go of — and what the walk wants next is in the same order as what
/// it shows, so a floor beside the order would only keep pictures it ranks
/// last.
///
/// ↩️It kept two caches in one budget until 2026-10-10 — a composite of
/// each of the film's frames beside the row images the canvas holds, the
/// composites claiming the line first — and the composites went
/// (playback-plays-the-screen-material: the film is drawn from the row
/// images too).
class PlaybackCacheBudgetEnforcer {
  PlaybackCacheBudgetEnforcer({
    required this.layerImages,
    int maxBytes = playbackCacheBudgetBytes,
  }) : _budget = MemoryPressureBudget.halving(
         normal: maxBytes,
         floor: playbackCacheBudgetUnderPressureBytes,
       );

  final LayerFrameImageCache layerImages;

  /// The cap in force — [playbackCacheBudgetBytes] until the OS warns. The
  /// lowers-only rule is [MemoryPressureBudget]'s, shared with the cel
  /// store, the undo stack and the media viewer.
  final MemoryPressureBudget _budget;

  int get maxBytes => _budget.bytes;

  /// A new normal — the memory tab's allowance ([CacheBudgets.playback]).
  set maxBytes(int value) => _budget.bytes = value;

  /// The OS said memory is tight: halve the budget, floored at
  /// [playbackCacheBudgetUnderPressureBytes]. Answers whether it moved.
  ///
  /// ⚠️Lowering alone frees nothing — the caller runs [enforce] after, the
  /// way the cel store cools after halving.
  bool respondToMemoryPressure() => _budget.respondToMemoryPressure();

  /// [lentBytes] is what a borrower holds on this line — an export run's
  /// row pictures (F-289-Q21) — and comes off the cache's share first: it
  /// gives way to it, and takes it back when it is lent no more.
  ///
  /// [wantedAt] is when each image is next shown: the ones wanted latest go
  /// first. The rows of the frame under the playhead stay whatever the cap.
  void enforce({required LayerImageWantedAt wantedAt, int lentBytes = 0}) {
    layerImages.enforceBudget(
      maxBytes: room(lentBytes: lentBytes),
      wantedAt: wantedAt,
      laterThan: 0,
    );
  }

  /// The bytes the images may hold while they are being made: the line,
  /// less what is lent.
  int room({int lentBytes = 0}) => math.max(0, maxBytes - lentBytes);

  /// Makes room for one more picture of [bytes], wanted [step] frames on,
  /// [within] the bytes the images may hold ([room]) — by letting go of
  /// images wanted LATER than it, never of one wanted sooner, nor of one a
  /// screen shows. False when that leaves no room: what is held is the
  /// window.
  bool makeRoomFor({
    required int bytes,
    required int step,
    required int within,
    required LayerImageWantedAt wantedAt,
  }) => layerImages.enforceBudget(
    maxBytes: within - bytes,
    wantedAt: wantedAt,
    laterThan: step,
  );

  /// How much of the line a borrower may hold: all of it, less what
  /// [enforce] never takes back — the images a screen shows.
  int lendableBytes() => math.max(0, maxBytes - layerImages.pinnedBytes);
}
