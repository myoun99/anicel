// Every pixel this session is holding on to, and the one signal that
// makes a held pixel wrong: the cel stores an archive persists, the two
// playback render caches built on top of them, the invalidation hub the
// commands publish on, and the debounce that restarts warming once per
// edit burst.
//
// Its own object since round 8 (G2, 2026-09-07). They are ONE object
// because they are one lifetime and one chain: a brush edit invalidates
// the layer image, the layer image invalidates the composite, and the
// composite is what the warmer refills. Splitting them would put the
// chain's three links in three places and give the invalidation listener
// nowhere to live.
//
// ⛔What is NOT here is the session's REACTION to a settled burst —
// which cut to warm, around which frame. That reads
// the standing row, the timeline controller and the storyboard order, so
// it stays with the session and arrives here as the [ChangeSink] verb it
// always was. Keeping it out is also what keeps this acyclic: the
// playback rig reaches IN here for the composite cache, so if the caches
// reached back out for the warmer neither could be built.

import 'dart:async';
import 'dart:io';

import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_cache_invalidation.dart';
import '../../models/brush_frame_key.dart';
import '../../models/conte/conte_ink_keys.dart';
import '../../models/envelope/cut_envelope_ink_keys.dart';
import '../../models/frame.dart';
import '../../models/layer.dart';
import '../../models/timesheet_ink_keys.dart';
import '../../services/bitmap_surface_geometry.dart'
    show bitmapSurfaceContentBounds;
import '../../services/brush_frame_store.dart';
import '../../services/cel_text_laying.dart';
import '../../services/cut_frame_composite_plan.dart'
    show resolveExposedFrameAt;
import '../../services/playback/editor_cache_invalidation_hub.dart';
import '../playback/cut_frame_composite_cache.dart';
import '../playback/layer_frame_image_cache.dart';
import 'session_roles.dart';
import 'cache_budgets.dart';

/// The session's cel stores, the playback render caches over them, and
/// the invalidation path that keeps the two honest.
class RenderCaches {
  RenderCaches({
    required ProjectAccess project,
    required ChangeSink changes,
    required bool Function() sessionDisposed,
    required void Function() onEditActivity,
  }) : _project = project,
       _changes = changes,
       _sessionDisposed = sessionDisposed,
       _onEditActivity = onEditActivity;

  final ProjectAccess _project;
  final ChangeSink _changes;

  /// Whether the session has been disposed — a plain flag, so it comes as
  /// the question.
  final bool Function() _sessionDisposed;

  /// What an edit owes the warmer BEFORE anything is re-rendered: yield.
  /// A callback rather than the rig itself — the rig holds this object
  /// (its scheduler composites out of [cutFrameCompositeCache]), and two
  /// objects that name each other cannot be built at all.
  final void Function() _onEditActivity;

  /// App-level brush stroke store shared with the canvas host, so commands
  /// (e.g. anchored canvas resize) can transform stroke data.
  ///
  /// The link resolver reads the CURRENT project's registry on every
  /// resolve (L1) — link edits need no event plumbing to reach the store.
  late final BrushFrameStore brushFrameStore = BrushFrameStore()
    ..setLinkResolver(
      (key) =>
          _project.repository.currentProject?.linkRegistry.canonicalCelKey(
            key,
          ) ??
          key,
    );

  /// Sets the cel stores' hot budgets from [budgets]: the drawings' own,
  /// and the sheet-ink stores' ONE share, split evenly
  /// ([CacheBudgets.sheetInk]). The session calls it; a store no session
  /// set keeps the desktop-class default, as an unknown device does.
  ///
  /// ...and KEEPS them: each store cools what its new budget no longer
  /// holds ([BrushFrameStore.coolToBudget]) — the playback cache's
  /// `enforce` said of the cels. A budget that moved and waited for the
  /// next cel to arrive was never kept by a project tab sent behind (I-7),
  /// which gets no next cel.
  void applyCacheBudgets(CacheBudgets budgets) {
    brushFrameStore.hotCelByteBudget = budgets.drawings;
    final stores = sheetInkStores;
    for (final store in stores) {
      store.hotCelByteBudget = budgets.sheetInk ~/ stores.length;
    }
    for (final store in celStores) {
      store.coolToBudget();
    }
  }

