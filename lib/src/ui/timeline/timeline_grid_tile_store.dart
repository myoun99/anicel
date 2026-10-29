import '../../services/straight_rgba_image.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' hide Uint8List;
import 'package:flutter/material.dart';

import '../../core/rgba_premultiply.dart' show straightRgbaFor;
import '../../core/signed_memo.dart';
import '../../core/sync_image_upload.dart';
import '../../models/frame.dart' show InbetweenMark;
import '../../models/layer.dart';
import '../../models/layer_cells_agreement.dart';
import '../../models/layer_id.dart';
import '../../models/rgba_image_bytes.dart';
import '../../native/qa_native_engine.dart';
import '../text/word_bake.dart';
import '../text/word_condensation.dart';
import '../quiet_turns.dart';
import 'axis_turn.dart' show endAlong, offsetAlong, startAlong;
import 'inbetween_mark_painter.dart' show inbetweenMarkRingWidth;
import 'timeline_frame_window.dart';
import '../text/laid_out_glyph.dart';
import 'timeline_grid_tile_ops.dart';
import 'timeline_tile_raster_source.dart';
import '../../core/bake_once_lru.dart';
import '../../core/lru.dart';
import '../../services/playback/let_go_wanted_latest.dart';

/// The drawing rows' SUBSTRATE tile store (UI-R18 O7 T2, R18-T).
///
/// A row's cells — its paper and the frame lines on it
/// ([TimelineTileRasterSource.substrateIn]), plus the ink over them —
/// rasterize ONCE per (row, span, look) through the native
/// `qa_grid_raster_tile` and land here as a premultiplied [ui.Image]; the
/// row painter then draws one `drawImageRect` per span instead of 2-3
/// canvas calls per cell.
///
/// ⚠️ The ink is IN the tile. The emitter writes the substrate and then
/// the foreground — the in-between marks inline, glyph text through the A8
/// atlas (T3), a ghost's aside (F-446) — into one op stream, and `_paint` skips
/// its Dart foreground pass for any span a tile covers. This doc used to say
/// the opposite ("foreground ink stays the painter's Dart pass on top"),
/// which was true of the tile's first shape and has misled at least one
/// reader into costing a text-layering round wrongly; the
/// stale-while-revalidate note below is the honest description, naming the
/// two technologies it chooses between as "baked A8 glyphs ↔ TextPainter".
///
/// The classic Dart pass is the FALLBACK, for spans with no usable tile.
///
/// Contracts:
/// - Tiles are TRANSPARENT (background 0): accumulation from
///   transparent black is premultiplied, the raw-upload contract, so a
///   tile composites pixel-true over any panel background.
/// - The tile grid rides the SHARED window policy
///   ([timelineFrameWindowSpanFor]): tile i covers cells
///   [i*span, (i+1)*span) — scrolling reuses tiles bucket by bucket.
/// - Keys carry the full LOOK identity (layer object identity — layers
///   are immutable, an edit is a new instance — extents, the paper's
///   ground, the block-frame-lines switch and the fps, scheme, DPR): any
///   mismatch re-rasters, so edits invalidate exactly like `shouldRepaint`.
/// - NO native engine (flutter_tester, unsupported platforms, load
///   failure) = the store stands down entirely ([tileFor] returns null
///   and requests nothing): rows keep the classic Dart paint, tests and
///   packaging stay byte-for-byte on today's path.
class TimelineGridTileStore {
  TimelineGridTileStore._();

  static final TimelineGridTileStore instance = TimelineGridTileStore._();

  /// Bumped when a tile lands, whichever row it is — in the paint that
  /// bakes it or off-frame — a count for tests to wait on. ⛔No painter
  /// listens to it: a row repaints on ITS OWN landings ([noticesFor]).
  ///
  /// 🚨I-22 ③: every row painter used to merge this into its repaint, so ONE
  /// landing repainted EVERY row — and a row with cold spans repaints the
  /// classic way. A zoom past the stale tiles' reach leaves every visible
  /// span cold at once (~480 at 0.8px/frame over 24 rows), so the ~50
  /// frames after it each repainted all 24 rows by hand (p50 84ms, debug).
  @visibleForTesting
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// The rows shown now, each with the listeners of the painters that show
  /// it: they come as those painters are attached and go as they are
  /// detached ([noticesFor]), so a row nothing shows is not here.
  final Map<String, List<VoidCallback>> _shown = <String, List<VoidCallback>>{};

  /// Whether [row] is shown now and [painter] paints the live state — the
  /// only rows the store asks anything for of its own accord: a warm-up,
  /// or a request its queue once turned away.
  bool _showsLive(String row, TimelineTileRasterSource painter) =>
      _shown.containsKey(row) && _answersLive(painter);

  /// Whether [painter]'s resolvers still describe its rows: always, for a
  /// source that follows no live cut; for one that does, while its world
  /// is the live one ([_liveGeneration]).
  bool _answersLive(TimelineTileRasterSource painter) =>
      !painter.followsTheLiveCut ||
      painter.substrateGeneration == _liveGeneration;

  /// The rows the queue turned a request of away, each with the latest one
  /// it turned away — see [_revisitStarved].
  final LinkedHashMap<String, _TileRequest> _starved =
      LinkedHashMap<String, _TileRequest>();

  /// How many tiles it keeps. A span tile at 96px × a 28px row × DPR 2 ≈
  /// 42KB; 768 covers dozens of rows × the whole scroll neighborhood before
  /// it lets any go.
  static const int capacity = 768;

  /// How many tiles it keeps: [capacity] — lowered by a test that lands a
  /// few past it, where 769 would be as many real rasters. ⚠️TEST ONLY.
  @visibleForTesting
  int debugCapacity = capacity;

  /// The tiles, each with when it was last asked for — bounded by how
  /// many ([debugCapacity]), let go by the order a playhead's caches let go
  /// by ([_letGoWantedLatest]), and weighed for [tileImageBytes].
  ///
  /// 🚨A RUN READS THESE TILES IN ITS OWN ORDER, so they are let go by it
  /// (card playback-draws-frames-the-film-did-not-change-in, 2026-10-24).
  /// They were an `Lru`, whose own doc turns away a cache a playhead reads:
  /// a loop shows every page again, and the page used longest ago is the
  /// next one it shows. 🔬A cut whose lap held 793 tiles over these 768
  /// (13 rows × 61 spans, the user's project, Windows profile): of 431 and
  /// 508 shown landings two runs had, 309 and 182 were tiles let go and
  /// asked for again — and every shown span left cold kept the next pages'
  /// warm-up from starting ([_startWarming]).
  final Map<String, _Kept> _entries = <String, _Kept>{};

  /// What [_entries]' pictures weigh together.
  int _heldBytes = 0;

  /// One tick each time a tile is asked for — the recency that orders
  /// tiles wanted alike.
  int _clock = 0;

  /// What the tiles' pictures weigh resident, for the memory census.
  int get tileImageBytes => _heldBytes;

  /// The spans asked for and not rastered yet, the latest ask last — past
  /// 32 the oldest ask is turned away into [_starved]. The order a bounded
  /// cache lets go by, and so the one that keeps it.
  late final Lru<String, _TileRequest> _pending = Lru(
    limit: () => 32,
    letGo: (_, turnedAway) => _starved[turnedAway.row] = turnedAway,
  );

  bool _drainScheduled = false;

  /// The latest painter each row's paint asked through, with the device
  /// pixel ratio it asked at — whom a warm-up asks for its next page
  /// ([warmTheNextPage]).
  final Map<String, ({TimelineTileRasterSource painter, double ratio})>
  _askedBy = <String, ({TimelineTileRasterSource painter, double ratio})>{};

  /// The next pages' spans, rastered while no shown span waits — at most as
  /// many a warm-up as the run asked for ([warmTheNextPage]).
  final LinkedHashMap<String, _TileRequest> _warming =
      LinkedHashMap<String, _TileRequest>();

  /// The spans past the edges of the rows' windows ([warmAhead]): rastered
  /// as the next pages' are, but every one of them, by whichever warm-up
  /// runs.
  ///
  /// ⛔Not in [_warming]: a run asks for its pages a few spans each frame
  /// it changes its film frame in, and nothing asks at rest — a paint's
  /// spans there, held to that count, waited for a run that never came.
  final LinkedHashMap<String, _TileRequest> _ahead =
      LinkedHashMap<String, _TileRequest>();

  /// Whether a paint's [warmAhead] has a warm-up's start waiting for the
  /// paint phase to end.
  bool _warmScheduled = false;

  /// The keys a warm-up has in flight, and of those the ones a paint asked
  /// for meanwhile — whose landing tells the row, as a shown one's does.
  final Set<String> _warmInFlight = <String>{};
  final Set<String> _askedWhileWarm = <String>{};

  /// The keys a drain has taken off the queue and not landed yet.
  final Set<String> _inFlight = <String>{};

  /// The keys of [_inFlight] a paint baked meanwhile ([_landNow]) — from an
  /// ask newer than the drain's, so the drain's raster lands nothing.
  final Set<String> _overtaken = <String>{};

  /// Bumped by [clear]: what a drain begun before it was doing reaches
  /// nothing after it — its key is free at once, it counts as no drain,
  /// and its pixels land nowhere.
  ///
  /// 🚨A widget test's clock is fake, so a raster that awaits a real upload
  /// never lands in it: without the fence its key stayed in [_inFlight]
  /// into every later test of the file, and nothing there could ask for it
  /// again (found by `layer_timeline_grid_test`, where the order the tiles
  /// were baked in changed with it).
  int _epoch = 0;

