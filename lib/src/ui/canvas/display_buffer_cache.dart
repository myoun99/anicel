import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';

/// 🚨★★★ (v) — THE COMPOSITE BUFFER, KEPT WHILE NOTHING HAS CHANGED.
///
/// The single buffer made sampling a property of the display: everything
/// composites at canvas resolution and the finished image is resampled
/// ONCE. What it did not do was remember: every paint rasterised the whole
/// visible rect again, including the paints where nothing had moved — a
/// hover, a cursor blink, a neighbouring panel's rebuild.
///
/// ⛔A MISS COSTS EXACTLY WHAT TODAY COSTS, and that is the property that
/// makes this safe to try. The tiled buffer that came before it failed on
/// the other side of that line: a cold tile cache rasterised the composite
/// once PER TILE, so the thing meant to make strokes cheap made panning N
/// times dearer, and it had to be reverted. One image cannot do that —
/// worst case it does the work the untiled path already did.
///
/// ⚠️It also cannot go stale silently in a small way: if the key misses
/// something, the whole canvas freezes rather than one corner of it, which
/// is the failure everybody notices in the first second.
class DisplayBufferCache {
  /// Told whenever [heldBytes] changes, so an owner that the memory census
  /// CAN reach is able to report a buffer that lives in a widget State.
  ///
  /// ⚠️A callback rather than the census reading this object: the census
  /// pulls from holders the session owns, and a canvas view is not one —
  /// the same reason the media viewers push
  /// ([RenderCaches.viewerRasterBytesByViewer]).
  void Function(int bytes)? onHeldBytesChanged;

  void _tellHeldBytes() => onHeldBytesChanged?.call(heldBytes);

  /// Bytes the kept buffer holds: one canvas-resolution RGBA image, or
  /// none.
  ///
  /// 🔬**Counted because it is not small.** One buffer is the visible
  /// canvas at 1:1 — 33MB on a 4K view — and it is held for as long as
  /// nothing changes, which is most of the time. It was outside
  /// [collectMemoryCensus] until 2026-09-10, so the readout was short by a
  /// whole canvas per open view and nobody could see it.
  int get heldBytes {
    final image = _image;
    return image == null ? 0 : image.width * image.height * 4;
  }

  ui.Image? _image;
  Rect? _rect;
  Object? _key;

  /// The part of the key that does not move with the live surface, kept
  /// apart so a stroke step can still recognise its own previous frame.
  Object? _staticKey;

  /// What the live surface looked like when the kept image was made, so the
  /// next paint can say WHERE it changed.
  ///
  /// 🚨Here rather than on the painter, and that is forced: a
  /// `CustomPainter` is a fresh object every frame, and a stroke step
  /// repaints WITHOUT a widget rebuild, so neither the painter nor `build`
  /// can hold a "since last time". This object is the only thing on that
  /// path that outlives a frame.
  /// Overlay coordinate → the tile IMAGE it held, so the next paint can
  /// say which tiles a dab actually touched. A bare coordinate SET here
  /// made every step dirty the whole stroke's bounding box — the overlay
  /// accumulates for the stroke's life, so membership alone says "part of
  /// the stroke", not "changed since last paint".
  Map<Object, Object> lastOverlayTokens = const {};
  Map<Object, Object> lastTileTokens = const {};


  /// The kept image for [key] over [rect], or null when there is none.
  ui.Image? imageFor(Object key, Rect rect) {
    if (_key == key && _rect == rect) {
      return _image;
    }
    return null;
  }

  /// Keeps [image] as the answer for [key] over [rect], dropping whatever
  /// was there.
  ///
  /// [staticKey] is the part of [key] that does NOT move with the live
  /// surface: the layer tree, the viewport, the paper. Keeping it apart is
  /// what makes [patchBaseFor] possible — a stroke step changes the live
  /// half and nothing else, and that is the one case where the previous
  /// image is still worth something.
  /// How many stored images were built by PATCHING the previous one, and
  /// how many were composited from nothing.
  ///
  /// 🚨A counter rather than an argument about the design: an optimisation
  /// that never runs looks exactly like one that works, and this session
  /// shipped two that did not (a tile grid whose key never matched, and a
  /// walk that hashed every tile and still missed). The test asserts the
  /// SECOND stroke step patches — if the dirty rect stops being found, this
  /// number says so instead of the frame rate saying it later.
  ///
  /// Not test-only: the geometry field probe reports both in RELEASE
  /// builds (behind the Input Inspector toggle), because "the patch path
  /// stopped running" is precisely the regression a hands-on report needs
  /// to be able to show.
  int patchedCount = 0;
  int fullCount = 0;

