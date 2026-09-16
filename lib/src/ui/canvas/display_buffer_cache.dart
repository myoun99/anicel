import 'dart:async' show unawaited;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/rendering.dart';

/// What the live surface looked like, per coordinate: the overlay's tile
/// images, and the committed tiles' decoded images (or the tiles
/// themselves, until they decode). Identity per coordinate is what lets the
/// next paint say WHERE the surface changed — see
/// [DisplayBufferCache.keptTokens].
///
/// 🚨★★★F-130: AND THE STAMP'S GHOST. F-33 put the ghost inside the surface
/// painter's own draw, so the buffer holds it — and the buffer's KEY knew
/// (a hover was a miss) while its tokens did not (the miss could not say
/// where, and fell through to a full raster of the whole canvas, once per
/// pointer move: measured at 25 full composes for 25 moves). [ghost] is
/// the preview BY VALUE (its `==` is identity on the piece and the image,
/// value on the rect, the opacity and the blend — exactly what a hover
/// changes) beside the rect it covered, so the next paint can patch where
/// it was and where it is. A record rather than the preview's own type so
/// this file, which every canvas paint reads, does not import the brush
/// tool's.
typedef LiveSurfaceTokens = ({
  Map<Object, Object> overlay,
  Map<Object, Object> tiles,
  ({Object value, Rect rect})? ghost,
});

