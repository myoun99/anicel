import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/rgba_image_bytes.dart';
import 'dart:ui' as ui;

import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/layer_effect.dart';
import '../../models/playback_quality.dart';
import '../../models/tile_coord.dart';
import '../../services/brush_frame_display_cache_service.dart';
import '../../services/playback/let_go_wanted_latest.dart';
import '../../services/brush_frame_store.dart';
import '../../services/cel_source_effect_pass.dart';
import '../../services/cel_surface_as_shown.dart';
import '../canvas/bitmap_tile_image_cache.dart';
import '../../core/dev_profile.dart';
import '../canvas/deferred_image_disposal.dart';
import '../canvas/layer_image_draw.dart';
import '../canvas/level_image.dart';
import '../canvas/raster_picture.dart';
import '../canvas/tiled_surface_compose.dart';
import '../quiet_turns.dart' show QuietTurn, QuietTurns;
import '../../core/pin_counts.dart';

/// One cached layer-frame render: the image, the CANVAS-SPACE rect its
/// pixels cover, and the rect the whole content image covers.
///
/// [extent] is the content: the canvas rect, grown by any pasteboard tiles so
/// the editing stack can show them. [worldRect] is the same rect — or, for a
/// row whose route draws its ink alone exactly (`inkCropDrawsTheSame`), just
/// the part that holds the ink, every pixel of [extent] outside it being
/// transparent. `drawPosedLayerImage` takes both, and lays the whole image
/// back whenever a draw needs it.
class LayerFrameImage {
  LayerFrameImage({
    required this.image,
    required this.worldRect,
    required this.extent,
    this.madeFrom = const {},
    Object? content,
  }) : content = content ?? Object();

  final ui.Image image;
  final ui.Rect worldRect;
  final ui.Rect extent;

  /// What each coordinate showed when these pixels were composed — the tile
  /// OBJECT at every coordinate the surface held (no entry: nothing there).
  ///
  /// It is how a painter that draws the same cel from its tiles can tell
  /// that a part of this image is still what those tiles show: a tile is
  /// never edited in place, a changed coordinate holds a new object. The
  /// active row below 100% draws the level it was handed from here instead
  /// of making it again ([TilePyramid.seed]).
  final Map<TileCoord, Object> madeFrom;

  /// Whether this is the ink alone rather than the whole content image.
  bool get isInk => worldRect != extent;

  /// What these PIXELS are — a new token for every compose, and the SAME
  /// token on the plain snapshot that later takes a deferred image's place
  /// ([LayerFrameImageCache._settleWhenTheSnapshotLands]: 「same pixels,
  /// same validity」).
  ///
  /// 🚨★★★That sentence used to live only in a comment, so a holder could
  /// not tell a settle from a recompose — and treated it as one. 🔬Measured
  /// 2026-09-23 (the F-130 `solo` arm, 24 drawn rows): the row a LAYER
  /// SELECT drops out of the active slot is composed in the build, settles
  /// one frame later, and the editing stack took the swap as a new picture
  /// — the whole display buffer rastered a SECOND time, for pixels it
  /// already had (229ms of 520 in the test VM's software raster).
  final Object content;
}

class _LayerFrameImageEntry {
  _LayerFrameImageEntry({
    required this.positioned,
    required this.sourceRevision,
    required this.canvasSize,
    required this.sourceEffectSignature,
    required this.lastUsed,
  });

  /// The stable per-entry wrapper — cache hits return the SAME instance,
  /// so `identical` remains a valid hit oracle for consumers and tests.
  final LayerFrameImage positioned;
  final int sourceRevision;
  final CanvasSize canvasSize;

  /// The VALUES of the color keys this image was built with.
  ///
  /// 🚨PART OF VALIDITY, NOT A HINT. The pixels of a keyed cel are not the
  /// cel's pixels, and `sourceRevision` cannot see that — it moves when the
  /// DRAWING changes, and a Tolerance edit changes no drawing at all. Left
  /// out, dragging Tolerance would serve the image built at the old value
  /// for ever ([[derived-cel-projection-pattern]]: a content-addressed cache
  /// that misses a field does not read stale, it MERGES two pictures).
  final List<double> sourceEffectSignature;

  int lastUsed;

  /// Pending while this entry holds a DEFERRED image — one the synchronous
  /// road made ([LayerFrameImageCache.prepareSyncOrNull]) — and completes
  /// when the plain snapshot of the same picture has taken the entry's
  /// place, or could not be had. Null for an entry that was a snapshot from
  /// the start.
  ///
  /// ⚠️A deferred image is a recipe that pins every tile picture it drew
  /// for as long as it lives (`raster_picture.dart`), so it is only ever
  /// the picture of the frame that needed it NOW: [prepare] waits here and
  /// answers with the snapshot, which is what a holder keeps.
  Future<void>? settling;

  ui.Image get image => positioned.image;
}

/// What a picture is made of, as an ask says it: the content's revision,
/// the canvas, the chain baked in, and whether its ink alone is kept.
typedef _MadeOf = ({
  int revision,
  CanvasSize canvasSize,
  List<double> sourceEffectSignature,
  bool inkSuffices,
});

/// A picture being made for a slot, and what it is being made of: the ask
/// that started it.
final class _Making {
  _Making(this.madeOf, this.done);

  final _MadeOf madeOf;
  final Future<LayerFrameImage?> done;

  /// Whether this making answers [ask] — the same picture of the same
  /// content, kept the same way. An ask the making does not answer makes its
  /// own.
  bool answers(_MadeOf ask) =>
      ask.revision == madeOf.revision &&
      ask.canvasSize == madeOf.canvasSize &&
      sameCelSourceEffectSignature(
        ask.sourceEffectSignature,
        madeOf.sourceEffectSignature,
      ) &&
      ask.inkSuffices == madeOf.inkSuffices;
}