  /// Page-raster bytes each mounted media viewer is holding, by viewer id.
  ///
  /// 🚨**PUSHED, where every other census number is PULLED.** The census
  /// is deliberately addition rather than measurement — it reads counters
  /// the holder already keeps — and it can do that because the session
  /// owns those holders. It does not own these: the viewer's pages live in
  /// a widget State that mounts and unmounts as tabs open and rails fold,
  /// and there are two of them. So the viewers write here instead, and
  /// clear their entry when they go.
  ///
  /// ⛔Without this the panel that answers「어떤항목이 얼만큼」 was silent
  /// about a cache that can hold a quarter of a gigabyte per viewer — the
  /// gap would land in `untrackedBytes` and read as engine overhead.
  final Map<String, int> viewerRasterBytesByViewer = <String, int>{};

  /// What the editing canvas's display buffer holds — one canvas-resolution
  /// image, 33MB on a 4K view, kept for as long as nothing changes.
  /// 🆕2026-09-11: and the static-composite bake beside it — one visible-rect
  /// raster (~9MB at 1928×1200) that nobody counted. The same view reports
  /// both as this one number.
  ///
  /// 🚨PUSHED, for the reason above it: the buffer lives in a widget State
  /// the session does not own. ⚠️A plain int rather than the viewers' map
  /// because it is the EDITING CANVAS's alone; the second
  /// `CanvasLayerStackView` site keeps its own map below
  /// ([livePictureBufferBytes]) rather than overwriting this.
  int canvasBufferBytes = 0;

  /// What each LIVE picture's display buffer holds — the conte's pictures,
  /// composited live while its brush is on (유저 답 conte-picture-display-Q1
  /// 「실시간 합성」), by picture: several are live at once. The same census
  /// row as [canvasBufferBytes], pushed for the same reason.
  final Map<String, int> livePictureBufferBytes = {};

  /// What the storyboard's and the conte's thumbnails hold — every panel
  /// picture still inside its budget (one viewer's share of this device).
  ///
  /// 🚨PUSHED, for the reason above it: the store lives in the workspace's
  /// State, which the session does not own. Until 2026-09-11 nothing
  /// counted it at all — no budget and no census row, and a panel looked
  /// at once stayed resident until the workspace closed.
  int storyboardThumbnailBytes = 0;

  /// What the media viewers hold between them.
  int get viewerRasterBytes {
    var total = 0;
    for (final bytes in viewerRasterBytesByViewer.values) {
      total += bytes;
    }
    return total;
  }

  /// The conte sheet ink's cel store (R5) — SESSION-owned so the .anicel
  /// archive can persist it (the second cel namespace), while the ink
  /// controller (workspace UI) keeps the coordinator. Its
  /// keys carry each storyboard block's own handwriting id
  /// (`ExposureMemo.inkId`): entries no block names any more are pruned at
  /// LOAD (never at save — a deleted block's ink must survive its own
  /// undo), so "ink dies with the block" lands at the session boundary.
  final BrushFrameStore conteInkRowStore = BrushFrameStore();

  /// The cut envelope's ink store — SESSION-owned for the same reason: the
  /// archive persists it, the workspace's controller owns the coordinator.
  /// Its keys carry the OWNER cut's id, so an entry whose cut is gone is
  /// pruned at LOAD exactly like a conte row's.
  final BrushFrameStore envelopeInkStore = BrushFrameStore();

  /// The timesheet's ink store — SESSION-owned like the conte's and the
  /// envelope's (유저 2026-09-26: 「다 통일해줘. 기능은 어차피 생길수있어」):
  /// the ink was the one sheet's that no save carried. The keys carry the
  /// cut's id, so an entry whose cut is gone is pruned at LOAD, the
  /// envelope's unit.
  final BrushFrameStore timesheetInkStore = BrushFrameStore();

