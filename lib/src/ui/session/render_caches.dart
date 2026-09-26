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
// which cut to warm, around which frame, at which quality. That reads
// the standing row, the timeline controller and the storyboard order, so
// it stays with the session and arrives here as the [ChangeSink] verb it
// always was. Keeping it out is also what keeps this acyclic: the
// playback rig reaches IN here for the composite cache, so if the caches
// reached back out for the warmer neither could be built.

import 'dart:async';
import 'dart:io';

import '../../models/brush_frame_cache_invalidation.dart';
import '../../models/brush_frame_key.dart';
import '../../models/conte/conte_ink_keys.dart';
import '../../models/envelope/cut_envelope_ink_keys.dart';
import '../../models/timesheet_ink_keys.dart';
import '../../services/brush_frame_store.dart';
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
    required SessionInternals internals,
    required void Function() onEditActivity,
  }) : _project = project,
       _changes = changes,
       _internals = internals,
       _onEditActivity = onEditActivity;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final SessionInternals _internals;

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
  void applyCacheBudgets(CacheBudgets budgets) {
    brushFrameStore.hotCelByteBudget = budgets.drawings;
    final stores = sheetInkStores;
    for (final store in stores) {
      store.hotCelByteBudget = budgets.sheetInk ~/ stores.length;
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
  /// because `CanvasLayerStackView` has exactly ONE construction site (the
  /// editing canvas). A second one would need the map — and would silently
  /// overwrite this until someone noticed, which is why it is written down.
  int canvasBufferBytes = 0;

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

  /// The conte sheet ink's cel stores (R5) — SESSION-owned so the .anicel
  /// archive can persist them (the second cel namespace), while the ink
  /// controller (workspace UI) keeps the coordinators. The ROW store's
  /// keys carry storyboard block [FrameId]s: entries whose block no longer
  /// exists are pruned at LOAD (never at save — a deleted block's ink must
  /// survive its own undo), so "ink dies with the drawing" lands at the
  /// session boundary.
  final BrushFrameStore conteInkRowStore = BrushFrameStore();
  final BrushFrameStore conteInkPageStore = BrushFrameStore();

  /// The cut envelope's ink store — SESSION-owned for the same reason: the
  /// archive persists it, the workspace's controller owns the coordinator.
  /// Its keys carry the OWNER cut's id, so an entry whose cut is gone is
  /// pruned at LOAD exactly like a conte row's.
  final BrushFrameStore envelopeInkStore = BrushFrameStore();

  /// The timesheet's ink stores — SESSION-owned like the conte's and the
  /// envelope's (유저 2026-09-26: 「다 통일해줘. 기능은 어차피 생길수있어」):
  /// the ink was the one sheet's that no save carried. The keys carry the
  /// cut's id, so an entry whose cut is gone is pruned at LOAD, the
  /// envelope's unit.
  final BrushFrameStore timesheetInkStripStore = BrushFrameStore();
  final BrushFrameStore timesheetInkPageStore = BrushFrameStore();

  /// Every sheet's ink stores — the ONE list a whole-session walk reads:
  /// the budgets, memory pressure, the census, a save, an open, a reset.
  ///
  /// ⛔Six walks each wrote the stores out by hand; a sheet whose ink came
  /// later would have been saved by some of them and budgeted by others.
  List<BrushFrameStore> get sheetInkStores => [
    conteInkRowStore,
    conteInkPageStore,
    envelopeInkStore,
    timesheetInkStripStore,
    timesheetInkPageStore,
  ];

  /// Every store a cel ref can live in — the drawings, then
  /// [sheetInkStores], the order every writer lists them in.
  List<BrushFrameStore> get celStores => [brushFrameStore, ...sheetInkStores];

  /// The store a sheet-ink [key] lives in — by its namespace and its plane
  /// — or null for a drawing's key.
  BrushFrameStore? sheetInkStoreFor(BrushFrameKey key) {
    if (isConteInkKey(key)) {
      return key.layerId == conteInkRowLayerId
          ? conteInkRowStore
          : conteInkPageStore;
    }
    if (isTimesheetInkKey(key)) {
      return key.layerId == timesheetInkStripLayerId
          ? timesheetInkStripStore
          : timesheetInkPageStore;
    }
    return isEnvelopeInkKey(key) ? envelopeInkStore : null;
  }

  /// Production sink for brush edit invalidations; playback caches and the
  /// prerender scheduler listen here.
  late final EditorCacheInvalidationHub cacheInvalidationHub =
      EditorCacheInvalidationHub();

  // --- Playback render cache stack (all non-notifying; see plan R2-R4) -----

  late final LayerFrameImageCache layerFrameImageCache = LayerFrameImageCache(
    frameStore: brushFrameStore,
  );

  late final CutFrameCompositeCache cutFrameCompositeCache =
      CutFrameCompositeCache(
        layerImages: layerFrameImageCache,
        frameStore: brushFrameStore,
        frameKeyOf: _internals.brushFrameKeyForCut,
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
      if (_internals.disposed) {
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