/// 🚨A PICTURE IS MADE ONCE: the pictures being made, by slot
/// ([LayerFrameImageCache.prepare]). Asked for while the same picture is
/// being made, a slot waits for that making instead of making it again
/// beside it — the canvas and the warm both make rows, and a frame asks for
/// its rows at once, so two makings of one cel side by side were the
/// ordinary case (a-picture-is-made-once, 2026-10-10).
final class _Makings {
  final Map<(BrushFrameKey, PlaybackQuality), _Making> _bySlot = {};

  /// [make]'s picture for [slot] — or, while a making there answers
  /// [madeOf], that one's. A making stands down only for the ask that
  /// started it: an ask that did not want to stand down ([shouldAbort]) and
  /// got nothing from it is made again.
  Future<LayerFrameImage?> once(
    (BrushFrameKey, PlaybackQuality) slot,
    _MadeOf madeOf, {
    required bool Function()? shouldAbort,
    required Future<LayerFrameImage?> Function() make,
  }) async {
    final making = _bySlot[slot];
    if (making != null && making.answers(madeOf)) {
      final made = await making.done;
      if (made != null || (shouldAbort?.call() ?? false)) {
        return made;
      }
    }
    final now = _Making(madeOf, make());
    _bySlot[slot] = now;
    try {
      return await now.done;
    } finally {
      if (identical(_bySlot[slot], now)) {
        _bySlot.remove(slot);
      }
    }
  }
}

/// How many steps on a cached slot's image is next shown — null where no
/// frame ahead shows it ([LayerFrameImageCache.enforceBudget]).
typedef LayerImageWantedAt =
    int? Function((BrushFrameKey, PlaybackQuality) slot);

/// Level-1 playback cache: one GPU [ui.Image] per (layer frame, quality),
/// built from the brush store's display-cache surface (the first production
/// consumer of [BrushFrameDisplayCacheService]).
///
/// Validity is revision-based: an entry is valid iff its stored
/// `sourceRevision` (and canvas size) still match the store's current
/// drawing state, so brush edits and undo/redo invalidate without any event
/// plumbing. [invalidateFrame] additionally drops entries eagerly on sink
/// events to free memory sooner.
class LayerFrameImageCache {
  LayerFrameImageCache({required this.frameStore}) {
    frameStore.addRekeyListener(_travelWithTheirCels);
  }

  final BrushFrameStore frameStore;
  final Map<(BrushFrameKey, PlaybackQuality), _LayerFrameImageEntry> _entries =
      {};
  int _useCounter = 0;

  /// Test hatch: keep every image whole, as the cache did before it stored a
  /// row's ink alone — what the byte-for-byte pins render the ink against
  /// (`a_cropped_cel_draws_the_same_bytes_test`).
  @visibleForTesting
  bool debugStoresWholeContent = false;

  /// The cached image when it still matches the frame's current source
  /// revision, [canvasSize] and [sourceEffects]; `null` on miss or staleness.
  ///
  /// [sourceEffects] is the row's chain — the CPU half of it is baked into
  /// the image this returns. ⛔REQUIRED, with no default, deliberately: the
  /// same reason `drawPosedLayerImage` requires its filter quality. A
  /// default would let a new caller inherit "no keys" silently and serve
  /// unkeyed pixels next to keyed ones, which is precisely the split this
  /// argument exists to close. Pass `const []` where the row has no chain.
  ///
  /// Whole or the ink alone — [LayerFrameImage.isInk] says which; the two
  /// prepares hand out only what the asking route can draw.
  LayerFrameImage? validImageOrNull(
    BrushFrameKey key,
    PlaybackQuality quality, {
    required CanvasSize canvasSize,
    required List<ResolvedLayerEffect> sourceEffects,
  }) {
    final entry = _validEntry(key, quality, canvasSize, sourceEffects);
    if (entry == null) {
      return null;
    }
    entry.lastUsed = ++_useCounter;
    return entry.positioned;
  }

  /// The image [prepareSyncOrNull] would hand a route drawing [key]'s row
  /// at [quality] from what is held ALREADY — without counting as a use.
  ///
  /// ⛔A LOOK, NOT A USE: what asks it is counting pictures — the warmer
  /// walking a window, the ruler's bar, a run asking whether it may go on —
  /// and a count that touched every row it read would make each one the
  /// most recently used, which is the order the budget lets go by.
  LayerFrameImage? peek(
    BrushFrameKey key,
    PlaybackQuality quality, {
    required CanvasSize canvasSize,
    required List<ResolvedLayerEffect> sourceEffects,
    required bool inkSuffices,
  }) => _drawable(
    _validEntry(key, quality, canvasSize, sourceEffects)?.positioned,
    inkSuffices: inkSuffices,
  );

  _LayerFrameImageEntry? _validEntry(
    BrushFrameKey key,
    PlaybackQuality quality,
    CanvasSize canvasSize,
    List<ResolvedLayerEffect> sourceEffects,
  ) {
    final entry = _entries[(key, quality)];
    if (entry == null ||
        entry.canvasSize != canvasSize ||
        !sameCelSourceEffectSignature(
          entry.sourceEffectSignature,
          celSourceEffectSignature(sourceEffects),
        ) ||
        entry.sourceRevision != _currentRevision(key)) {
      return null;
    }
    return entry;
  }