  /// The drains running: from the moment one takes a request off the queue
  /// until its upload lands (or is discarded). With [_pending] this is the
  /// store's whole notion of "busy".
  ///
  /// ⚠️A COUNT, not a flag: a request made while a drain is suspended in a
  /// raster schedules another drain beside it, and the first to finish used
  /// to clear the flag while the other still had a raster in flight — idle
  /// by this word, busy in fact.
  int _drainsRunning = 0;

  /// Whether anything is queued or in flight. ⚠️TEST ONLY — the quiescence
  /// signal for tests that wait on tiles: waiting for SILENCE (no landing
  /// for N ms) misreads a slow drain on a loaded machine as a finished one,
  /// which is how `timeline_viewport_resize_test` went red in bulk runs and
  /// green alone (2026-09-03). Idle is the store's word, not a timer's.
  @visibleForTesting
  bool get debugBusy =>
      _drainsRunning > 0 || _pending.isNotEmpty || _warmScheduled;

  /// The substrate generation the LIVE paints carry — the newest
  /// [TimelineTileRasterSource.substrateGeneration] a [tileFor] call has
  /// seen of a source that follows the live cut
  /// ([TimelineTileRasterSource.followsTheLiveCut]). Paints only happen for
  /// the live state, so the last generation such a paint carried IS the
  /// live one; no host wiring, no setter to race.
  ///
  /// 🚨#29 프레임 블록 회색 깜빡임: a request captures the painter, but the
  /// painter's resolvers answer FROM THE LIVE SESSION at drain time
  /// (`celHasContentForLayer` reads `activeCutOrNull`). The drain is
  /// serial, up to 32 deep, with real async hops between rasters — so a
  /// cut switch mid-queue made every remaining request bake the OLD
  /// cut's rows against the NEW cut's answers: a miss, painted grey,
  /// stored, and served again later as a perfectly valid hit. A drained
  /// request whose generation is no longer live is DEAD, not stale —
  /// rastering it would consult resolvers that no longer describe its
  /// rows.
  String _liveGeneration = '';

  /// Lets go of every tile — a project closing (F-505: its tiles keep its
  /// session through the resolvers they were baked against), and tests.
  void clear() {
    for (final kept in _entries.values) {
      kept.entry.image.dispose();
    }
    _entries.clear();
    _heldBytes = 0;
    _pending.clear();
    _starved.clear();
    _inFlight.clear();
    _overtaken.clear();
    _warming.clear();
    _ahead.clear();
    _warmInFlight.clear();
    _askedWhileWarm.clear();
    _warmSpan.micros = 0;
    _drainsRunning = 0;
    _epoch += 1;
  }

  /// What a painter of the row of [layerId] along [axis], in the world
  /// [substrateGeneration], listens to for its tiles: a landing of one of
  /// THAT row's tiles, never another row's.
  Listenable noticesFor({
    required String substrateGeneration,
    required LayerId layerId,
    required Axis axis,
  }) => _RowNotices(this, _rowKey(substrateGeneration, layerId, axis));

  static String _rowKey(String generation, LayerId layerId, Axis axis) =>
      '$generation|${layerId.value}:${axis.index}';

  void _noticeLanding(String row) {
    for (final listener in [...?_shown[row]]) {
      listener();
    }
  }

  /// The substrate tile for [painter]'s span starting at [spanStartIndex]:
  /// the one it holds where that shows the span, one baked in this call
  /// where the span's look or content moved — or a stand-in while a word
  /// it sets is baked the first time, scaled while a zoom's raster lands,
  /// and null for a cold span (the classic paint covers this frame). What
  /// is not baked here is scheduled off the paint phase.
  ui.Image? tileFor({
    required TimelineTileRasterSource painter,
    required int spanStartIndex,
    required int spanEndIndexExclusive,
    required double devicePixelRatio,
  }) {
    final engine = QaNativeEngine.instance;
    if (engine == null) {
      return null;
    }
    if (painter.followsTheLiveCut) {
      _liveGeneration = painter.substrateGeneration;
    }
    // 🚨The generation is IN the key, not only compared later: the key is
    // deliberately the layer's ID (an edited layer is a NEW instance that
    // must find its old tile and show it stale while re-rastering), and
    // the same ID legitimately exists in other cuts — old files written
    // before PR #1070 even carry duplicate ids across cuts. Without the
    // generation, cut B's row was served cut A's pixels whenever the
    // geometry happened to match, which after a mid-drain poisoning is
    // exactly how a grey block went from "flicker" to "stays".
    final row = _rowKey(
      painter.substrateGeneration,
      painter.layer.id,
      painter.axis,
    );
    final asked = _TileRequest(
      row: row,
      painter: painter,
      spanStartIndex: spanStartIndex,
      spanEndIndexExclusive: spanEndIndexExclusive,
      devicePixelRatio: devicePixelRatio,
    );
    final key = asked.key;
    _askedBy[row] = (painter: painter, ratio: devicePixelRatio);
    final entry = _touched(key);
    if (entry != null && _shows(entry, asked)) {
      return entry.image;
    }
    // 🚨F-314 (유저 2026-10-08: 「코마 바꿀때 +나 N이나 코마텍스트 이런 위젯이랑
    // 블록이랑 위치 어긋나는 프레임 1프레임정도 … 1프레임도 위치 안어긋나게」):
    // A SPAN WHOSE LOOK OR CONTENT MOVED IS BAKED IN THE PAINT THAT ASKS.
    // The row's chrome follows an edit in the frame it lands in, so a tile
    // that came a frame later showed the block a step behind its own grips:
    // 🔬every one of a drag's steps did (8 of 8 — comma, +, a move, a move
    // to another row; Surface, 10-25), each tile ~0.3ms of ops and ~70µs of
    // raster through the door's picture ([pictureOf]), ~1.5 tiles a step.
    // A word never baked before is the one wait left: its bake reads the
    // word back ([bakeWordCoverage]), which a paint cannot wait for.
    final stale = entry != null && entry.hasTheGeometryOf(asked) ? entry : null;
    if (stale != null) {
      final baked = _landNow(engine, asked);
      if (baked != null) {
        return baked;
      }
    }
    // Cold or stale: schedule ONE raster per key (the newest look wins —
    // a stale in-flight request re-checks at drain time). The queue is
    // CAPPED (UI-R20 #4): a scrollbar teleport requests dozens of spans
    // per frame and most are passed before their raster would land —
    // dropping the OLDEST keeps the drain working on what is actually
    // on screen now. A row it turns away is not forgotten, though
    // ([_revisitStarved]).
    //
    // 🚨A tile being rastered is NOT asked for again ([_inFlight]): a row
    // repaints on each of its landings, and every repaint asked afresh for
    // the tiles still in flight — each ask a second raster, each landing
    // another repaint. Measured in the pin: 900 rasters of 19 tiles, 450
    // drains beside each other. Its landing repaints the row, which asks
    // then if the look moved meanwhile.
    // A span a warm-up still holds becomes a shown one's to raster first; one
    // a warm-up has in flight tells this row when it lands.
    if (!_inFlight.contains(key)) {
      _warming.remove(key);
      _ahead.remove(key);
      _enqueue(key, asked);
    } else if (_warmInFlight.contains(key)) {
      _askedWhileWarm.add(key);
    }
    // Stale-while-revalidate (UI-R20 #6, widened for R26 #27): WHATEVER
    // went stale — a look flip or a content edit (a new layer instance) —
    // keep showing the stale tile while the fresh raster lands, as long as
    // the GEOMETRY still matches (a mis-sized tile would stretch).
    // Dropping to the classic pass instead swaps text rendering
    // technologies for a frame (baked A8 glyphs ↔ TextPainter), which
    // reads as every glyph momentarily thinning/thickening.
    //
    // R9 #16: this used to fire on EVERY host rebuild, because the
    // resolver closures are method tear-offs and [_TileEntry.matches]
    // compared them with `identical` — which is false for two tear-offs of
    // the same method. That is fixed at the comparison, so the stale path
    // now runs only when something genuinely changed, and it stays as the
    // graceful landing for those cases. The drain rasters the NEWEST look
    // within a frame or two, so content lags one beat at most.
    // ↩️F-314: that beat was the frame the user saw the block part from its
    // grips in — the span is baked above now, and the stale tile stands in
    // only while a word it sets is baked the first time.
    // ⛔Both stale arms demand the GENERATION even though the key already
    // carries it: stale-while-revalidate exists precisely for "same row,
    // new instance", and without this term it is also "same id, other
    // cut" — the alias that turned a mid-drain grey from a flicker into
    // a resident.
    if (stale != null) {
      return stale.image;
    }
    // R27 #10: a ZOOM step changes the geometry of every visible tile at
    // once, and dropping all of them to the classic Dart pass is what
    // made zooming crawl. The tile covers the SAME frames either way and
    // the painter draws it into a `dst` rect built from the CURRENT
    // geometry — so the stale raster simply scales, the way every pro
    // timeline shows a stretched last frame while the real one renders.
    // Bounded so an extreme jump (a 10× slider throw) still takes the
    // crisp path rather than showing mush.
    if (entry != null &&
        entry.substrateGeneration == painter.substrateGeneration &&
        entry.spanEndIndexExclusive == spanEndIndexExclusive &&
        entry.devicePixelRatio == devicePixelRatio &&
        entry.crossAxisExtent == painter.crossAxisExtent &&
        _withinRescaleBand(entry.frameCellExtent, painter.frameCellExtent)) {
      return entry.image;
    }
    return null;
  }