  /// How many stores IN A ROW were drawn from the kept image instead of
  /// from nothing.
  ///
  /// 🚨★★★A STACK BUDGET, NOT A CACHE STATISTIC — and the reason this
  /// class refuses to hand its image out forever.
  ///
  /// `toImageSync` returns an image that is NOT rasterized yet, and the
  /// engine keeps the display list that would draw it
  /// (`DlDeferredImageGPUSkia::ImageWrapper` holds an `sk_sp<DisplayList>`)
  /// until the raster thread gets to it. So a buffer drawn from the kept
  /// one RETAINS it, and the next buffer retains that: derive N times with
  /// no rasterization in between and the chain is N long. It costs almost
  /// nothing resident — a display list is small — which is exactly why
  /// nothing noticed.
  ///
  /// ⛔RELEASING THAT CHAIN IS RECURSIVE, IN THE ENGINE, ON THE RASTER
  /// THREAD: `~DisplayList → DisposeOps → ~DlDeferredImageGPUSkia →
  /// ~ImageWrapper → ~DisplayList`, ~850 bytes of stack per link against a
  /// 2MB stack. 2026-09-09 the app died there with no frame of ours
  /// anywhere on the stack — ~2,470 links, guard-page violation
  /// (0x80000001). Read from the dump with WinDbg; board card
  /// `app-crash-stack-overflow-in-engine` has the walk.
  ///
  /// 🎯THE COUNT IS RESET BY THE ONE EVENT THAT COLLAPSES THE CHAIN — a
  /// frame finishing RASTERIZATION. Drawing the newest buffer snapshots it,
  /// which releases its display list, which releases the buffer before it,
  /// all the way down: the crash landed inside `Rasterizer::DrawToSurfaces`
  /// for exactly that reason. So "derivations since the last rasterized
  /// frame" is not an approximation of the chain — it IS the chain.
  ///
  /// [FrameTiming] reports only frames that were rasterized, which is
  /// precisely the signal wanted: a burst of composes with no frame drawn
  /// in between (an offscreen bake, a raster thread left behind) produces
  /// no timing, so the count keeps climbing and the budget below fires.
  int _derivedDepth = 0;

  /// The most derivations allowed before the next compose has to start
  /// from nothing.
  ///
  /// 128 links ≈ 110KB of the raster thread's 2MB — a twentieth of what it
  /// took to die — and at 60fps an unbroken stroke pays one full compose
  /// about every two seconds. ⛔Raising the thread's stack is not the
  /// alternative: the chain has no length of its own to be under.
  static const int _maxDerivedDepth = 128;

  /// Whether the kept image may be drawn into the next one at all. Both
  /// doors below ask it, so neither can forget the budget.
  bool get _mayDeriveAgain => _derivedDepth < _maxDerivedDepth;

  /// The deepest the chain has ever been this session.
  ///
  /// 🚨★★★THE ONE THING THE CRASH DUMP COULD NOT SAY. It proved WHAT
  /// collapsed (the chain, inside `Rasterizer::DrawToSurfaces`) and HOW BIG
  /// it was (~2,470 links × 848 bytes = the whole 2MB stack), but not how
  /// 2,470 derivations happened with no frame reaching the screen in
  /// between — the heap is not in a WER dump, so the objects could not be
  /// read. The frame pipeline throttles the UI thread, so ordinary
  /// per-frame painting cannot produce that number: something paints the
  /// canvas WITHOUT a frame being drawn. Which something is not known.
  ///
  /// So it is measured instead of argued (the counters' own law). In
  /// normal use this stays at 1–2. Anything above [_deepDeriveSuspicion]
  /// means a burst of composes the screen never saw, and
  /// [debugFirstDeepDerive] then holds the stack that was doing it.
  int maxDerivedDepth = 0;