  /// Returns a valid image, rebuilding it when missing or stale. `null` when
  /// the frame has no drawn content — or, with [shouldAbort] (the warm path,
  /// R13-4), when the build was abandoned mid-way: aborts cache nothing and
  /// the abort checks bracket the two big slices (the cel's thaw and each
  /// tile picture [composePositionedSurfaceImage] makes).
  ///
  /// [inkSuffices] is whether the route draws this row exactly from its ink
  /// alone (`inkCropDrawsTheSame`): an image is stored as its ink only then,
  /// and one stored so is handed out only then. False is the safe answer,
  /// not the lazy one — the whole image draws right on every route, and all
  /// the default costs a caller that forgets is the memory the ink would
  /// have saved.
  ///
  /// [turn] is what the making waits for before it puts its work on the GPU
  /// — its turn in the quiet between a run's held frames ([QuietTurns]);
  /// none where null (the editing canvas's own). No turn stands the making
  /// down, as [shouldAbort] does.
  ///
  /// 🚨A PICTURE IS MADE ONCE ([_Makings]).
  Future<LayerFrameImage?> prepare({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
    required List<ResolvedLayerEffect> sourceEffects,
    bool Function()? shouldAbort,
    bool inkSuffices = false,
    Future<QuietTurn?> Function()? turn,
  }) => _makings.once(
    (key, quality),
    (
      revision: _currentRevision(key),
      canvasSize: canvasSize,
      sourceEffectSignature: celSourceEffectSignature(sourceEffects),
      inkSuffices: inkSuffices,
    ),
    shouldAbort: shouldAbort,
    make: () => _prepareNow(
      key: key,
      canvasSize: canvasSize,
      quality: quality,
      sourceEffects: sourceEffects,
      shouldAbort: shouldAbort,
      inkSuffices: inkSuffices,
      turn: turn,
    ),
  );

  final _Makings _makings = _Makings();

  Future<LayerFrameImage?> _prepareNow({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
    required List<ResolvedLayerEffect> sourceEffects,
    bool Function()? shouldAbort,
    bool inkSuffices = false,
    Future<QuietTurn?> Function()? turn,
  }) async {
    final cached = _drawable(
      validImageOrNull(
        key,
        quality,
        canvasSize: canvasSize,
        sourceEffects: sourceEffects,
      ),
      inkSuffices: inkSuffices,
    );
    if (cached != null) {
      // A deferred image is the picture of the frame that needed it, not
      // one to keep ([_LayerFrameImageEntry.settling]): wait for the
      // snapshot that replaces it and answer with that.
      final settling = _entries[(key, quality)]?.settling;
      if (settling == null) {
        return cached;
      }
      await settling;
      final settled = _drawable(
        validImageOrNull(
          key,
          quality,
          canvasSize: canvasSize,
          sourceEffects: sourceEffects,
        ),
        inkSuffices: inkSuffices,
      );
      if (settled != null) {
        return settled;
      }
      // The cel moved on while the snapshot was out: build it like any miss.
    }

    // 🚨A CEL STILL COLD, OR STILL IN THE FILE, IS THAWED AHEAD — OFF THE UI
    // THREAD ([BrushFrameStore.thawAhead], card cel-thaw-holds-the-ui-thread):
    // inflated and laid into its tiles on a worker, and read below once it
    // is hot. 🔬Read here instead, a cel held the UI thread 16–19 ms (line
    // art at 1920×1080), and a cut's first play 60–70 ms at a time (I-57,
    // 2026-10-15). Waited for before the content and the revision are
    // read, so an edit made while it thaws is what they see; never STARTED
    // when the editor just went hot.
    if (shouldAbort?.call() ?? false) {
      return null;
    }
    await frameStore.thawAhead(key, canvasSize: canvasSize);

    // Content oracle, not a command check (R19 P3a): an OPENED cel's
    // picture is its baked raster and carries no commands at all — the
    // old command-emptiness guard blanked every loaded cel in playback.
    // ↩️It asked for the cel's drawing state too, the commands' old holder:
    // a cel donated without one — a layer's cels forked by an unlink, an
    // independent clip's copies — had its pixels and no picture (found
    // 2026-10-10, when the whole film came to be drawn here). A cel no
    // edit has touched is at revision 0.
    if (!frameStore.celHasRenderableContent(key)) {
      _dropEntry((key, quality));
      return null;
    }
    final revision = _currentRevision(key);

    // What the worker did not thaw — a thaw that failed, a cel cooled again
    // since — is read and inflated inside this call, the one slice on this
    // path nothing can stand down (🔬1.4–17 ms a cel on the Windows app,
    // 2026-10-07 — board F-296): never START it when the editor just went
    // hot.
    // 🪦It said 「the display-cache replay … grows with the cel's stroke
    // count」 until then; no stroke has been replayed since the baked raster
    // became the cel (R19 P3b, `BrushFrameDisplayCacheService`).
    if (shouldAbort?.call() ?? false) {
      return null;
    }
    final previewCache = BrushFrameDisplayCacheService(
      frameStore: frameStore,
      canvasSize: canvasSize,
    ).prepareFramePreview(key);
    if (!previewCache.isValid) {
      // A cel that HAS pixels, recorded at another canvas size. Composing
      // the blank stand-in and banking it here under [revision] is what
      // makes the row stay blank: the revision does not move when a heal
      // repairs the size, so the empty image is served for ever after.
      // No image this pass, nothing remembered, next pass gets to look.
      return null;
    }
    // ★THE COLOR KEYS RUN HERE, on the CPU, before a single byte is
    // uploaded. This is the editing canvas's half of the seam: the composite
    // plan applies them in `CutFrameCompositeLayer`'s constructor, but the
    // editing stack does not go through that plan at all — it asks this
    // cache for an image by frame key. Both call the SAME function, so the
    // two routes cannot mean different things by "keyed"; missing this one
    // is what would have made a color key visible in playback and invisible
    // on the canvas you draw on. The cel's texts are laid in the same call,
    // for the same reason ([celSurfaceAsShown]).
    final preview = celSurfaceAsShown(
      previewCache.previewSurface,
      sourceEffects,
    );

    final source = (
      revision: revision,
      canvasSize: canvasSize,
      sourceEffects: sourceEffects,
      madeFrom: _tilesOf(preview),
    );
    final plan = _levelPlan(
      preview,
      quality,
      storesInk: inkSuffices && !debugStoresWholeContent,
    );
    // 🚨WHAT IS PUT ON THE GPU WAITS ITS TURN ([turn]): everything above is
    // the CPU's and the workers', so the turn is taken here, and given back
    // once the image is banked.
    final QuietTurn? taken;
    if (turn == null) {
      taken = null;
    } else {
      taken = await turn();
      if (taken == null) {
        return null;
      }
    }
    LayerFrameImage? made;
    try {
      final stored = await _composed(
        preview,
        plan,
        quality,
        shouldAbort: shouldAbort,
      );
      made = stored == null ? null : _bank((key, quality), stored, source);
    } finally {
      made == null ? taken?.gaveUp() : taken?.landed();
    }
    return made;
  }