  /// Bakes [asked]'s span in this call and keeps it — the picture the paint
  /// asking draws — or null while a word it sets has never been baked.
  /// What was asked for it before is answered by it, and a raster of it in
  /// flight lands nothing ([_overtaken]).
  ui.Image? _landNow(QaNativeEngine engine, _TileRequest asked) {
    final rastered = _rasterNow(engine, asked);
    if (rastered == null) {
      return null;
    }
    final key = asked.key;
    _pending.take(key);
    _warming.remove(key);
    _ahead.remove(key);
    if (_inFlight.contains(key)) {
      _overtaken.add(key);
    }
    _keep(key, asked, _entryOf(asked, rastered));
    revision.value += 1;
    return rastered.image;
  }

  /// The tile at [key], made the newest in the cache: a span asked for —
  /// shown, or warmed to be — is one about to be shown.
  _TileEntry? _touched(String key) {
    final kept = _entries[key];
    if (kept == null) {
      return null;
    }
    kept.lastUsed = ++_clock;
    return kept.entry;
  }

  /// Keeps [landed] at [key] for [request], disposing the tile it replaces,
  /// and lets go of the ones wanted latest while more than [debugCapacity]
  /// are kept — the one that landed, the newest, only where it is wanted
  /// after every other.
  void _keep(String key, _TileRequest request, _TileEntry landed) {
    final replaced = _entries.remove(key);
    if (replaced != null) {
      _heldBytes -= replaced.bytes;
      replaced.entry.image.dispose();
    }
    final kept = _Kept(
      landed,
      row: request.row,
      spanStartIndex: request.spanStartIndex,
      lastUsed: ++_clock,
    );
    _entries[key] = kept;
    _heldBytes += kept.bytes;
    _letGoWantedLatest();
  }

  /// Lets go of tiles, the one wanted latest first, until [debugCapacity]
  /// are kept: by [letGoWantedLatest], the one order playback's caches let
  /// go by — the least recently asked for first among tiles wanted alike,
  /// as an `Lru` would, which is every tile wherever nothing plays.
  void _letGoWantedLatest() {
    if (_entries.length <= debugCapacity) {
      return;
    }
    final shownBy = <String, _RowShows>{};
    letGoWantedLatest<MapEntry<String, _Kept>>(
      entries: [..._entries.entries],
      heldBytes: _entries.length,
      maxBytes: debugCapacity,
      wantedAt: (entry) => _wantedAt(entry.value, shownBy),
      lastUsed: (entry) => entry.value.lastUsed,
      bytesOf: (_) => 1,
      letGo: (entry) {
        _entries.remove(entry.key);
        _heldBytes -= entry.value.bytes;
        entry.value.entry.image.dispose();
      },
    );
  }

  /// How many steps on [kept] is next shown: none while a row on screen
  /// shows its span ([TimelineTileRasterSource.tileSpans]), as many as the
  /// playing run takes to show the span's first frame
  /// ([TimelineTileRasterSource.stepsUntilShown]) — and null, wanted by no
  /// step, for a tile of a row nothing shows, or wherever nothing plays.
  /// [shownBy] holds each row's answers for one letting go.
  int? _wantedAt(_Kept kept, Map<String, _RowShows> shownBy) {
    final asked = _shown.containsKey(kept.row) ? _askedBy[kept.row] : null;
    if (asked == null) {
      return null;
    }
    final (:shown, :stepsUntilShown) = shownBy.putIfAbsent(
      kept.row,
      () => (
        shown: asked.painter.tileSpans.shown,
        stepsUntilShown: asked.painter.stepsUntilShown,
      ),
    );
    final start = kept.spanStartIndex;
    final end = kept.entry.spanEndIndexExclusive;
    for (final (from, to) in shown) {
      if (start < to && from < end) {
        return 0;
      }
    }
    return stepsUntilShown?.call(start);
  }

  void _enqueue(String key, _TileRequest request) {
    _pending.keep(key, request);
    if (!_drainScheduled) {
      _drainScheduled = true;
      // Off the paint phase; microtasks run before the next frame, so a
      // tile can land within a frame or two.
      scheduleMicrotask(_drain);
    }
  }

  /// How far a stale tile may be stretched before the classic pass is the
  /// better answer.
  static bool _withinRescaleBand(double from, double to) {
    if (from <= 0 || to <= 0) {
      return false;
    }
    final ratio = to / from;
    return ratio >= 0.5 && ratio <= 2.0;
  }

  Future<void> _drain() async {
    _drainScheduled = false;
    final engine = QaNativeEngine.instance;
    if (engine == null) {
      _pending.clear();
      return;
    }
    final epoch = _epoch;
    _drainsRunning += 1;
    try {
      while (_pending.isNotEmpty) {
        final request = _pending.take(_pending.keys.first)!;
        if (!await _rasterAndLand(engine, request, epoch, warm: false)) {
          return;
        }
      }
      _revisitStarved();
    } finally {
      if (epoch == _epoch) {
        _drainsRunning -= 1;
        // What is on the screen is rastered; what is past it goes on. The
        // next pages wait for the run to ask again.
        _startWarming();
      }
    }
  }

  /// Rasters [request] and lands its tile — false when a [clear] fenced the
  /// drain off while it was in flight.
  ///
  /// A shown span's landing tells its row, which repaints with it. A warm
  /// one's tells nobody — the row does not show the span yet, and a repaint
  /// of a row for a tile it does not show is a frame drawn for nothing —
  /// unless a paint asked for it while it was in flight ([_askedWhileWarm]).
  Future<bool> _rasterAndLand(
    QaNativeEngine engine,
    _TileRequest request,
    int epoch, {
    required bool warm,
  }) async {
    final key = request.key;
    // A dead-generation request is discarded, not rastered: its painter's
    // resolvers answer from the live session, which no longer describes its
    // rows. ⛔This check and the resolver reads are one synchronous block —
    // `_raster` emits the substrate and collects the glyph cells before its
    // first await — so nothing can change the session between the check and
    // the answers it guards.
    if (!_answersLive(request.painter)) {
      return true;
    }
    _inFlight.add(key);
    if (warm) {
      _warmInFlight.add(key);
    }
    final _Rastered? rastered;
    try {
      rastered = await _raster(engine, request);
    } finally {
      if (epoch == _epoch) {
        _inFlight.remove(key);
        _warmInFlight.remove(key);
      }
    }
    if (epoch != _epoch) {
      rastered?.image.dispose();
      return false;
    }
    if (_overtaken.remove(key)) {
      _askedWhileWarm.remove(key);
      rastered?.image.dispose();
      return true;
    }
    if (rastered == null) {
      return true;
    }
    _keep(key, request, _entryOf(request, rastered));
    revision.value += 1;
    if (!warm || _askedWhileWarm.remove(key)) {
      // A row whose tile lands asks again for itself when it repaints —
      // coming back to it could only find an older painter.
      _starved.remove(request.row);
      _noticeLanding(request.row);
    }
    return true;
  }

  /// The tile [rastered] makes of [request]: the look its painter states,
  /// and what the raster read.
  static _TileEntry _entryOf(_TileRequest request, _Rastered rastered) {
    final painter = request.painter;
    final emitted = rastered.emitted;
    return _TileEntry(
      substrateGeneration: painter.substrateGeneration,
      layer: painter.layer,
      coverageIdentity: painter.coverageIdentity,
      frameCellExtent: painter.frameCellExtent,
      crossAxisExtent: painter.crossAxisExtent,
      colorScheme: painter.colorScheme,
      exposureStateForLayer: painter.exposureStateForLayer,
      frameNameForLayer: painter.frameNameForLayer,
      celHasContentForLayer: painter.celHasContentForLayer,
      // ⛔The revision the RASTER sampled, never a live read. `_raster`
      // suspends between its content reads and this landing (the glyph A8
      // bake, the ImmutableBuffer upload are real awaits), so a crossing
      // that bumps the revision inside that window would give pixels of
      // revision N a stamp of N+1 — and `showsNow` trusts the NUMBER, so
      // the poisoned tile was served as fresh forever (the LRU survives cut
      // trips and the 'projectId:cutId' string is reproduced exactly on
      // return; only the NEXT bump healed it).
      celContentRevision: emitted.celContentRevision,
      substrate: emitted.substrate,
      baseTextStyle: painter.baseTextStyle,
      spanEndIndexExclusive: request.spanEndIndexExclusive,
      devicePixelRatio: request.devicePixelRatio,
      paperGround: painter.paperGround,
      blockFrameLines: painter.blockFrameLines,
      unnamedMark: painter.unnamedMark,
      framesPerSecond: painter.framesPerSecond,
      shown: painter.shown,
      image: rastered.image,
      ink: emitted.ink,
    );
  }