/// 🚨THE ONE SENTINEL for 「nothing was kept to measure from」 — a cold
/// start, or a buffer stored without a snapshot. Compared by IDENTITY
/// (`identical`), never by emptiness: an EMPTY cel's tokens are empty too,
/// and a stamp's usual target is an empty cel (F-130 — the ghost's patch
/// was refused on every move there, with the counter reading full).
const LiveSurfaceTokens noLiveSurfaceTokens = (
  overlay: {},
  tiles: {},
  ghost: null,
);

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

  /// Bytes this cache pins: THE WHOLE CHAIN, not just the kept image.
  ///
  /// 🔬**Counted because it is not small.** One buffer is the visible
  /// canvas at 1:1 — 33MB on a 4K view — and it is held for as long as
  /// nothing changes, which is most of the time. It was outside
  /// [collectMemoryCensus] until 2026-09-10, so the readout was short by a
  /// whole canvas per open view and nobody could see it.
  ///
  /// 🚨★★★IT USED TO ANSWER `_image` ALONE, AND THAT WAS A FALSE STATEMENT
  /// (2026-09-12). A derived buffer pins the one before it — see
  /// [_derivedDepth] — so this object can hold [_maxDerivedDepth] canvases
  /// while reporting one. The census is the app's only way to name a
  /// holder, so an under-reporting counter does not merely lose precision:
  /// it moves the bytes into 「엔진·폰트·프레임워크」, which is exactly where
  /// the user's screenshots found 10GB that nothing would own.
  int get heldBytes {
    final base = _realBase;
    return (_image == null ? 0 : _chainBytes) +
        (base == null ? 0 : base.width * base.height * 4);
  }

  ui.Image? _image;
  Rect? _rect;
  Object? _key;

  /// 🎯THE REAL BASE — what the next paint derives from, so that the
  /// deferred head is only ever DRAWN and never drawn FROM (유저 결정
  /// 2026-09-13: 「사슬을 없앤다 — 파생 베이스를 실체 이미지로」).
  ///
  /// A plain `toImage` snapshot of the picture that made a recent head:
  /// the same pixels, with NO recipe behind them, so a picture that draws
  /// it pins one real image and nothing else. Patching from it forms no
  /// chain — the head made from it references a real image, and releasing
  /// that head releases a structure one deep. The two budgets above stop
  /// being the mechanism and become the safety net for two windows: the
  /// paints before the first snapshot lands, and a raster thread that never
  /// answers (then the head is derived from, under budget, exactly as
  /// before).
  ///
  /// ⚠️It is as old as the paint whose picture it was made from, so the
  /// dirty rect measured against ITS tokens spans every paint since — two
  /// or three of a stroke's steps, which is the price of not chaining and
  /// is why the tokens travel with the image ([_realBaseTokens]).
  ///
  /// Kept with its OWN rect and static key: a landing after a pan is still
  /// a valid scroll base (the pixels are offset, not wrong), and a landing
  /// after the layer tree changed is not a base at all.
  ui.Image? _realBase;
  Rect? _realBaseRect;
  Object? _realBaseStaticKey;
  LiveSurfaceTokens _realBaseTokens = noLiveSurfaceTokens;

  /// Whether a snapshot is still on its way. ONE IN FLIGHT AT A TIME, and
  /// that is the cost decision: a snapshot is a whole extra raster pass,
  /// so the buffer does not start another until the last one has landed —
  /// on a GPU that answers within a frame that is every other paint, on a
  /// slower one fewer, and the base is correspondingly older. Better a
  /// larger dirty rect than a raster thread paying twice per paint.
  bool _promotionInFlight = false;

  /// Whether the next compose should also snapshot its picture.
  bool get wantsPromotion => !_promotionInFlight && !_disposed;

  /// How many snapshots landed and became the base. The counters' own
  /// law: a promotion that never lands looks exactly like one that works
  /// — the head would simply be derived from under budget, as before.
  int promotedCount = 0;

  bool _disposed = false;

  /// Offers [pending] — the snapshot of the picture that made the head just
  /// stored — as the next base. Describes it with what [store] just
  /// recorded (static key, rect, tokens): the two are one picture.
  void promote(Future<ui.Image> pending) {
    final staticKey = _staticKey;
    final rect = _rect;
    final tokens = keptTokens;
    _promotionInFlight = true;
    // Deliberately not awaited: the paint that started it is long over by
    // the time it lands, and the landing has nobody to report to but this
    // cache. Both arms below clear the slot, so a snapshot that fails frees
    // the next compose to ask again.
    unawaited(
      pending.then(
        (image) {
          _promotionInFlight = false;
          // ⛔A snapshot of a picture the layer tree has moved on from is
          // not a base for anything, and one that lands after dispose has
          // no owner. Either way it is released here, or it is a leak.
          if (_disposed || staticKey == null || staticKey != _staticKey) {
            image.dispose();
            return;
          }
          _realBase?.dispose();
          _realBase = image;
          _realBaseRect = rect;
          _realBaseStaticKey = staticKey;
          _realBaseTokens = tokens;
          promotedCount += 1;
          _tellHeldBytes();
        },
        onError: (Object _) {
          // A lost GPU context, a size the driver refused: the head stays
          // the base under budget, and the next compose asks again.
          _promotionInFlight = false;
        },
      ),
    );
  }

  /// What a base answers with: the image, the rect its pixels cover, the
  /// tokens to measure the dirty rect from, and whether drawing it forms a
  /// link ([deferred] — only the head does).
  ({ui.Image image, Rect rect, LiveSurfaceTokens tokens, bool deferred})?
  _realBaseFor(Object staticKey, {required bool Function(Rect was) fits}) {
    final base = _realBase;
    final was = _realBaseRect;
    if (base == null ||
        was == null ||
        _realBaseStaticKey != staticKey ||
        !fits(was)) {
      return null;
    }
    return (image: base, rect: was, tokens: _realBaseTokens, deferred: false);
  }

  /// The part of the key that does not move with the live surface, kept
  /// apart so a stroke step can still recognise its own previous frame.
  Object? _staticKey;

  /// What the live surface looked like WHEN THE KEPT IMAGE WAS MADE, so the
  /// next paint can say WHERE it changed since.
  ///
  /// 🚨Here rather than on the painter, and that is forced: a
  /// `CustomPainter` is a fresh object every frame, and a stroke step
  /// repaints WITHOUT a widget rebuild, so neither the painter nor `build`
  /// can hold a "since last time". This object is the only thing on that
  /// path that outlives a frame.
  ///
  /// 🚨★★★WRITTEN WITH THE IMAGE, IN [store], AND NOWHERE ELSE (F-68 ③,
  /// 2026-09-11). It used to be re-recorded on EVERY paint, including the
  /// paints that kept nothing — a floating selection makes the buffer
  /// uncacheable for the whole session — so after a lift (erase; float up;
  /// nothing kept) and a confirm (float gone; cacheable again) the patch
  /// base was the image from BEFORE the lift while the dirty rect was only
  /// what the confirm changed: the erased ring came back from the old
  /// buffer and stayed until something else repainted it. On every
  /// platform, because this is the buffer and not the tiles. A snapshot
  /// describes exactly one image, and it lives and dies with it.
  ///
  /// Overlay coordinate → the tile IMAGE it held, so the next paint can
  /// say which tiles a dab actually touched. A bare coordinate SET here
  /// made every step dirty the whole stroke's bounding box — the overlay
  /// accumulates for the stroke's life, so membership alone says "part of
  /// the stroke", not "changed since last paint".
  LiveSurfaceTokens keptTokens = noLiveSurfaceTokens;


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
  /// from nothing — which is exactly how many canvases the kept image
  /// pins, because NOTHING ELSE EVER LETS ONE GO.
  ///
  /// 🚨★★★THE ENGINE FACT THIS CLASS IS BUILT ON, READ FROM ITS SOURCE
  /// (2026-09-13, Flutter 3.44.2 / engine 77e2e94772,
  /// `lib/ui/painting/display_list_deferred_image_gpu_skia.cc`):
  /// `toImageSync` hands back a `DlDeferredImageGPUSkia` whose
  /// `ImageWrapper` keeps the picture's display list in `display_list_`
  /// FOR THE IMAGE'S WHOLE LIFE. `SnapshotDisplayList` rasterizes it and
  /// keeps it — there is no `reset()` anywhere in that file — because
  /// `OnGrContextCreated` re-runs the snapshot when the GPU context is lost
  /// and rebuilt, and the list is the only recipe it has. And the list
  /// holds an `sk_sp<DlImage>` for every image it draws
  /// (`DrawImageOp.image`, `dl_op_records.h`). `rasterPicture` states the
  /// law for every caller; this class is where it bites hardest.
  ///
  /// So a buffer drawn FROM the kept one holds the kept one for as long as
  /// it lives, that one holds the one before it, and the chain is exactly
  /// as long as the run of derived stores since the last compose that
  /// started from nothing. Rasterization does not shorten it. A frame
  /// reaching the screen does not shorten it. Only releasing the head does
  /// — and then the whole run goes at once, recursively, on the raster
  /// thread: `~DisplayList → DisposeOps → ~DlDeferredImageGPUSkia →
  /// ~ImageWrapper → ~DisplayList`, ~850 bytes of stack a link against a
  /// 2MB stack. 2026-09-09 the app died there at ~2,470 links (guard-page
  /// violation 0x80000001, read from the dump with WinDbg; board card
  /// `app-crash-stack-overflow-in-engine` has the walk).
  ///
  /// ⛔TWO THINGS WERE WRITTEN HERE THAT WERE FALSE, AND BOTH COST THE USER
  /// (2026-09-12: 544MB → 17GB in two minutes of drawing):
  /// · "the chain costs almost nothing resident — a display list is
  ///   small". The list is small; what it holds is not. Every link pins a
  ///   whole canvas of pixels.
  /// · "the count is reset by the one event that collapses the chain — a
  ///   frame finishing rasterization". No event collapses it. This counter
  ///   was zeroed on every `FrameTiming`, so the link budget below never
  ///   once fired during ordinary drawing and the chain was unbounded:
  ///   2,048 links of a 1920×1080 canvas is 17GB, and switching layers
  ///   invalidated the head and gave it all back in one event, which is
  ///   the user's own "레이어를 바꾸면 풀린다".
  ///
  /// 🔬Measured in `drawing_does_not_grow_the_footprint_test.dart`: on a
  /// 1200×1200 view (5.76MB a buffer) the footprint climbs
  /// 106·207·308·409·511MB in a straight line until a budget forces a full
  /// compose, and the peak is a LINEAR function of the budget.
  int _derivedDepth = 0;

  /// The most links allowed before the next compose has to start from
  /// nothing — THE STACK BUDGET. 128 links ≈ 110KB of the raster thread's
  /// 2MB, a twentieth of what it took to die. ⛔Raising the thread's stack
  /// is not the alternative: the chain has no length of its own to be
  /// under.
  static const int _maxDerivedDepth = 128;

  /// Bytes the chain pins right now: every image from the kept one back to
  /// the last compose that started from nothing.
  ///
  /// 🚨★★★MAINTAINED IN [store] AND NOWHERE ELSE, beside [_derivedDepth],
  /// because they are the SAME EVENT counted in two units, and reset by the
  /// same two events — a fresh store, an [invalidate] — because those are
  /// the only two that release anything. A field touched anywhere else
  /// would be a second answer to "how deep is the chain".
  int _chainBytes = 0;

  /// The most the chain may pin before the next compose has to start from
  /// nothing — THE MEMORY BUDGET.
  ///
  /// 🚨★★★THE TWO BUDGETS ARE THE ONLY THING THAT EVER COLLAPSES A CHAIN.
  /// A chain has two costs — the raster thread's stack and memory — so it
  /// has two budgets, and whichever binds first forces the full compose
  /// that lets the whole run go. 128 links was chosen against a 2MB stack
  /// with no thought for the bytes each link pins, which is how a stroke
  /// came to cost a gigabyte (see [_derivedDepth]). Since the real base
  /// ([_realBase], 2026-09-13) a chain forms only in the paints before the
  /// first snapshot lands, or when the raster thread never answers — so in
  /// ordinary drawing these never bind, and they are what stands when it
  /// is not ordinary.
  ///
  /// ⛔ABSOLUTE, NOT A MULTIPLE OF THE CANVAS: a big canvas must not be
  /// allowed to pin proportionally more, because the machine it has to run
  /// on is the same one (구형 기기 방침). 64MB is ~44 links of a 600×600
  /// view, ~11 of 1200×1200, ~8 of 1920×1080, ~2 of 4K — so during a
  /// stroke a 1920×1080 canvas pays one full compose in eight paints and a
  /// 4K one pays one in three.
  ///
  /// ⚠️THE FIRST DERIVATION IS ALWAYS ALLOWED, whatever the canvas costs:
  /// this budget bounds ACCUMULATION, and at depth 0 there is none.
  /// Without that a canvas whose ONE image exceeds the budget could never
  /// patch at all — the optimisation would switch itself off exactly where
  /// it is worth most.
  static const int _maxChainBytes = 64 << 20;

  /// Whether the kept image may be drawn into the next one at all. Both
  /// doors below ask it, so neither can forget either budget.
  bool get _mayDeriveAgain =>
      _derivedDepth == 0 ||
      (_derivedDepth < _maxDerivedDepth && _chainBytes < _maxChainBytes);

  /// How deep the chain is right now. Probe surface: the geometry field
  /// probe prints it beside the compose counters, because "the budget
  /// stopped firing" and "the budget fires on every paint" are both
  /// regressions a hands-on report has to be able to show.
  int get derivedDepth => _derivedDepth;

  /// The dirty rect the last compose was confined to (canvas space, after
  /// the hairline inflate); null when the compose was full. Probe surface
  /// like the counters: a patch that quietly grows back to the stroke's
  /// whole bounding box is invisible in `patchedCount` — it still counts
  /// as one patch — and THIS is what says how big that patch really was.
  Rect? lastDirtyRect;

  /// Probe: the level ([displayLevelOf]) the last stored buffer was
  /// composed at — 0 at canvas resolution. A level path that silently stops
  /// running looks exactly like one that works (the counters' own law), and
  /// this is what says which level a paint actually composed at.
  int? lastBufferLevel;

  /// [patched] and [derived] are two questions, deliberately two flags.
  /// [patched] is the PROBE — "did the patch path run" — and a scrolled
  /// carry answers it false. [derived] is what the two budgets above
  /// count — "did this picture draw the DEFERRED head", the one draw that
  /// forms a link: a carry from the head answers true, a patch from the
  /// real base answers false even though it patched. One flag for both
  /// would let a pan build the chain unwatched.
  ///
  /// [tokens] is what the live surface looked like as [image] was made —
  /// what a later paint measures its dirty rect from. Null when that could
  /// not be said, and then nothing is kept to measure from: the next paint
  /// composites whole, which is the honest price of an image nobody can
  /// describe.
  void store(
    Object key,
    Object staticKey,
    Rect rect,
    ui.Image image, {
    bool patched = false,
    bool derived = false,
    LiveSurfaceTokens? tokens,
  }) {
    if (patched) {
      patchedCount += 1;
    } else {
      fullCount += 1;
    }
    _derivedDepth = derived ? _derivedDepth + 1 : 0;
    // The same event in the other unit. A compose that started from
    // nothing pins exactly its own image; a derived one pins that on top
    // of everything the chain already held.
    final imageBytes = image.width * image.height * 4;
    _chainBytes = derived ? _chainBytes + imageBytes : imageBytes;
    if (!identical(_image, image)) {
      _image?.dispose();
    }
    _image = image;
    _rect = rect;
    _key = key;
    _staticKey = staticKey;
    keptTokens = tokens ?? noLiveSurfaceTokens;
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
  ///
  /// 🎯THE REAL BASE FIRST, whenever it fits — it forms no chain. The head
  /// only when there is no real base yet, and then under both budgets.
  ({ui.Image image, Rect rect, LiveSurfaceTokens tokens, bool deferred})?
  patchBaseFor(Object staticKey, Rect rect) {
    final real = _realBaseFor(staticKey, fits: (was) => was == rect);
    if (real != null) {
      return real;
    }
    final image = _image;
    if (image == null || _staticKey != staticKey || _rect != rect) {
      return null;
    }
    if (!_mayDeriveAgain) {
      return null;
    }
    return (image: image, rect: rect, tokens: keptTokens, deferred: true);
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
  ({ui.Image image, Rect rect, LiveSurfaceTokens tokens, bool deferred})?
  scrollBaseFor(Object staticKey, Rect rect) {
    bool carries(Rect was) {
      if (was == rect) {
        // Not moved: that is [patchBaseFor]'s case, and it knows more.
        return false;
      }
      final overlap = was.intersect(rect);
      return !overlap.isEmpty && overlap.width > 0 && overlap.height > 0;
    }

    final real = _realBaseFor(staticKey, fits: carries);
    if (real != null) {
      return real;
    }
    final image = _image;
    final was = _rect;
    if (image == null || was == null || _staticKey != staticKey) {
      return null;
    }
    if (!_mayDeriveAgain || !carries(was)) {
      return null;
    }
    return (image: image, rect: was, tokens: keptTokens, deferred: true);
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
    _chainBytes = 0;
    // ⛔The snapshot goes with the image. Kept across an invalidate it would
    // describe a frame nobody holds any more, and the next paint would
    // "find" a small dirty rect against a base that no longer exists.
    keptTokens = noLiveSurfaceTokens;
    // And the real base goes with it, for the same reason: an invalidate
    // says the old pixels are wrong everywhere, whichever image holds them.
    // A snapshot still in flight lands on a changed static key and is
    // released by [promote]'s own check.
    _realBase?.dispose();
    _realBase = null;
    _realBaseRect = null;
    _realBaseStaticKey = null;
    _realBaseTokens = noLiveSurfaceTokens;
    _tellHeldBytes();
  }

  void dispose() {
    _disposed = true;
    invalidate();
  }

  /// Whether anything is kept — the seam a cost test reads.
  @visibleForTesting
  bool get isWarm => _image != null;
}