  /// Every sheet's ink stores — the ONE list a whole-session walk reads:
  /// the budgets, memory pressure, the census, a save, an open, a reset.
  ///
  /// ⛔Six walks each wrote the stores out by hand; a sheet whose ink came
  /// later would have been saved by some of them and budgeted by others.
  List<BrushFrameStore> get sheetInkStores => [
    conteInkRowStore,
    envelopeInkStore,
    timesheetInkStore,
  ];

  /// Every store a cel ref can live in — the drawings, then
  /// [sheetInkStores], the order every writer lists them in.
  List<BrushFrameStore> get celStores => [brushFrameStore, ...sheetInkStores];

  /// The store a sheet-ink [key] lives in — by its namespace — or null for
  /// a drawing's key.
  BrushFrameStore? sheetInkStoreFor(BrushFrameKey key) {
    // Every conte key, even the paper plane an older file kept: it is
    // sheet ink and never a drawing, and the load drops what names no block.
    if (isConteInkKey(key)) {
      return conteInkRowStore;
    }
    if (isTimesheetInkKey(key)) {
      return timesheetInkStore;
    }
    return isEnvelopeInkKey(key) ? envelopeInkStore : null;
  }

  /// Production sink for brush edit invalidations; playback caches and the
  /// prerender scheduler listen here.
  late final EditorCacheInvalidationHub cacheInvalidationHub =
      EditorCacheInvalidationHub();