  /// 🚨A RUN'S NEXT PAGE IS BAKED WHILE IT PLAYS THE PAGE BEFORE (유저
  /// 2026-10-11: 「144hz든 몇이든 확실하게 근본/구조적으로 해결하도록」).
  ///
  /// A page turn used to bring every row's next spans under the window at
  /// once, cold: 🔬40-odd tiles and their words rastered, baked and
  /// uploaded in the frames right after the turn (profile, 144Hz, a cut of
  /// 132 frames, first loop) — the raster thread held 20–35ms, the UI
  /// thread long enough that the clock's next look came a refresh late, and
  /// a film frame shown seven refreshes long beside one five long at every
  /// turn. Asked for here instead, a few spans at a time, after each frame a
  /// clock's look changed what it shows — and rastered, baked and uploaded
  /// only in the quiet between that frame's raster and the next held one
  /// ([QuietTurns]): a first attempt that began them straight after the
  /// frame had their uploads running beside its raster, which they slowed
  /// past its vblank.
  ///
  /// [tiles] at most a call, and none while any raster is under way: the
  /// surfaces that turn their pages in one frame start one warm-up between
  /// them, and what is on the screen is rastered first ([tileFor] takes a
  /// span over from here), and what is past it next ([warmAhead]).
  ///
  /// Where the turn stands an axis is asked of its owner once a call, and
  /// every row it lays cuts its spans from that one answer
  /// ([TimelineTileRasterSource.nextPage]) — the run's end it reads is the
  /// cut's drawn length, worked out again at each asking.
  void warmTheNextPage({int tiles = 6}) {
    if (QaNativeEngine.instance == null) {
      return;
    }
    final pages = <TimelineNextPage? Function(), TimelineNextPage?>{};
    for (final MapEntry(key: row, value: (:painter, :ratio))
        in _askedBy.entries) {
      final ask = painter.nextPage;
      if (ask == null || !_showsLive(row, painter)) {
        continue;
      }
      final page = pages.putIfAbsent(ask, ask);
      if (page == null) {
        continue;
      }
      for (final (start, end) in painter.tileSpansOfThePage(page)) {
        _warm(
          _warming,
          _TileRequest(
            row: row,
            painter: painter,
            spanStartIndex: start,
            spanEndIndexExclusive: end,
            devicePixelRatio: ratio,
          ),
        );
      }
    }
    _startWarming(pageTiles: tiles);
  }

  /// The span past either edge of [painter]'s window, asked for so a
  /// scroll — or a page turn — finds it warm: rastered as the next page is
  /// ([warmTheNextPage]), once no shown span waits and in the quiet between
  /// held frames, and its landing repaints nothing. Every such span is
  /// rastered by the next warm-up that runs, a run's or not ([_ahead]).
  ///
  /// ↩️It was asked for as a shown span ([tileFor]): rastered at once,
  /// beside whatever frame was under way, and its landing repainted a row
  /// that does not show it. 🔬A playing timeline's turn brings every row
  /// one such span — the first of the page after the new one — so every
  /// row repainted a few frames after every turn, and the dock's still
  /// region read each row as moving and was taken again when they stopped
  /// (10-12, cut 302 at 144Hz: about two images a page).
  void warmAhead({
    required TimelineTileRasterSource painter,
    required int spanStartIndex,
    required int spanEndIndexExclusive,
    required double devicePixelRatio,
  }) {
    if (QaNativeEngine.instance == null) {
      return;
    }
    _warm(
      _ahead,
      _TileRequest(
        row: _rowKey(
          painter.substrateGeneration,
          painter.layer.id,
          painter.axis,
        ),
        painter: painter,
        spanStartIndex: spanStartIndex,
        spanEndIndexExclusive: spanEndIndexExclusive,
        devicePixelRatio: devicePixelRatio,
      ),
    );
    if (_ahead.isEmpty || _warmScheduled) {
      return;
    }
    _warmScheduled = true;
    // Off the paint phase, as a shown span's drain is ([_enqueue]).
    scheduleMicrotask(() {
      _warmScheduled = false;
      _startWarming();
    });
  }

  /// Queues [request] in [queue] unless a tile shows its span already or
  /// it is on its way. One the next page's warm-up holds moves to [_ahead]
  /// when a paint asks for it there.
  void _warm(
    LinkedHashMap<String, _TileRequest> queue,
    _TileRequest request,
  ) {
    final key = request.key;
    if (_inFlight.contains(key) ||
        _pending.containsKey(key) ||
        _ahead.containsKey(key) ||
        queue.containsKey(key)) {
      return;
    }
    final entry = _touched(key);
    if (entry != null && _shows(entry, request)) {
      return;
    }
    _warming.remove(key);
    queue[key] = request;
  }

  /// Starts a warm-up when no raster is under way and it has something to
  /// warm — what is on the screen is rastered first.
  void _startWarming({int pageTiles = 0}) {
    final engine = QaNativeEngine.instance;
    if (engine != null &&
        _drainsRunning == 0 &&
        _warmQueue(pageTiles) != null) {
      unawaited(_drainWarm(engine, pageTiles));
    }
  }

  /// Where a warm-up takes its next span from: past the windows' edges
  /// while any is left there, then the next pages' while it has [pageTiles]
  /// of them left to take — and nowhere while a shown span waits.
  LinkedHashMap<String, _TileRequest>? _warmQueue(int pageTiles) {
    if (_pending.isNotEmpty) {
      return null;
    }
    if (_ahead.isNotEmpty) {
      return _ahead;
    }
    return pageTiles > 0 && _warming.isNotEmpty ? _warming : null;
  }

  Future<void> _drainWarm(QaNativeEngine engine, int pageTiles) async {
    final epoch = _epoch;
    _drainsRunning += 1;
    var pagesLeft = pageTiles;
    try {
      while (_warmQueue(pagesLeft) != null) {
        // 🚨A WARM SPAN IS RASTERED, BAKED AND UPLOADED IN THE QUIET
        // BETWEEN TWO HELD FRAMES ([QuietTurns]): turned away — no room, or
        // a [clear] came while it waited — the warm-up goes on after the
        // next held frame, which asks again ([warmTheNextPage]). With
        // nothing held there is no quiet to keep, and a warm span is taken
        // in the same turn as the call that asked for it, as it always was.
        final turn = await quietTurns.inThisQuiet(
          _warmSpan,
          gone: () => epoch != _epoch,
        );
        if (turn == null) {
          return;
        }
        var landed = false;
        try {
          final queue = _warmQueue(pagesLeft);
          if (queue == null) {
            return;
          }
          if (identical(queue, _warming)) {
            pagesLeft -= 1;
          }
          final request = queue.remove(queue.keys.first)!;
          landed = await _rasterAndLand(engine, request, epoch, warm: true);
          if (!landed) {
            return;
          }
        } finally {
          // The next span is asked for once the GPU is done with this one:
          // turns are first come, first served, and a job that asked
          // meanwhile goes before it.
          await (landed ? turn.landed() : turn.gaveUp());
        }
      }
    } finally {
      if (epoch == _epoch) {
        _drainsRunning -= 1;
      }
    }
  }

  /// Where a warm-up takes its turns in the quiet between held frames.
  @visibleForTesting
  QuietTurns quietTurns = QuietTurns.instance;

  /// How long a warm span took from its raster to its landing, at the most
  /// of late — what one more has to fit in before the quiet ends.
  final QuietSpan _warmSpan = QuietSpan();

  /// Once the queue has run dry, asks again for the first row it turned
  /// away that is still shown — through the latest request it turned away,
  /// for the spans that row's painter shows NOW
  /// ([TimelineTileRasterSource.tileSpans]), not the ones it was showing.
  ///
  /// Every landing used to repaint every row, and those repaints asked again
  /// for whatever the cap had dropped. A landing repaints its own row now,
  /// and a row whose every request was turned away has none coming — so
  /// without this it kept the classic paint until something else repainted
  /// it (and then paid the classic pass again).
  ///
  /// One row at a time, and never by repainting it: a painter that is
  /// shown but not being painted (an offstage tab) would never ask.
  void _revisitStarved() {
    while (_starved.isNotEmpty) {
      final row = _starved.keys.first;
      final request = _starved.remove(row)!;
      final painter = request.painter;
      if (!_showsLive(row, painter)) {
        continue;
      }
      final (:shown, :ahead) = painter.tileSpans;
      final landings = revision.value;
      for (final (start, end) in shown) {
        tileFor(
          painter: painter,
          spanStartIndex: start,
          spanEndIndexExclusive: end,
          devicePixelRatio: request.devicePixelRatio,
        );
      }
      // A span the ask bakes in itself lands there ([_landNow]) — with no
      // paint under way to draw it, so the row hears of it.
      if (revision.value != landings) {
        _noticeLanding(row);
      }
      for (final (start, end) in ahead) {
        _warm(
          _ahead,
          _TileRequest(
            row: row,
            painter: painter,
            spanStartIndex: start,
            spanEndIndexExclusive: end,
            devicePixelRatio: request.devicePixelRatio,
          ),
        );
      }
      if (_pending.isNotEmpty) {
        return;
      }
    }
  }

  // --- Glyph A8 bake cache (T3) ---------------------------------------
  //
  // Foreground glyphs bake ONCE per (text, shape-style, DPR) into an A8
  // coverage bitmap (white text rendered off-screen, alpha extracted);
  // tiles blit them through the op stream's GLYPH op, tinted with the
  // painter's exact ink per cell.