  /// Banks a freshly composed image as the entry for [at], replacing
  /// whatever sat there.
  ///
  /// ⛔BOTH COMPOSE PATHS BANK HERE. The async prepare and the sync
  /// handoff twin have to record the SAME revision, canvas size and
  /// source-effect signature, or the validity check reads one path's
  /// entry as stale and recomposes on every frame.
  LayerFrameImage _bank(
    (BrushFrameKey, PlaybackQuality) at,
    ({ui.Image image, ui.Rect worldRect, ui.Rect extent}) stored,
    ({
      int revision,
      CanvasSize canvasSize,
      List<ResolvedLayerEffect> sourceEffects,
      Map<TileCoord, Object> madeFrom,
    })
    source,
  ) {
    _dropEntry(at);
    final result = LayerFrameImage(
      image: stored.image,
      worldRect: stored.worldRect,
      extent: stored.extent,
      madeFrom: source.madeFrom,
    );
    _entries[at] = _LayerFrameImageEntry(
      positioned: result,
      sourceRevision: source.revision,
      canvasSize: source.canvasSize,
      sourceEffectSignature: celSourceEffectSignature(source.sourceEffects),
      lastUsed: ++_useCounter,
    );
    return result;
  }

  /// The synchronous road, for the editing canvas's sweep: the valid cached
  /// image, or one composed inside this call. `null` means the caller must
  /// fall back to [prepare] — or that the cel has nothing to show.
  ///
  /// 🚨★★★[makePictures] IS 「THIS CEL WAS ON SCREEN A FRAME AGO」 — as the
  /// layer being drawn on (a layer switch, a step to the next frame with
  /// onion skin on) or as this very row's picture before an edit (an undo
  /// on a layer you have switched away from). Such a row may not go blank,
  /// and may not keep the old picture, for the frames an asynchronous build
  /// takes (유저 절대규칙 2026-09-17 「보이는 중이랑 결과랑 절대로 다르면 안
  /// 되」), so its image is made HERE, at the quality asked: the tiles'
  /// pictures through the one door, halved on the spot below 100%.
  ///
  /// False is every other row — a cel that was NOT on screen (a frame
  /// scrubbed to, a project just opened). There the road is free or not
  /// taken: full quality only, and only when every tile already has its
  /// picture. Composing a whole cold stack inside a build is a stall
  /// nobody asked for; those rows arrive over the next frames, as they
  /// always have.
  ///
  /// ⛔REQUIRED, with no default, for [sourceEffects]' reason: a default
  /// would let a new caller inherit the blank frame silently.
  ///
  /// 🪦Until 2026-09-17 only the free road existed, full quality only. It
  /// was written when the display was always full quality and a background
  /// pass kept every committed tile pictured; with levels below 100%
  /// (2026-09-16) it answered null for every zoomed-out layer switch —
  /// measured: all 8 tiles pictured, 0 of 32 columns on the first frame
  /// after the switch at 50% — and with the one door (2026-09-17) also for
  /// a cel the paint had reached only part of.
  LayerFrameImage? prepareSyncOrNull({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
    required List<ResolvedLayerEffect> sourceEffects,
    required bool makePictures,
    bool inkSuffices = false,
  }) {
    final cached = _drawable(
      validImageOrNull(
        key,
        quality,
        canvasSize: canvasSize,
        sourceEffects: sourceEffects,
      ),
      inkSuffices: inkSuffices,
    );
    if (cached != null) {
      return cached;
    }
    if (!makePictures && quality != PlaybackQuality.full) {
      return null;
    }

    // The content oracle alone — see the async twin.
    if (!frameStore.celHasRenderableContent(key)) {
      return null;
    }
    final revision = _currentRevision(key);

    final previewCache = labProbe(
      'prepareFramePreview(${key.frameId.value} rev$revision)',
      () => BrushFrameDisplayCacheService(
        frameStore: frameStore,
        canvasSize: canvasSize,
      ).prepareFramePreview(key),
    );
    if (!previewCache.isValid) {
      // The size miss again — see the async twin. Banking the blank under
      // a revision that a heal never moves is what freezes the row.
      return null;
    }
    // The sync twin keys too — see the async path. A handoff that skipped
    // this would flash the unkeyed cel for exactly one layer switch, which
    // is the hardest kind of wrong to catch.
    final preview = celSurfaceAsShown(
      previewCache.previewSurface,
      sourceEffects,
    );
    final composed = _composedNow(
      preview,
      quality,
      makePictures: makePictures,
      storesInk: inkSuffices && !debugStoresWholeContent,
    );
    if (composed == null) {
      return null;
    }
    final at = (key, quality);
    final banked = _bank(at, composed.now, (
      revision: revision,
      canvasSize: canvasSize,
      sourceEffects: sourceEffects,
      madeFrom: _tilesOf(preview),
    ));
    _settleWhenTheSnapshotLands(at, composed.kept);
    return banked;
  }