  /// The drawable artwork of one layer frame in the active cut; `null` when
  /// nothing is drawn. This is the production [LayerFrameSurfaceResolver]
  /// for camera preview/export compositing and the canvas tools (eyedropper
  /// sample, fill compose). The store's display cache is consumed when
  /// valid (the editing coordinator donates the session surface on every
  /// commit/undo/redo); a cold rebuild replays the frame's paint commands
  /// ONCE and stores the result back as the new display cache — repeated
  /// tool taps must not replay the whole stroke history per tap (R11-②③).
  ///
  /// The cel is keyed the one way the project keys it
  /// ([ProjectAccess.brushFrameKeyForCut]) — this read built its key by
  /// hand from the SELECTED track, the old name for the active cut's track
  /// (the audit's twentieth family, 2026-09-29).
  BitmapSurface? brushSurfaceForLayerFrame(Layer layer, Frame frame) {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return null; // Gap state: no cut, no artwork.
    }
    // R19 P3b: the baked raster is the truth — the resolver is a plain
    // reference read (valid display cache first, else baked). No replay
    // exists anymore.
    return brushFrameStore.currentSurfaceWithoutReplay(
      _project.brushFrameKeyForCut(cut, layer.id, frame.id),
      canvasSize: cut.canvasSize,
    );
  }

  /// [layer]'s tight INK bounds at [frameIndex], in the layer's own
  /// artwork coordinates — what the canvas transform box frames (R5 #10:
  /// "레이어 그림의 바운드에 걸리는게 알기쉬울거같기도하고? 그렇게하자").
  /// Null while the row shows nothing there, or the cel is blank.
  ///
  /// Memoized on the surface INSTANCE, and that is not an optimisation but
  /// the condition of calling it at all: the scan reads every tile of the
  /// cel, and the box is framed from `build`. `BitmapSurface` is immutable
  /// with structural tile sharing, so identity is an exact key — a changed
  /// cel is always a new instance. The selection layer's own box learned
  /// this the hard way (`bitmap_surface_geometry.dart`'s note).
  ({int left, int top, int rightExclusive, int bottomExclusive})?
  layerContentBoundsAt(Layer layer, int frameIndex) {
    final frame = resolveExposedFrameAt(layer, frameIndex);
    if (frame == null) {
      return null;
    }
    // The LAYER's picture — its texts with it: the box this frames moves
    // the whole row, and a text is part of what the row shows (유저
    // 2026-10-06: 「셀의 그림이랑 정확히 동일」). ⚠️The transform TOOL's own box
    // frames the drawing alone — it never takes a text (「변형도구로 잡히지도
    // 아무 영향도 없음」) — and does not ask here.
    final drawn = brushSurfaceForLayerFrame(layer, frame);
    final surface = drawn == null ? null : celSurfaceWithTextsLaid(drawn);
    if (surface == null) {
      return null;
    }
    if (identical(surface, _layerContentBoundsSurface)) {
      return _layerContentBoundsCached;
    }
    _layerContentBoundsSurface = surface;
    return _layerContentBoundsCached = bitmapSurfaceContentBounds(surface);
  }

  BitmapSurface? _layerContentBoundsSurface;
  ({int left, int top, int rightExclusive, int bottomExclusive})?
  _layerContentBoundsCached;

  // --- Playback render cache stack (all non-notifying; see plan R2-R4) -----

  late final LayerFrameImageCache layerFrameImageCache = LayerFrameImageCache(
    frameStore: brushFrameStore,
  );

  late final CutFrameCompositeCache cutFrameCompositeCache =
      CutFrameCompositeCache(
        layerImages: layerFrameImageCache,
        frameStore: brushFrameStore,
        frameKeyOf: _project.brushFrameKeyForCut,
      );

  /// A5 — the trailing edge of an edit burst, so the warming queue
  /// restarts ONCE per burst instead of once per dab commit. Only the
  /// RESTART is deferred: the cache invalidations and the yield signal
  /// stay synchronous, because a stale composite must be unservable the
  /// instant the stroke lands. The window costs nothing in production —
  /// warming cannot start until [PlaybackPrerenderScheduler.idleDelay]
  /// (1200ms) of quiet anyway, so any window under that only merges
  /// restarts it never delays.
  Timer? _warmDebounce;

  static final Duration _warmDebounceWindow =
      Platform.environment['FLUTTER_TEST'] == 'true'
      // Tests: next-turn, mirroring the scheduler's zero idleDelay — a
      // pending 200ms timer at teardown trips the binding's timer
      // invariant before the session's tearDown dispose runs. Zero still
      // debounces: a synchronous burst re-arms one timer and fires once.
      ? Duration.zero
      : const Duration(milliseconds: 200);

  void _onBrushFrameInvalidated(BrushFrameCacheInvalidation invalidation) {
    layerFrameImageCache.invalidateFrame(invalidation.frameKey);
    cutFrameCompositeCache.invalidateWhereLayerFrame(
      layerId: invalidation.frameKey.layerId,
      frameId: invalidation.frameKey.frameId,
    );
    // Warming yields to the edit and then re-renders the dirty frames.
    _onEditActivity();
    _warmDebounce?.cancel();
    _warmDebounce = Timer(_warmDebounceWindow, () {
      _warmDebounce = null;
      // ⚠️Mutating this guard away leaves every suite green (measured
      // 2026-09-07): [dispose] cancels the pending timer first, so no
      // route reaches here after teardown. Belt to that brace — kept
      // because the cancel and this check answer the same question from
      // two sides and the cheap one is here.
      if (_sessionDisposed()) {
        return;
      }
      _changes.warmActiveCut();
    });
  }

  /// Listening starts with the session: a command that lands before this
  /// leaves a stale composite servable.
  void attach() =>
      cacheInvalidationHub.addBrushFrameListener(_onBrushFrameInvalidated);

  /// ⚠️The ORDER is the one the session's `dispose` used to spell: the
  /// listener comes off the hub and the pending restart is cancelled
  /// BEFORE the caches it would have refilled go down.
  void dispose() {
    _warmDebounce?.cancel();
    cacheInvalidationHub.removeBrushFrameListener(_onBrushFrameInvalidated);
    cutFrameCompositeCache.dispose();
    layerFrameImageCache.dispose();
  }
}