  static const int _glyphCapacity = 1024;
  final BakeOnceLru<String, BakedWordCoverage?> _glyphs =
      BakeOnceLru<String, BakedWordCoverage?>(capacity: _glyphCapacity);

  /// ⚠️The narrowing is part of the glyph (B, 유저 2026-09-24): a word that
  /// runs past its block is baked narrow, and [wordCondensation] quantises
  /// the factor so the distinct bakes stay few. So is the spacing its letter
  /// gaps gave way to first (F-234-Q1, [wordTightening] — quarter pixels).
  static String _glyphKey(String text, TextStyle style, _GlyphBake at) =>
      '$text|${style.fontSize}|${style.fontWeight}|${style.fontStyle}|'
      '${style.fontFamily}|${style.letterSpacing}|${at.tightening}|'
      '${at.dpr}|${at.fit.x}|${at.fit.y}';

  Future<BakedWordCoverage?> _glyphA8(
    String text,
    TextStyle style,
    _GlyphBake at,
  ) {
    final key = _glyphKey(text, style, at);
    return _glyphs.ensure(key, () => _bakeGlyph(text, style, at));
  }

  Future<BakedWordCoverage?> _bakeGlyph(
    String text,
    TextStyle style,
    _GlyphBake at,
  ) {
    final (:dpr, :fit, :tightening) = at;
    // COVERAGE bake: white text on transparent, alpha channel out — the
    // GLYPH op multiplies the per-cell ink's alpha by it. Rasterised big and
    // shrunk where it is small ([bakeWordCoverage], the bake a screen draws
    // a narrowed word from too, F-224).
    //
    // ⛔AND THE ATLAS STAYS 1:1. The GLYPH op blits without a scale
    // parameter, so the shrink and the narrowing happen in the bake, before
    // upload; the native ABI is untouched.
    return bakeWordCoverage(
      laidOutGlyph(
        text,
        style.copyWith(color: const Color(0xFFFFFFFF)),
        tightening: tightening,
      ),
      fit: fit,
      dpr: dpr,
      fontSize: style.fontSize,
    );
  }

  /// Rasters the request and returns the image TOGETHER WITH the content
  /// revision the raster's answers described and the substrate it laid
  /// down — both sampled in the same synchronous block as the substrate
  /// emit, so pixels, stamp and substrate can never disagree.
  Future<_Rastered?> _raster(
    QaNativeEngine engine,
    _TileRequest request,
  ) async {
    final emitted = _emit(request);
    if (emitted == null) {
      return null;
    }
    final words = await _bakedWords(emitted.ink.glyphs);
    final pixels = _pixelsOf(engine, request, emitted, words);
    if (pixels == null) {
      return null;
    }
    final image = await _upload(pixels, emitted.tileWidth, emitted.tileHeight);
    return (image: image, emitted: emitted);
  }

  /// [_raster] within the call, the picture made through the door
  /// ([pictureOf]) — or null while a word the span sets has never been
  /// baked.
  _Rastered? _rasterNow(QaNativeEngine engine, _TileRequest request) {
    final emitted = _emit(request);
    if (emitted == null) {
      return null;
    }
    final words = _bakedWordsNow(emitted.ink.glyphs);
    if (words == null) {
      return null;
    }
    final pixels = _pixelsOf(engine, request, emitted, words);
    if (pixels == null) {
      return null;
    }
    return (
      image: pictureOf(
        _TileBytes(pixels, emitted.tileWidth, emitted.tileHeight),
      ),
      emitted: emitted,
    );
  }

  /// The request's span laid as ops up to its words ([_setWords]) — its
  /// tile's size, and the revision, the substrate and the ink the ops
  /// describe — or null for a span with no pixels. ⛔Synchronous, every
  /// answer of it read in one block.
  _Emitted? _emit(_TileRequest request) {
    final painter = request.painter;
    final dpr = request.devicePixelRatio;
    final spanCells = request.spanEndIndexExclusive - request.spanStartIndex;
    if (spanCells <= 0) {
      return null;
    }
    final horizontal = painter.axis == Axis.horizontal;
    // The span's cells as the painter lays them — the frame axis' one law,
    // so a tile is exactly as long as the cells it holds at any zoom.
    final first = painter.cellRectFor(request.spanStartIndex);
    final last = painter.cellRectFor(request.spanEndIndexExclusive - 1);
    final spanExtent =
        endAlong(painter.axis, last) - startAlong(painter.axis, first);
    final width = (spanExtent * dpr).ceil();
    final height = (painter.crossAxisExtent * dpr).ceil();
    if (width <= 0 || height <= 0) {
      return null;
    }
    final tileWidth = horizontal ? width : height;
    final tileHeight = horizontal ? height : width;

    final writer = TimelineGridTileOpWriter();
    // Sampled HERE — the substrate emit below reads every content answer
    // (`celHasContentForLayer` per cell) in this same synchronous block,
    // and nothing can bump the revision inside one block. This value is
    // what the pixels actually describe; the drain stamps it verbatim.
    final sampledCelContentRevision = painter.celContentRevision;
    // ONE pass over the span's cells for the paper and the ink both — every
    // cell the two ask for is resolved once, as in a paint.
    final (:substrate, :ink) = painter.readInOnePass(
      () => (
        substrate: timelineGridEmitSubstrate(
          writer,
          painter: painter,
          spanStartIndex: request.spanStartIndex,
          spanEndIndexExclusive: request.spanEndIndexExclusive,
          devicePixelRatio: dpr,
        ),
        ink: _inkOf(
          painter,
          spanStartIndex: request.spanStartIndex,
          spanEndIndexExclusive: request.spanEndIndexExclusive,
          devicePixelRatio: dpr,
        ),
      ),
    );
    writer.append(ink.ops);
    return (
      writer: writer,
      tileWidth: tileWidth,
      tileHeight: tileHeight,
      celContentRevision: sampledCelContentRevision,
      substrate: substrate,
      ink: ink,
    );
  }

  /// [emitted]'s span with [words] set over it ([_setWords]), rastered by
  /// [engine] into the tile's premultiplied bytes — null where it refused.
  static Uint8List? _pixelsOf(
    QaNativeEngine engine,
    _TileRequest request,
    _Emitted emitted,
    Map<String, BakedWordCoverage> words,
  ) {
    final writer = emitted.writer;
    final atlas = _setWords(
      writer,
      emitted.ink.glyphs,
      words,
      devicePixelRatio: request.devicePixelRatio,
    );
    final pixels = Uint8List(emitted.tileWidth * emitted.tileHeight * 4);
    final result = engine.gridRasterTileBytes(
      pixels: pixels,
      tileWidth: emitted.tileWidth,
      tileHeight: emitted.tileHeight,
      backgroundRgba: 0,
      ops: writer.build(),
      atlas: atlas?.alpha,
      atlasWidth: atlas?.width ?? 0,
      atlasHeight: atlas?.height ?? 0,
    );
    if (result != 0) {
      assert(false, 'qa_grid_raster_tile failed: $result');
      return null;
    }
    return pixels;
  }

  /// The ink [painter]'s span [spanStartIndex, spanEndIndexExclusive) bakes
  /// over its substrate: the ops of its marks, and the words it sets — what
  /// a raster writes, and what a tile it holds is asked against
  /// ([_TileEntry.showsNow]).
  _TileInk _inkOf(
    TimelineTileRasterSource painter, {
    required int spanStartIndex,
    required int spanEndIndexExclusive,
    required double devicePixelRatio,
  }) => painter.readInOnePass(() {
    final writer = TimelineGridTileOpWriter();
    final glyphs = _emitForeground(
      writer,
      painter: painter,
      spanStartIndex: spanStartIndex,
      spanEndIndexExclusive: spanEndIndexExclusive,
      devicePixelRatio: devicePixelRatio,
    );
    return (ops: writer.build(), glyphs: glyphs);
  });

  /// Whether [entry] shows what [asked] would bake now — its ink read only
  /// when the answer turns on it.
  bool _shows(_TileEntry entry, _TileRequest asked) => entry.showsNow(
    asked,
    inkNow: () => _inkOf(
      asked.painter,
      spanStartIndex: asked.spanStartIndex,
      spanEndIndexExclusive: asked.spanEndIndexExclusive,
      devicePixelRatio: asked.devicePixelRatio,
    ),
  );

  /// The op stream [_emitForeground] writes for a span — what a tile bakes
  /// over its substrate, readable without a native engine.
  @visibleForTesting
  Future<Int32List> debugForegroundOps({
    required TimelineTileRasterSource painter,
    required int spanStartIndex,
    required int spanEndIndexExclusive,
    required double devicePixelRatio,
  }) async {
    final ink = _inkOf(
      painter,
      spanStartIndex: spanStartIndex,
      spanEndIndexExclusive: spanEndIndexExclusive,
      devicePixelRatio: devicePixelRatio,
    );
    final writer = TimelineGridTileOpWriter()..append(ink.ops);
    _setWords(
      writer,
      ink.glyphs,
      await _bakedWords(ink.glyphs),
      devicePixelRatio: devicePixelRatio,
    );
    return writer.build();
  }