  /// The entry at [at] holds a deferred image; [real] is the plain snapshot
  /// of the same picture. When it lands it takes the entry's place — same
  /// pixels, same validity — and the deferred image is retired, letting go
  /// of every tile picture it pinned ([_LayerFrameImageEntry.settling]).
  void _settleWhenTheSnapshotLands(
    (BrushFrameKey, PlaybackQuality) at,
    Future<ui.Image> real,
  ) {
    final entry = _entries[at]!;
    entry.settling = real.then<void>(
      (snapshot) {
        final slot = _slotHolding(entry, at);
        if (slot == null) {
          // Replaced, dropped, or the cache is gone: nobody wants it.
          snapshot.dispose();
          return;
        }
        _entries[slot] = _LayerFrameImageEntry(
          positioned: LayerFrameImage(
            image: snapshot,
            worldRect: entry.positioned.worldRect,
            extent: entry.positioned.extent,
            madeFrom: entry.positioned.madeFrom,
            // The same pixels, so the same content — a holder swaps its
            // handle and keeps everything it drew with the old one.
            content: entry.positioned.content,
          ),
          sourceRevision: entry.sourceRevision,
          canvasSize: entry.canvasSize,
          sourceEffectSignature: entry.sourceEffectSignature,
          lastUsed: entry.lastUsed,
        );
        DeferredImageDisposer.instance.retire(entry.image);
      },
      // A snapshot the engine refused: the deferred image stays the entry.
      onError: (Object _) => entry.settling = null,
    );
  }

  /// Eagerly drops every quality of one layer frame (sink-event eviction).
  void invalidateFrame(BrushFrameKey key) {
    for (final quality in PlaybackQuality.values) {
      _dropEntry((key, quality));
    }
  }

  /// Carries every quality's picture of a cel to the key a rekey moved its
  /// pixels to ([BrushFrameStore.addRekeyListener]): the same pixels, so
  /// the same picture, valid there as it was here.
  ///
  /// ⛔The pins stay where they are: each is a holder's, released at the
  /// slot it was taken on.
  void _travelWithTheirCels(
    List<(BrushFrameKey from, BrushFrameKey to)> pairs,
  ) {
    for (final (from, to) in pairs) {
      for (final quality in PlaybackQuality.values) {
        final entry = _entries.remove((from, quality));
        if (entry != null) {
          _dropEntry((to, quality));
          _entries[(to, quality)] = entry;
        }
      }
    }
  }

  /// The slot [entry] is held at now — where it was banked, or wherever a
  /// rekey carried it since ([_travelWithTheirCels]); null once it is gone.
  (BrushFrameKey, PlaybackQuality)? _slotHolding(
    _LayerFrameImageEntry entry,
    (BrushFrameKey, PlaybackQuality) banked,
  ) {
    if (identical(_entries[banked], entry)) {
      return banked;
    }
    for (final MapEntry(:key, :value) in _entries.entries) {
      if (identical(value, entry)) {
        return key;
      }
    }
    return null;
  }

  int get estimatedBytes {
    var total = 0;
    for (final entry in _entries.values) {
      total += estimatedImageBytes(entry.image.width, entry.image.height);
    }
    return total;
  }

  /// Lets go of images until at or under [maxBytes] — the ones wanted
  /// LATEST first ([wantedAt]: how many frames on a slot's image is next
  /// shown, null where nothing ahead shows it), the least recently used
  /// among equals — and answers whether that was enough. With [laterThan],
  /// never one wanted that soon or sooner: a picture is made only by
  /// letting go of pictures wanted after it.
  ///
  /// Without [wantedAt] every image is wanted equally, and recency alone
  /// orders them. The order is the budget's one ([letGoWantedLatest]).
  bool enforceBudget({
    required int maxBytes,
    LayerImageWantedAt? wantedAt,
    int? laterThan,
  }) => letGoWantedLatest(
    entries: [
      for (final entry in _entries.entries)
        // ⛔A pinned slot is ON SCREEN. Evicting it returns zero bytes
        // anyway (the holder's clone shares the pixels) and puts the very
        // image the canvas is drawing back on the cold path — the "worked
        // harder, got emptier" loop PR #1065 documented. Recency cannot
        // express "someone is holding this"; only the pin can.
        if (!_pins.isPinned(entry.key)) entry,
    ],
    heldBytes: estimatedBytes,
    maxBytes: maxBytes,
    wantedAt: (entry) => wantedAt?.call(entry.key),
    lastUsed: (entry) => entry.value.lastUsed,
    bytesOf: (entry) =>
        estimatedImageBytes(entry.value.image.width, entry.value.image.height),
    letGo: (entry) => _dropEntry(entry.key),
    laterThan: laterThan,
  );

  // --- Display pins (A6) ----------------------------------------------
  //
  // The editing canvas holds CLONES of cache images, and a clone shares
  // pixels: dropping the entry "freed" bytes that stayed fully alive, so
  // every budget figure downstream was fiction — the reserve PR #1065
  // added was sized by an estimate that saturated at twenty layers. The
  // pin is the holder saying "these pixels are on screen": eviction skips
  // the slot, and [pinnedBytes] is the MEASURED reserve that replaces the
  // estimate.