  /// Far above the 1–2 of ordinary painting, far below the budget — so it
  /// fires on the real thing and never on a frame that ran long.
  static const int _deepDeriveSuspicion = 16;

  /// Who was composing when the chain first went deep. Debug builds only:
  /// the capture is the point, and it costs a stack walk.
  ///
  /// ⚠️Recorded ONCE. The tenth caller is the same as the first, and a
  /// field that keeps being overwritten is a field that says whatever
  /// happened last.
  StackTrace? debugFirstDeepDerive;

  void _noteDepth() {
    if (_derivedDepth > maxDerivedDepth) {
      maxDerivedDepth = _derivedDepth;
    }
    assert(() {
      if (_derivedDepth == _deepDeriveSuspicion &&
          debugFirstDeepDerive == null) {
        debugFirstDeepDerive = StackTrace.current;
      }
      return true;
    }());
  }

  /// A frame reached the screen: every deferred image it drew has been
  /// snapshotted, so the chain behind the kept buffer is gone.
  ///
  /// ⚠️Called for frames that RASTERIZED, never for work that only painted
  /// — that difference is the whole point.
  void noteFrameRasterized() {
    _derivedDepth = 0;
  }

  bool _watchingFrames = false;

  /// Subscribes to raster completions the first time anything derives.
  ///
  /// ⚠️Lazily, and never in a bare unit test: `SchedulerBinding.instance`
  /// throws without a binding, and there are no frames there to reset on
  /// anyway — the same shape [DeferredImageDisposer.retire] uses.
  void _watchRasterizedFrames() {
    if (_watchingFrames) {
      return;
    }
    final SchedulerBinding binding;
    try {
      binding = SchedulerBinding.instance;
    } on Object catch (_) {
      return;
    }
    _watchingFrames = true;
    binding.addTimingsCallback(_onFramesRasterized);
  }

  void _onFramesRasterized(List<FrameTiming> timings) => noteFrameRasterized();

  /// The generation count itself, for the test that pins the budget.
  @visibleForTesting
  int get debugDerivedDepth => _derivedDepth;

  /// The dirty rect the last compose was confined to (canvas space, after
  /// the hairline inflate); null when the compose was full. Probe surface
  /// like the counters: a patch that quietly grows back to the stroke's
  /// whole bounding box is invisible in `patchedCount` — it still counts
  /// as one patch — and THIS is what says how big that patch really was.
  Rect? lastDirtyRect;

  /// ⓔ 5단계 probe: the resolved scale of the last SCALED (below-knee)
  /// store. The s=1 path never touches it — it answers "when the knee
  /// path last ran, what s did it run at", because a scaled path that
  /// silently stops running looks exactly like one that works (the
  /// counters' own law).
  double? lastBufferScale;

  /// [patched] and [derived] are two questions, deliberately two flags.
  /// [patched] is the PROBE — "did the patch path run" — and a scrolled
  /// carry answers it false. [derived] is the STACK BUDGET above: a carry
  /// draws the kept image too, so it answers true. One flag for both would
  /// let a pan build the chain unwatched.
  void store(
    Object key,
    Object staticKey,
    Rect rect,
    ui.Image image, {
    bool patched = false,
    bool derived = false,
  }) {
    if (patched) {
      patchedCount += 1;
    } else {
      fullCount += 1;
    }
    _derivedDepth = derived ? _derivedDepth + 1 : 0;
    if (derived) {
      _noteDepth();
      _watchRasterizedFrames();
    }
    if (!identical(_image, image)) {
      _image?.dispose();
    }
    _image = image;
    _rect = rect;
    _key = key;
    _staticKey = staticKey;
    _tellHeldBytes();
  }