  /// Emits the span's FOREGROUND ink (T3), a ghost's aside (F-446) — the
  /// in-between marks inline — and answers the words it writes, for
  /// [_setWords] to set through the A8 atlas: geometry and ink probed from
  /// the painter (the substrate's fidelity rule).
  ///
  /// ⛔SYNCHRONOUS, so it can run inside the painter's one pass
  /// ([TimelineTileRasterSource.readInOnePass]) — every answer it reads is
  /// the session's, and a word's first bake after it awaits.
  List<_TileGlyph> _emitForeground(
    TimelineGridTileOpWriter writer, {
    required TimelineTileRasterSource painter,
    required int spanStartIndex,
    required int spanEndIndexExclusive,
    required double devicePixelRatio,
  }) {
    final dpr = devicePixelRatio;
    final axis = painter.axis;
    final toLocal = offsetAlong(
      axis,
      along: -startAlong(axis, painter.cellRectFor(spanStartIndex)),
      across: 0,
    );

    final glyphCells = <_TileGlyph>[];
    // F-96: a word may start before the span and grow into it, so the
    // earlier word that does is baked too — the tile's own edge cuts what
    // lies outside it, the way it cuts a word that grows past the span's end.
    // 🗣️F-446: ↩️the nearest earlier word, whether it reached or not — so a
    // tile showed the same pixels from two layers and baked them apart.
    final lead = painter.bakedWordGrowingInto(spanStartIndex);
    for (final frameIndex in [
      ?lead,
      ...painter.bakedWritingCellsIn(spanStartIndex, spanEndIndexExclusive),
    ]) {
      final model = painter.cellModelAt(frameIndex);
      final mark = model.mark;
      if (mark != null) {
        final place = painter.inbetweenMarkLayoutFor(frameIndex);
        final center = place.center + toLocal;
        writer.inbetweenMark(
          mark,
          Rect.fromCenter(
            center: center * dpr,
            width: place.size.width * dpr,
            height: place.size.height * dpr,
          ),
          rgba: timelineGridPackRgba(painter.foregroundInkFor(model)),
          devicePixelRatio: dpr,
        );
        continue;
      }
      if (model.glyph.isEmpty) {
        continue;
      }
      final ink = painter.foregroundInkFor(model);
      // Set, laid and narrowed where the classic pass sets it — its letter
      // gaps first ([TimelineTileRasterSource.cellWordSetFor]).
      final style = painter.glyphStyleFor(model);
      final layout = painter.cellWordSetFor(frameIndex, model.glyph, style);
      final bake = (
        dpr: dpr,
        fit: layout.fit,
        tightening: layout.tightening,
      );
      glyphCells.add((
        text: model.glyph,
        style: style,
        rgba: timelineGridPackRgba(ink),
        key: _glyphKey(model.glyph, style, bake),
        bake: bake,
        origin: layout.origin + toLocal,
      ));
    }
    // ↩️The holds' lines were baked here as capsules. A hold is a ghost's,
    // and a ghost is the row's to lay over its tiles (F-446).
    return glyphCells;
  }

  /// The [glyphs] [_emitForeground] answered, baked into A8 coverage, each
  /// once ([_glyphA8]) — by their keys, a word whose bake made nothing left
  /// out.
  Future<Map<String, BakedWordCoverage>> _bakedWords(
    List<_TileGlyph> glyphs,
  ) async {
    final baked = <String, BakedWordCoverage>{};
    for (final cell in glyphs) {
      if (baked.containsKey(cell.key)) {
        continue;
      }
      final glyph = await _glyphA8(cell.text, cell.style, cell.bake);
      if (glyph != null) {
        baked[cell.key] = glyph;
      }
    }
    return baked;
  }

  /// [_bakedWords] as the words stand baked — null while any of them has
  /// never been.
  Map<String, BakedWordCoverage>? _bakedWordsNow(List<_TileGlyph> glyphs) {
    final baked = <String, BakedWordCoverage>{};
    for (final cell in glyphs) {
      if (!_glyphs.isDone(cell.key)) {
        return null;
      }
      final glyph = _glyphs.peek(cell.key);
      if (glyph != null) {
        baked[cell.key] = glyph;
      }
    }
    return baked;
  }

  /// Writes the GLYPH ops of the [glyphs] [baked] holds — returns the
  /// transient atlas those ops reference, or null (no word to set).
  static _TileAtlas? _setWords(
    TimelineGridTileOpWriter writer,
    List<_TileGlyph> glyphs,
    Map<String, BakedWordCoverage> baked, {
    required double devicePixelRatio,
  }) {
    final dpr = devicePixelRatio;
    if (baked.isEmpty) {
      return null;
    }

    // Transient atlas: the span's distinct glyphs stacked vertically.
    var atlasWidth = 0;
    var atlasHeight = 0;
    final rowOf = <String, int>{};
    for (final entry in baked.entries) {
      rowOf[entry.key] = atlasHeight;
      atlasHeight += entry.value.height;
      if (entry.value.width > atlasWidth) {
        atlasWidth = entry.value.width;
      }
    }
    final atlas = Uint8List(atlasWidth * atlasHeight);
    for (final entry in baked.entries) {
      final glyph = entry.value;
      final rowStart = rowOf[entry.key]!;
      for (var y = 0; y < glyph.height; y += 1) {
        atlas.setRange(
          (rowStart + y) * atlasWidth,
          (rowStart + y) * atlasWidth + glyph.width,
          glyph.alpha,
          y * glyph.width,
        );
      }
    }

    for (final cell in glyphs) {
      final glyph = baked[cell.key];
      if (glyph == null) {
        continue;
      }
      // The bake pads 1 physical px on each side.
      final destX = (cell.origin.dx * dpr).round() - 1;
      final destY = (cell.origin.dy * dpr).round() - 1;
      writer.glyph(
        destX,
        destY,
        0,
        rowOf[cell.key]!,
        glyph.width,
        glyph.height,
        cell.rgba,
      );
    }
    return _TileAtlas(width: atlasWidth, height: atlasHeight, alpha: atlas);
  }

  Future<ui.Image> _upload(
    Uint8List pixels,
    int tileWidth,
    int tileHeight,
  ) async {
    return uploadRawRgba(pixels, width: tileWidth, height: tileHeight);
  }
}

class _TileRequest {
  const _TileRequest({
    required this.row,
    required this.painter,
    required this.spanStartIndex,
    required this.spanEndIndexExclusive,
    required this.devicePixelRatio,
  });

  /// The row the tile belongs to — whose painters hear it land.
  final String row;
  final TimelineTileRasterSource painter;
  final int spanStartIndex;
  final int spanEndIndexExclusive;
  final double devicePixelRatio;

  /// The store's key for the tile: the row and the frame its span starts on.
  String get key => keyOf(row, spanStartIndex);

  static String keyOf(String row, int spanStartIndex) => '$row:$spanStartIndex';
}

/// A row's side of the store's landing notices ([TimelineGridTileStore.
/// noticesFor]): its painter adds a listener when it is attached and
/// removes it when it is detached, so the store holds a row only while
/// something shows it.
class _RowNotices implements Listenable {
  const _RowNotices(this._store, this._row);

  final TimelineGridTileStore _store;
  final String _row;

  @override
  void addListener(VoidCallback listener) =>
      _store._shown.putIfAbsent(_row, () => <VoidCallback>[]).add(listener);

  @override
  void removeListener(VoidCallback listener) {
    final listeners = _store._shown[_row];
    if (listeners == null) {
      return;
    }
    listeners.remove(listener);
    if (listeners.isEmpty) {
      _store._shown.remove(_row);
      _store._askedBy.remove(_row);
    }
  }
}

/// A word a tile writes: its text and type, its ink, its bake key, how far it
/// is narrowed, and where it lands in the tile (logical px from the span's
/// start).
typedef _TileGlyph = ({
  String text,
  TextStyle style,
  int rgba,
  String key,
  _GlyphBake bake,
  Offset origin,
});

/// How a word's glyph is baked: at the device pixel ratio, narrowed by its
/// fit, and set as tight as its letter gaps gave way (F-234-Q1).
typedef _GlyphBake = ({double dpr, WordFit fit, double tightening});

/// A span as a raster lays it before it sets a word
/// ([TimelineGridTileStore._emit]): the op stream, the tile's size, and the
/// revision, the substrate and the ink the ops describe — read in one
/// synchronous block.
typedef _Emitted = ({
  TimelineGridTileOpWriter writer,
  int tileWidth,
  int tileHeight,
  int celContentRevision,
  TimelineRowSubstrate substrate,
  _TileInk ink,
});

/// What a raster hands its landing: the picture, and what it shows.
typedef _Rastered = ({ui.Image image, _Emitted emitted});

/// A tile's pixels as the door ([pictureOf]) reads them: the raster's own
/// premultiplied bytes, and on the road that draws them the straight bytes
/// that premultiply back to them ([straightRgbaFor]).
class _TileBytes implements PictureBytes {
  const _TileBytes(this._premultiplied, this.width, this.height);

  final Uint8List _premultiplied;

  @override
  final int width;

  @override
  final int height;

  @override
  T readPremultiplied<T>(T Function(Uint8List premultiplied) use) =>
      use(_premultiplied);

  @override
  T readStraight<T>(T Function(Uint8List straight) use) =>
      use(straightRgbaFor(_premultiplied));
}

/// The ink a tile bakes over its substrate ([TimelineGridTileStore._inkOf]):
/// the ops its marks write, and the words it sets.
typedef _TileInk = ({Int32List ops, List<_TileGlyph> glyphs});