  final PinCounts<(BrushFrameKey, PlaybackQuality)> _pins = PinCounts<(BrushFrameKey, PlaybackQuality)>();

  /// Declares a holder of [key]'s image at [quality]. Balanced by
  /// [releasePin]; counts nest, because two widgets may hold the same
  /// slot's clone.
  void retainPin(BrushFrameKey key, PlaybackQuality quality) {
    final slot = (key, quality);
    _pins.retain(slot);
  }

  void releasePin(BrushFrameKey key, PlaybackQuality quality) {
    final slot = (key, quality);
    _pins.release(slot);
  }

  /// The bytes of every pinned slot's CURRENT entry — what the screen is
  /// actually holding, measured, not estimated. Walks the pins, not the
  /// entries: the pin set is the visible layer count.
  int get pinnedBytes {
    var total = 0;
    for (final slot in _pins.keys) {
      final entry = _entries[slot];
      if (entry != null) {
        total += estimatedImageBytes(entry.image.width, entry.image.height);
      }
    }
    return total;
  }

  void dispose() {
    frameStore.removeRekeyListener(_travelWithTheirCels);
    for (final key in _entries.keys.toList()) {
      _dropEntry(key);
    }
  }

  int _currentRevision(BrushFrameKey key) =>
      frameStore.frameOrNull(key)?.sourceRevision ?? 0;

  void _dropEntry((BrushFrameKey, PlaybackQuality) cacheKey) {
    final entry = _entries.remove(cacheKey);
    if (entry != null) {
      // Deferred, never direct: the image may still be referenced by the
      // frame currently on screen (same race the tile cache guards against).
      DeferredImageDisposer.instance.retire(entry.image);
    }
  }
}

// --- The steps a stored image is made of ------------------------------
//
// Plain functions of their inputs: each road's whole chain, halving a
// level, finding and cutting out the ink. Each step has a synchronous twin
// for the sync road.

/// [preview] put on the GPU at [quality] under [plan] — the cel's first
/// step ([_firstStep]), halved down to the level, and its ink cut out of
/// that when [plan] keeps the ink — each step waited for as it lands, where
/// [_composedNow] answers inside the call. Null when [shouldAbort] stood it
/// down between its tile pictures.
Future<({ui.Image image, ui.Rect worldRect, ui.Rect extent})?> _composed(
  BitmapSurface preview,
  ({ui.Rect whole, ui.Rect? texels}) plan,
  PlaybackQuality quality, {
  bool Function()? shouldAbort,
}) async {
  final (:whole, :texels) = plan;
  // Per-tile GPU compose ([_firstStep] says over what): the editing canvas
  // keeps the on-screen frame's tiles decoded in the shared cache, so the
  // post-stroke rebuild draws existing tile images instead of assembling +
  // uploading the whole canvas — cost follows the CHANGED tiles, not the
  // canvas.
  //
  // 🚨★★★ONE WAIT AN IMAGE, AT ANY LEVEL. Below the first level the compose
  // is the first step of a chain — halved, halved again, cut — and only
  // the chain's LAST step is the snapshot that is kept: every step before
  // it is rastered deferred and drawn straight into the next, the way the
  // synchronous road has always chained them ([_composedNow]).
  // ↩️Each step was a snapshot waited for until 2026-10-07 — up to three
  // waits for a half image and four for a quarter, the first of them the
  // whole canvas (🗣️유저 2026-10-05, board F-296: 「오히려 1/2로 하는게 더
  // 무거워지는거같은데 맞나?」).
  final first = _firstStep(preview, plan, quality.level);
  final firstIsKept = quality.level <= 1;
  final ui.Image? firstImage;
  if (first.halved) {
    firstImage = await composeHalvedSurfaceImage(
      preview,
      shouldAbort: shouldAbort,
      over: first.over,
      deferred: !firstIsKept,
    );
  } else {
    firstImage = (await composePositionedSurfaceImage(
      preview,
      reuse: BitmapTileImageCache.instance,
      shouldAbort: shouldAbort,
      over: first.over,
    ))?.image;
  }
  if (firstImage == null) {
    return null;
  }
  if (firstIsKept) {
    return (image: firstImage, worldRect: first.over, extent: whole);
  }
  // Down to the level, one exact 2×2 box at a time ([halvingPicture]) —
  // never one reduction straight to the size, which aliases past 2× and,
  // as `medium`, mipmaps on one engine and not the other.
  var image = firstImage;
  for (var i = 1; i < quality.level; i += 1) {
    // The last step when nothing is cut out after it.
    final kept = texels == null && i == quality.level - 1;
    final halved = kept
        ? await _halved(image)
        : _halvedNow(image, snapshot: false).deferred;
    // The halving keeps what it drew; only the handle is ours to drop.
    image.dispose();
    image = halved;
  }
  assert(_isLevelOf(image, whole, quality.level));
  if (texels == null) {
    return (image: image, worldRect: whole, extent: whole);
  }
  // Cut out of the level of the WHOLE image, never halved on its own: the
  // halving is the engine's, and a smaller image is halved differently on
  // Impeller Vulkan (`halving-rounds-differently-per-engine`).
  final ink = await _cutOut(image, texels);
  image.dispose();
  return (
    image: ink,
    worldRect: _worldRectOfTexels(whole, texels, quality.level),
    extent: whole,
  );
}