  /// The previous image, when the only thing that moved since is the LIVE
  /// surface — so redrawing the dirty part over it is the same picture as
  /// compositing the whole thing again.
  ///
  /// 🚨★★★THIS IS WHAT REPLACED THE TILE GRID. Tiling split the buffer to
  /// avoid recompositing all of it per stroke step; it also gave every
  /// boundary a seam at fractional scale, and made a cold cache cost N
  /// rasters instead of one. Patching the whole buffer keeps the ONE image
  /// (so there is no boundary to seam) and the cold path is untouched (so
  /// the worst case is still today's) — the recomposite is confined to the
  /// dirty rect either way, which was the only thing tiles were for.
  ///
  /// ⛔Null unless [staticKey] AND [rect] both match: a changed layer tree
  /// or a moved viewport means the old pixels are wrong everywhere, not
  /// just where the stroke went.
  ({ui.Image image, Rect rect})? patchBaseFor(Object staticKey, Rect rect) {
    final image = _image;
    if (image == null || _staticKey != staticKey || _rect != rect) {
      return null;
    }
    if (!_mayDeriveAgain) {
      return null;
    }
    return (image: image, rect: rect);
  }

  /// The kept image and the rect it ALREADY covers, when the extent has
  /// MOVED but the content behind it has not — a pan, or a zoom that slid
  /// the window over the same picture.
  ///
  /// 🚨★★★A PAN CARRIES WHAT IT ALREADY HAD. [patchBaseFor] refuses a moved
  /// rect, because for a stroke step a moved rect means the old pixels are
  /// in the wrong place. They are not WRONG, though — they are OFFSET. The
  /// buffer is canvas resolution, so one buffer pixel is one canvas pixel at
  /// every zoom, and the overlap can be blitted to its new home exactly.
  /// What is left to composite is the band the pan exposed.
  ///
  /// ⛔ONE IMAGE STILL. The blit and the band land in the SAME recorder and
  /// come out as one `toImageSync` — there is no second image at paint time,
  /// so there is no boundary for a fractional scale to seam (which is what
  /// the tile grid was rejected for, and what a base-plus-patch draw would
  /// bring back).
  ///
  /// ⚠️THE LIVE SURFACE IS NOT IN [staticKey] ON PURPOSE, so the carried
  /// pixels can hold a stale live layer. The caller composites the live
  /// dirty rect along with the exposed band, and must refuse the carry when
  /// it cannot say where the live surface changed.
  ({ui.Image image, Rect rect})? scrollBaseFor(Object staticKey, Rect rect) {
    final image = _image;
    final was = _rect;
    if (image == null || was == null || _staticKey != staticKey) {
      return null;
    }
    if (!_mayDeriveAgain) {
      return null;
    }
    if (was == rect) {
      // Not moved: that is [patchBaseFor]'s case, and it knows more.
      return null;
    }
    final overlap = was.intersect(rect);
    if (overlap.isEmpty || overlap.width <= 0 || overlap.height <= 0) {
      return null;
    }
    return (image: image, rect: was);
  }

  /// How many stores carried a moved buffer instead of compositing it whole.
  ///
  /// 🚨The counters' own law: an optimisation that never runs looks exactly
  /// like one that works.
  int scrolledCount = 0;

  /// The canvas-space AREA the last carry actually composited.
  ///
  /// 🚨THE COUNTER SAYS THE CARRY RAN; THIS SAYS IT SAVED SOMETHING. A carry
  /// that blits the overlap and then composites the whole rect anyway is
  /// correct, costs what it always did, and is invisible in every pixel test
  /// — 🧪a mutation shipped exactly that and stayed green.
  double? lastComposedArea;

  void invalidate() {
    _image?.dispose();
    _image = null;
    _rect = null;
    _key = null;
    _staticKey = null;
    // Nothing is kept, so nothing can be derived FROM: the next store
    // starts a new chain whatever it is.
    _derivedDepth = 0;
    // ⛔The snapshots go with the image. Kept across an invalidate they would
    // describe a frame nobody holds any more, and the next paint would
    // "find" a small dirty rect against a base that no longer exists.
    lastOverlayTokens = const {};
    lastTileTokens = const {};
    _tellHeldBytes();
  }

  void dispose() {
    if (_watchingFrames) {
      _watchingFrames = false;
      // The binding outlives this cache; a callback left on it would keep
      // the object alive and go on resetting a counter nobody reads.
      SchedulerBinding.instance.removeTimingsCallback(_onFramesRasterized);
    }
    invalidate();
  }

  /// Whether anything is kept — the seam a cost test reads.
  @visibleForTesting
  bool get isWarm => _image != null;
}