/// What a row's latest painter answers for one letting go
/// ([TimelineGridTileStore._wantedAt]): the spans it shows now, and how many
/// steps on a playing run shows a frame of it.
typedef _RowShows = ({
  List<(int, int)> shown,
  int? Function(int frame)? stepsUntilShown,
});

/// A tile the store keeps, with the row and the frame its span starts on —
/// what its key names — and when a paint or a warm-up last asked for it.
class _Kept {
  _Kept(
    this.entry, {
    required this.row,
    required this.spanStartIndex,
    required this.lastUsed,
  }) : bytes = estimatedImageBytes(entry.image.width, entry.image.height);

  final _TileEntry entry;
  final String row;
  final int spanStartIndex;
  final int bytes;
  int lastUsed;
}

class _TileEntry {
  _TileEntry({
    required this.substrateGeneration,
    required this.layer,
    required this.coverageIdentity,
    required this.frameCellExtent,
    required this.crossAxisExtent,
    required this.colorScheme,
    required this.exposureStateForLayer,
    required this.frameNameForLayer,
    required this.celHasContentForLayer,
    required this.celContentRevision,
    required this.substrate,
    required this.baseTextStyle,
    required this.spanEndIndexExclusive,
    required this.devicePixelRatio,
    required this.paperGround,
    required this.blockFrameLines,
    required this.unnamedMark,
    required this.framesPerSecond,
    required this.shown,
    required this.image,
    required this.ink,
  });

  /// #29: the (project, cut) world this tile's resolvers answered from.
  /// Redundant with the key today — and REQUIRED here anyway, so that if
  /// the key ever loses its generation segment the stale arms below still
  /// refuse to serve one cut's pixels to another. A silent regression is
  /// the one failure mode a cache is not allowed to have.
  final String substrateGeneration;

  /// The layer the tile shows: the one it was baked from, or a later one
  /// that bakes this span the same ([showsNow]), which it takes on.
  Layer layer;

  /// ㉘: what the row's coverage follows when it is not the layer — a
  /// camera row's keys live on `cut.camera`, so a tile baked before a key
  /// was added kept matching forever and served the old picture back.
  final Object? coverageIdentity;

  final double frameCellExtent;
  final double crossAxisExtent;
  final Object colorScheme;
  final Object exposureStateForLayer;
  final Object? frameNameForLayer;
  final Object? celHasContentForLayer;

  /// The RESOLVER above answers per cell, so its identity says nothing
  /// about whether a cel just gained pixels — a fresh stroke left this
  /// tile "matching" and serving the old grey back. The revision is the
  /// content's own version — the value `_raster` SAMPLED alongside its
  /// content reads, never a live read at store time (a crossing landing
  /// mid-raster would stamp pre-crossing pixels as post-crossing and
  /// [showsNow] would serve them fresh forever).
  ///
  /// It moves only in [showsNow], to a newer revision whose substrate
  /// it finds this tile's own, read in one synchronous block.
  int celContentRevision;

  /// The paper and lines `_raster` laid down — read in the same block as
  /// [celContentRevision]. Every pixel the content answers can reach is in
  /// here, or moves with it: the ink over it asks the content only through
  /// its block's state, and an empty block's grey words come with its
  /// ground for paper (I-129) — never a word changed on a paper that did
  /// not.
  final TimelineRowSubstrate substrate;

  final TextStyle baseTextStyle;
  final int spanEndIndexExclusive;
  final double devicePixelRatio;

  /// I-44: what the unworked paper was pre-blended onto.
  final Color? paperGround;

  /// Whether the frame lines crossed the paper, and the fps that made a
  /// second boundary's line the strongest. I-44 took both out of the key
  /// when it took the lines off the blocks; the user's switch (2026-09-24)
  /// can put the lines back, and a flip of it must re-bake — a stale tile
  /// would otherwise keep the other look until an unrelated bump.
  final bool blockFrameLines;
  final int framesPerSecond;

  /// The mark a drawing with no name wore — the user's pick (F-489), which
  /// moves no layer, so a pick anew must re-bake as the frame lines' flip
  /// does.
  final InbetweenMark unnamedMark;

  /// Whether the row was shown — a folder's flip hides its rows without
  /// making a new layer of any of them, so it is no fact of the layer's
  /// (I-129).
  final bool shown;

  final ui.Image image;

  /// The ink `_raster` baked over [substrate] — read in the same pass.
  final _TileInk ink;

  /// Whether this tile shows [asked]'s span as the row is now. Asked
  /// alike by every asker: a span shown, past the window or a page away.
  ///
  /// The look it was rastered for shows itself. Where what it was baked
  /// FROM moved — the cels' revision, or the layer within the tile's reach
  /// ([_showsSameCellsAs]) — it still shows the row when the span would
  /// bake the same now, and it takes the new revision and layer instead of
  /// a raster. [inkNow] is the span's ink as it would bake now; it is asked
  /// only when the layer moved, for what the content answers move in the
  /// ink moves the paper with it ([substrate]).
  ///
  /// 🚨THE REVISION IS ONE NUMBER FOR THE WHOLE TIMELINE (F-166). It bumps
  /// when the pen goes down or up and on every committed stroke, so every
  /// visible tile of every row went stale three times a stroke and the
  /// drain re-rastered them all — at pen-down, the moment the stroke needs
  /// the thread most — while only the cel under the pen could have
  /// changed. The revision can say THAT something moved, not WHERE; the
  /// substrate can: it is every pixel the content answers reach
  /// ([substrate]). Same look, same substrate ⇒ the same pixels.
  ///
  /// 🚨F-446 (유저 2026-10-23: 「엔드라인 드래그로 조절하는게 레이어가
  /// 많아질수록 렉이 심함」): an end-line step makes a new layer of every row
  /// whose last run ends in a ghost — every row of a TVPaint cut — and the
  /// agreement answers from where that ghost STARTS, so every span from
  /// there on was baked again at every step: 🔬~54 tiles a step on S5_BA's
  /// cut 352 (70 rows), the step's raster doubled and three more frames a
  /// step for their landings. Asked what it would bake, only the span the
  /// ghost's end moved through baked anything new (🔬705 tiles in the 40
  /// steps that had baked 2,169) — and since a ghost's ink is the row's to
  /// lay over its tiles ([TimelineTileRasterSource.bakedWritingCellsIn]),
  /// none does.
  bool showsNow(
    _TileRequest asked, {
    required _TileInk Function() inkNow,
  }) {
    final painter = asked.painter;
    final end = asked.spanEndIndexExclusive;
    if (!_sameLook(painter, end, asked.devicePixelRatio)) {
      return false;
    }
    final sameCells = _showsSameCellsAs(painter.layer);
    if (sameCells && celContentRevision == painter.celContentRevision) {
      return true;
    }
    final now = painter.substrateIn(asked.spanStartIndex, end);
    if (!_sameSubstrate(substrate, now) ||
        !sameCells && !_sameInk(ink, inkNow())) {
      return false;
    }
    // ⛔MUTANT SURVIVES (F-446, 2026-10-23): keeping the old layer reddens
    // nothing — the next ask then measures from it and bakes the same. It
    // is taken so the next ask parts from the newest layer, where a drag's
    // next step parts least.
    layer = painter.layer;
    celContentRevision = painter.celContentRevision;
    return true;
  }

  /// Whether this tile is drawn where [asked]'s span is, at its size — the
  /// same world, cells and device pixel ratio, whatever else of the look or
  /// the content moved.
  bool hasTheGeometryOf(_TileRequest asked) {
    final painter = asked.painter;
    return substrateGeneration == painter.substrateGeneration &&
        frameCellExtent == painter.frameCellExtent &&
        crossAxisExtent == painter.crossAxisExtent &&
        spanEndIndexExclusive == asked.spanEndIndexExclusive &&
        devicePixelRatio == asked.devicePixelRatio;
  }

  static bool _sameSubstrate(TimelineRowSubstrate a, TimelineRowSubstrate b) =>
      listEquals(a.paper, b.paper) &&
      listEquals(a.lines, b.lines) &&
      listEquals(a.rings, b.rings);

  static bool _sameInk(_TileInk a, _TileInk b) =>
      listEquals(a.ops, b.ops) && listEquals(a.glyphs, b.glyphs);