/// [preview] composed inside the call at [quality] — the cel's first step
/// ([_firstStep]), halved down to the level, and, when [storesInk] below the
/// first level, its ink cut out of that — beside the plain snapshot of the
/// picture that is KEPT: the last of those steps. Null only on the free
/// road ([makePictures] false and a tile without its picture).
({
  ({ui.Image image, ui.Rect worldRect, ui.Rect extent}) now,
  Future<ui.Image> kept,
})?
_composedNow(
  BitmapSurface preview,
  PlaybackQuality quality, {
  required bool makePictures,
  required bool storesInk,
}) {
  final plan = _levelPlan(preview, quality, storesInk: storesInk);
  final (:whole, :texels) = plan;
  final first = _firstStep(preview, plan, quality.level);
  final firstIsKept = quality.level <= 1;
  final ({ui.Image deferred, Future<ui.Image>? real})? composed;
  if (first.halved) {
    composed = composeHalvedSurfaceImageSync(
      preview,
      makePictures: makePictures,
      snapshot: firstIsKept,
      over: first.over,
    );
  } else {
    final positioned = composePositionedSurfaceImageSync(
      preview,
      reuse: BitmapTileImageCache.instance,
      makePictures: makePictures,
      snapshot: firstIsKept,
      over: first.over,
    );
    composed = positioned == null
        ? null
        : (deferred: positioned.deferred.image, real: positioned.real);
  }
  if (composed == null) {
    return null;
  }
  if (firstIsKept) {
    return (
      now: (image: composed.deferred, worldRect: first.over, extent: whole),
      kept: composed.real!,
    );
  }
  var image = composed.deferred;
  Future<ui.Image>? kept;
  for (var i = 1; i < quality.level; i += 1) {
    final halved = _halvedNow(
      image,
      snapshot: texels == null && i == quality.level - 1,
    );
    // The halving keeps what it drew; only the handle is ours to drop.
    image.dispose();
    image = halved.deferred;
    kept = halved.real;
  }
  assert(_isLevelOf(image, whole, quality.level));
  if (texels == null) {
    return (
      now: (image: image, worldRect: whole, extent: whole),
      kept: kept!,
    );
  }
  final ink = _cutOutNow(image, texels);
  // The cut keeps what it drew; only the handle is ours to drop.
  image.dispose();
  return (
    now: (
      image: ink.deferred,
      worldRect: _worldRectOfTexels(whole, texels, quality.level),
      extent: whole,
    ),
    kept: ink.real!,
  );
}

/// The first step of a level-[level] image of [preview] under [plan]: the
/// canvas-space rect its tiles are drawn over, and whether they are halved
/// as they are drawn — below the full level always, so no level begins as
/// the whole image at full size.
///
/// 🚨★★★THE FIRST HALVING IS MADE FROM THE TILES (2026-10-10). Below the
/// full level the chain began with the whole content at full size — every
/// raster of a picture is a multisampled render with a whole mip chain
/// ([_inkAtFull]) — and halved after; a tile halved at its place is the same
/// mean of the same four texels ([composeHalvedSurfaceImage]), drawn into a
/// quarter of the pixels. 🔬The Windows app (Impeller GLES, profile build),
/// a copy of the user's project, every distinct cel of a cut made one after
/// another with nothing playing: cut 302 (43 cels) at a half 1.09–1.30 →
/// 0.52–0.62 s and at a quarter 1.11–1.16 → 0.61–0.68 s; cut 301 (46 cels)
/// at a half 0.66 → 0.17–0.28 s — a level was dearer to make than the full
/// image (0.57 s and 0.22 s) and is not any more (유저 2026-10-05).
///
/// At the FIRST level the ink is drawn straight into its own rect: its
/// tiles, and so its texels, are the whole image's there. DEEPER, the first
/// level of the WHOLE is what the halvings go on from, and the ink is cut
/// out of the level they reach, as it always was — a smaller image halves
/// differently on Impeller Vulkan, and the ink kept must be the whole's
/// bytes on every engine (98442b79a; 유저 2026-09-23 「결과바뀌는건 절대로
/// 허용안하고」).
///
/// ⚠️THE WHOLE'S FIRST LEVEL IS THE CONTENT GROWN TO EVEN — the very image
/// the whole was halved to first — so every halving after it is the one the
/// whole took, an odd edge clamped where it was ([halvedSize]). Over the
/// level's own whole the bytes come out the same too, but only because a
/// content edge off the tile grid holds no ink (the mutant survives,
/// 2026-10-10).
({ui.Rect over, bool halved}) _firstStep(
  BitmapSurface preview,
  ({ui.Rect whole, ui.Rect? texels}) plan,
  int level,
) {
  final (:whole, :texels) = plan;
  if (level == 0) {
    return (over: _inkAtFull(plan) ?? whole, halved: false);
  }
  if (level == 1) {
    return (
      over: texels == null ? whole : _worldRectOfTexels(whole, texels, 1),
      halved: true,
    );
  }
  return (
    over: _levelPlan(preview, PlaybackQuality.forLevel(1), storesInk: false)
        .whole,
    halved: true,
  );
}

/// The tile object at every coordinate [surface] holds — what an image
/// composed from it was made from ([LayerFrameImage.madeFrom]).
Map<TileCoord, Object> _tilesOf(BitmapSurface surface) =>
    Map<TileCoord, Object>.of(surface.tiles);

/// [image] when the asking route can draw it — always for a whole image, and
/// for the ink alone only when [inkSuffices].
LayerFrameImage? _drawable(
  LayerFrameImage? image, {
  required bool inkSuffices,
}) => image != null && image.isInk && !inkSuffices ? null : image;