  /// Every fact of the look but the two a tile can outlive ([showsNow]):
  /// the layer and the cels' revision.
  bool _sameLook(
    TimelineTileRasterSource painter,
    int spanEndIndexExclusive,
    double devicePixelRatio,
  ) {
    // The cut's LENGTH is deliberately absent: it is not baked into these
    // tiles any more (the out-of-cut wash became its own overlay), so a
    // cut-length drag re-rasters nothing.
    return substrateGeneration == painter.substrateGeneration &&
        coverageIdentity == painter.coverageIdentity &&
        frameCellExtent == painter.frameCellExtent &&
        crossAxisExtent == painter.crossAxisExtent &&
        // `==`, NOT `identical`, for R9 #16's reason below: a panel opened
        // again reads a scheme of the same colours as a NEW instance, and
        // 🔬every tile it had went stale — the timeline tab baked ~84 again
        // at every opening, the storyboard ~42 (10-24,
        // frame-panels-build-in-one-frame).
        colorScheme == painter.colorScheme &&
        // R9 #16: `==`, NOT `identical`. A host hands these in as instance
        // method tear-offs (`_session.exposureStateForLayer`), and Dart
        // makes a FRESH closure object for each tear-off — measured:
        // `identical(s.f, s.f)` is false while `s.f == s.f` is true, and
        // tear-offs of different receivers are correctly unequal. So
        // `identical` here answered "no" on every rebuild, every tile went
        // stale, and up to 32 of them re-rastered one await at a time with
        // a repaint each: the ~100ms lag between the [+] tap and the cel
        // appearing. `==` asks the question we actually mean — is this the
        // same function? — without weakening the contract.
        exposureStateForLayer == painter.exposureStateForLayer &&
        frameNameForLayer == painter.frameNameForLayer &&
        celHasContentForLayer == painter.celHasContentForLayer &&
        baseTextStyle == painter.baseTextStyle &&
        paperGround == painter.paperGround &&
        blockFrameLines == painter.blockFrameLines &&
        unnamedMark == painter.unnamedMark &&
        framesPerSecond == painter.framesPerSecond &&
        shown == painter.shown &&
        this.spanEndIndexExclusive == spanEndIndexExclusive &&
        this.devicePixelRatio == devicePixelRatio;
  }

  /// Whether [next] shows the cells this tile was baked from: the same
  /// instance, or a new one that agrees with it through the tile's reach
  /// ([firstCellThatMayDiffer]).
  ///
  /// 🚨F-244 (유저 2026-09-30: 「블록 코마 늘리거나 관련 동작들 … 무거운
  /// 컷일수록 심해짐」): a comma drag makes a new layer at every step, and
  /// on the instance alone every visible span of the row — and of its
  /// attach mirror — was baked again at every step: 40 tiles a step on FU
  /// 301, the last landing 25–57ms after it, the row showing the step
  /// before meanwhile. Only the spans from the dragged block on show
  /// anything new.
  ///
  /// The reach is the span's own cells and the one after it — its last
  /// paper asks that cell whether it joins, and a frame line at the span's
  /// end stands on it. What a cell reads beyond itself (its neighbours, its
  /// block's word) the agreement answers for; what it reads from outside
  /// its layer is the look's other facts (the camera row's track is
  /// [coverageIdentity], the cels' pixels [celContentRevision]).
  bool _showsSameCellsAs(Layer next) {
    if (identical(layer, next)) {
      return true;
    }
    final differs = _agreementOf(layer, next);
    return differs == null || spanEndIndexExclusive < differs;
  }
}

/// [firstCellThatMayDiffer] of the pair a row's tiles ask about together —
/// every span of the row asks it of the same two instances.
int? _agreementOf(Layer baked, Layer next) => _agreements.resolve(
  baked,
  next,
  () => firstCellThatMayDiffer(baked, next),
);

final SignedMemo<Layer, int?> _agreements = SignedMemo(
  'tile agreement',
  same: identical,
);

/// The per-raster transient atlas (a vertical stack of the span's
/// distinct glyphs) the GLYPH ops reference.
class _TileAtlas {
  const _TileAtlas({
    required this.width,
    required this.height,
    required this.alpha,
  });

  final int width;
  final int height;
  final Uint8List alpha;
}

/// Emits the SUBSTRATE op stream for [painter]'s cells in
/// [spanStartIndex, spanEndIndexExclusive): the paper and the frame lines
/// across it — asked of the painter itself
/// ([TimelineTileRasterSource.substrateIn]), so the tile look can never
/// drift from the classic paint's. Coordinates are tile-local physical
/// pixels (row coords minus the span origin, times DPR). The foreground
/// (words, marks) is written after it ([TimelineGridTileStore._inkOf]).
Int32List timelineGridSubstrateOps({
  required TimelineTileRasterSource painter,
  required int spanStartIndex,
  required int spanEndIndexExclusive,
  required double devicePixelRatio,
}) {
  final writer = TimelineGridTileOpWriter();
  timelineGridEmitSubstrate(
    writer,
    painter: painter,
    spanStartIndex: spanStartIndex,
    spanEndIndexExclusive: spanEndIndexExclusive,
    devicePixelRatio: devicePixelRatio,
  );
  return writer.build();
}

/// The writer-append form of [timelineGridSubstrateOps] — the store
/// appends the foreground pass (T3) to the same stream. Answers the
/// substrate it wrote, which the store keeps beside the tile.
TimelineRowSubstrate timelineGridEmitSubstrate(
  TimelineGridTileOpWriter writer, {
  required TimelineTileRasterSource painter,
  required int spanStartIndex,
  required int spanEndIndexExclusive,
  required double devicePixelRatio,
}) {
  final horizontal = painter.axis == Axis.horizontal;
  final toLocal = offsetAlong(
    painter.axis,
    along: -startAlong(painter.axis, painter.cellRectFor(spanStartIndex)),
    across: 0,
  );
  // 🚨D43-2 재개 (유저 2026-08-22: 「아직도 레이어행에만 그리드 없거든?」)
  // taught this: the emitter is a SECOND reader of the painter's contract,
  // and the painter's own tests stay green when it drops an answer. So it
  // decides nothing — every box, corner and colour below is asked of the
  // painter.
  final substrate = painter.substrateIn(spanStartIndex, spanEndIndexExclusive);
  for (final piece in substrate.paper) {
    final local = piece.rect.shift(toLocal);
    final corner = _cornerOf(piece.radius);
    // ⚡The field is paid for at the run's two ends; the rest is plain
    // fills ([TimelineGridTileOpWriter.runFill] — the same bytes).
    writer.runFill(
      local.left * devicePixelRatio,
      local.top * devicePixelRatio,
      local.width * devicePixelRatio,
      local.height * devicePixelRatio,
      corner.radius * devicePixelRatio,
      corner.mask,
      timelineGridPackRgba(piece.color),
      alongX: horizontal,
    );
  }
  for (final line in substrate.lines) {
    final local = line.rect.shift(toLocal);
    writer.boxFill(
      local.left * devicePixelRatio,
      local.top * devicePixelRatio,
      local.width * devicePixelRatio,
      local.height * devicePixelRatio,
      timelineGridPackRgba(line.color),
    );
  }
  for (final ring in substrate.rings) {
    _emitRing(writer, ring.rect.shift(toLocal), ring, devicePixelRatio);
  }
  return substrate;
}

extension on TimelineGridTileOpWriter {
  /// An in-between mark as tile ops over [disc], its box in tile pixels —
  /// the shape [paintInbetweenMark] draws on the classic pass
  /// ([inbetweenMarkShape]), where the painter lays it: mark 1 ringed
  /// [inbetweenMarkRingWidth] wide at [devicePixelRatio], mark 2 filled.
  void inbetweenMark(
    InbetweenMark mark,
    Rect disc, {
    required int rgba,
    required double devicePixelRatio,
  }) {
    // A rounded rect as round as it is narrow: the disc, and the stadium a
    // narrowed one is.
    switch (mark) {
      case InbetweenMark.one:
        rrectRing(
          (
            x: disc.left,
            y: disc.top,
            width: disc.width,
            height: disc.height,
            radius: disc.shortestSide / 2,
            cornerMask: 15,
          ),
          lineWidth: inbetweenMarkRingWidth * devicePixelRatio,
          openMask: 0,
          rgba: rgba,
        );
      case InbetweenMark.two:
        rrectFill(
          disc.left,
          disc.top,
          disc.width,
          disc.height,
          disc.shortestSide / 2,
          15,
          rgba,
        );
    }
  }
}

/// [ring] as tile ops, laid over [local] — its rect, tile-local.
void _emitRing(
  TimelineGridTileOpWriter writer,
  Rect local,
  TimelineRowRing ring,
  double devicePixelRatio,
) {
  final corner = _cornerOf(ring.radius);
  final open = ring.open;
  writer.rrectRing(
    (
      x: local.left * devicePixelRatio,
      y: local.top * devicePixelRatio,
      width: local.width * devicePixelRatio,
      height: local.height * devicePixelRatio,
      radius: corner.radius * devicePixelRatio,
      cornerMask: corner.mask,
    ),
    lineWidth: ring.width * devicePixelRatio,
    openMask:
        (open.left ? TimelineGridTileOp.sideLeft : 0) |
        (open.top ? TimelineGridTileOp.sideTop : 0) |
        (open.right ? TimelineGridTileOp.sideRight : 0) |
        (open.bottom ? TimelineGridTileOp.sideBottom : 0),
    rgba: timelineGridPackRgba(ring.color),
  );
}

/// A piece's corners as the op stream states them. Every rounded corner
/// wears the one block corner law (`timelineCellBorderRadius`), so one
/// radius and a corner MASK capture it exactly.
({double radius, int mask}) _cornerOf(BorderRadius? radius) {
  if (radius == null) {
    return (radius: 0, mask: 0);
  }
  var mask = 0;
  var value = 0.0;
  for (final (corner, bit) in [
    (radius.topLeft, TimelineGridTileOp.cornerTopLeft),
    (radius.topRight, TimelineGridTileOp.cornerTopRight),
    (radius.bottomLeft, TimelineGridTileOp.cornerBottomLeft),
    (radius.bottomRight, TimelineGridTileOp.cornerBottomRight),
  ]) {
    if (corner.x > 0) {
      mask |= bit;
      value = corner.x;
    }
  }
  return (radius: value, mask: mask);
}