/// What a level-[quality] image of [preview] is, known before a pixel is
/// drawn — so both roads decide what to compose, and which step's snapshot
/// to keep, before composing: [whole] is the canvas-space rect the whole
/// content covers at that level — the content grown past an odd edge by the
/// halvings ([halvedSize]), so a level maps onto the canvas at exactly
/// 1/2^k — and, when [storesInk], [texels] the part of it holding the ink
/// ([_inkTexels]; null when that is all of it).
({ui.Rect whole, ui.Rect? texels}) _levelPlan(
  BitmapSurface preview,
  PlaybackQuality quality, {
  required bool storesInk,
}) {
  final content = surfaceContentWorldRect(preview);
  var width = content.width.round();
  var height = content.height.round();
  for (var i = 0; i < quality.level; i += 1) {
    (:width, :height) = halvedSize(width, height);
  }
  final step = (1 << quality.level).toDouble();
  final whole = ui.Rect.fromLTWH(
    content.left,
    content.top,
    width * step,
    height * step,
  );
  return (
    whole: whole,
    texels: storesInk
        ? _inkTexels(
            surfaceInkWorldRect(preview),
            whole: whole,
            level: quality.level,
          )
        : null,
  );
}

/// Whether [image] is the level-[level] image [whole] says it is.
bool _isLevelOf(ui.Image image, ui.Rect whole, int level) =>
    image.width << level == whole.width.round() &&
    image.height << level == whole.height.round();

/// The rect the ink alone is composed over at the full level, straight from
/// its tiles — each tile lands texel for texel, and those are the whole
/// image's pixels there. At the first level the ink is drawn halved straight
/// into its own rect the same way; deeper it is cut out of the halved whole
/// ([_firstStep]).
///
/// 🔬WHY NOT COMPOSE THE WHOLE AND CUT (2026-09-24, 유저 「성능적인 면은 아주
/// 중요하니까 철저하게 하자」): every raster of a picture is a multisampled
/// render with a whole mip chain (the engine's `DisplayListToTexture`,
/// `generate_mips`), ~6ms for a 2540×1654 image on the Windows app. The
/// whole-then-cut road paid that for the whole image and again for the cut;
/// this pays it once, for the ink.
ui.Rect? _inkAtFull(({ui.Rect whole, ui.Rect? texels}) plan) =>
    switch (plan) {
      (whole: final whole, texels: final texels?) =>
        _worldRectOfTexels(whole, texels, 0),
      _ => null,
    };

/// The texels of a level-[level] image of a cel's whole content — the image
/// over [whole] — that hold its [ink] ([surfaceInkWorldRect]); null when
/// that is all of them.
///
/// Nothing is lost past them at any level: a 2×2 block outside the ink holds
/// nothing and halves to nothing on every engine. Impeller Vulkan samples a
/// little off the middle of each block at a working size
/// (`halving-rounds-differently-per-engine`), which moves the weights of
/// that block's four texels and never which four — a trace of the next
/// block would take half a texel of drift. 🔬A cut with ink stopping at tile
/// edges lays back to the whole level's bytes on Vulkan at 1172×828
/// (`a_cropped_cel_draws_the_same_bytes_test`).
ui.Rect? _inkTexels(ui.Rect ink, {required ui.Rect whole, required int level}) {
  final step = (1 << level).toDouble();
  final width = (whole.width / step).round();
  final height = (whole.height / step).round();
  final texels = ui.Rect.fromLTRB(
    ((ink.left - whole.left) / step).floorToDouble(),
    ((ink.top - whole.top) / step).floorToDouble(),
    math.min(width, ((ink.right - whole.left) / step).ceil()).toDouble(),
    math.min(height, ((ink.bottom - whole.top) / step).ceil()).toDouble(),
  );
  return texels == ui.Rect.fromLTWH(0, 0, width * 1.0, height * 1.0)
      ? null
      : texels;
}

/// Where [texels] of a level-[level] image over [whole] sit in canvas
/// space.
ui.Rect _worldRectOfTexels(ui.Rect whole, ui.Rect texels, int level) {
  final step = (1 << level).toDouble();
  return ui.Rect.fromLTWH(
    whole.left + texels.left * step,
    whole.top + texels.top * step,
    texels.width * step,
    texels.height * step,
  );
}

/// [texels] of [whole] cut out, rasterised off the frame. The
/// synchronous twin is [_cutOutNow].
Future<ui.Image> _cutOut(ui.Image whole, ui.Rect texels) async {
  final picture = recordInkCutOut(whole, texels).endRecording();
  try {
    return await waitedSnapshot(
      picture,
      texels.width.round(),
      texels.height.round(),
    );
  } finally {
    picture.dispose();
  }
}

/// [texels] of [whole] cut out inside the call — deferred on the GPU —
/// plus the plain snapshot of the same cut.
({ui.Image deferred, Future<ui.Image>? real}) _cutOutNow(
  ui.Image whole,
  ui.Rect texels,
) => rasterPictureAndSnapshot(
  recordInkCutOut(whole, texels),
  texels.width.round(),
  texels.height.round(),
  snapshot: true,
);

/// [source] halved inside the call — the next level down, deferred on
/// the GPU — plus, when [snapshot], the plain snapshot of the same
/// halving. The asynchronous twin is [_halved].
({ui.Image deferred, Future<ui.Image>? real}) _halvedNow(
  ui.Image source, {
  required bool snapshot,
}) {
  final size = halvedSize(source.width, source.height);
  final picture = halvingPicture([(image: source, at: ui.Offset.zero)]);
  try {
    return (
      deferred: picture.toImageSync(size.width, size.height),
      real: snapshot ? picture.toImage(size.width, size.height) : null,
    );
  } finally {
    picture.dispose();
  }
}

/// [source] halved — the next level down, rasterised off the frame.
Future<ui.Image> _halved(ui.Image source) async {
  final size = halvedSize(source.width, source.height);
  final picture = halvingPicture([(image: source, at: ui.Offset.zero)]);
  try {
    return await waitedSnapshot(picture, size.width, size.height);
  } finally {
    picture.dispose();
  }
}
