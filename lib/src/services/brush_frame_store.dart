import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;

import '../core/in_flight.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/canvas_size.dart';
import '../models/cel_photo.dart' show celPhotoPaths;
import '../models/brush_frame_display_cache.dart';
import '../models/brush_frame_drawing_state.dart';
import '../models/brush_frame_key.dart';
import '../models/cut_id.dart';
import '../models/movie_cel.dart';
import '../models/pasteboard_bounds.dart';
import '../models/tile_coord.dart';
import '../native/qa_native_engine.dart';
import 'bitmap_surface_geometry.dart';
import 'memory_pressure_budget.dart';
import 'persistence/brush_drawing_binary_codec.dart';
import 'persistence/compress_in_worker.dart';
import 'persistence/open_project_file.dart';
import 'persistence/anicel_incremental_writer.dart' show AnicelRelocation;
import 'persistence/anicel_project_archive.dart' show anicelCelEntryName;
import 'persistence/scratch_cel_files.dart';
import 'persistence/scratch_file.dart';
import 'persistence/thaw_in_worker.dart';
import 'undo_surface_snapshot.dart';

/// The hot-tier default for THIS machine: a quarter of physical RAM,
/// clamped to [384MB, 1536MB]. Null/zero RAM (the platform refused, or
/// no engine — tests, host runs) keeps the desktop-class 1536MB, which
/// is exactly what every machine got before this existed.
///
/// 유저 확정 (2026-08-16): 「추천대로」 — RAM 비례 기본값 + 압박 반응.
/// A 3GB tablet lands at ~768MB instead of being asked to hold a
/// desktop's 1.5GB of hot cels; a 12GB iPad keeps today's number.
int deviceScaledHotCelBudget({required int? physicalMemoryBytes}) =>
    deviceScaledBudget(
      physicalMemoryBytes: physicalMemoryBytes,
      divisor: 4,
      floor: 384 * 1024 * 1024,
      ceiling: 1536 * 1024 * 1024,
    );

/// What a read of a cel is for — the one thing the store's readers differ
/// in (card `render-reads-thaw-into-hot`, 2026-09-29).
///
/// 🚨The hot budget belongs to what feeds the screen first (the cache law's
/// third question). A render read cels nobody is drawing on as a USE: each
/// cold or file-backed one thawed into the hot tier — filling a 13-cut
/// film's storyboard took it from 149 to 529MB (measured 09-28) — and,
/// newest in line, pushed the cut being drawn toward cooling.
enum CelRead {
  /// The app working on the cel — the canvas, an edit, a copy: what the
  /// read thaws stays hot with its display cache seeded, and the read
  /// counts as the cel's latest use.
  use,

  /// A render looking at it — a storyboard or conte picture, an export
  /// frame: the same pixels, decoded for this read alone. Nothing the store
  /// keeps moves — no hot tier, no place in line, no display cache — and a
  /// parked copy stays parked. What the caller then holds is outside every
  /// budget, so it holds only what it is drawing (`ExportFrameRenderer`).
  ///
  /// A movie's picture is not thawed but decoded, by the hydrator, for
  /// whoever asked — a render included — so a look finds it where the
  /// hydrator just put it.
  look,
}

class BrushFrameStore {
  BrushFrameStore();

  /// Link resolution (L1): every SINGLE-CEL public operation resolves its
  /// key through this first, so linked layers address ONE physical cel —
  /// "the picture exists once; the members are windows onto it". Editing
  /// through any member bumps the canonical revision, which every
  /// member's caches see (revision-based validation needs no fan-out).
  ///
  /// Invariant: because writes resolve too, NON-canonical keys never
  /// enter the maps — enumeration and persistence stay canonical-only
  /// (the .anicel saves each linked bank exactly once). Cut-scoped physical
  /// ops (rekey/translate/resize/snapshot) intentionally stay RAW: they
  /// manage canonical storage directly. A row's carry is not one of them
  /// — its keys are the rows' ([carryCels], F-413).
  BrushFrameKey Function(BrushFrameKey key) _canonicalize = _identityKey;

  static BrushFrameKey _identityKey(BrushFrameKey key) => key;

  /// Installs (or clears, with null) the canonical-key resolver — wire it
  /// to the current project's [LayerLinkRegistry.canonicalCelKey]. The
  /// resolver must be idempotent.
  void setLinkResolver(BrushFrameKey Function(BrushFrameKey key)? resolver) {
    _canonicalize = resolver ?? _identityKey;
  }

  /// The PHYSICAL cel [key] addresses — linked rows are windows onto one
  /// bank, and two different row keys can name the same pixels.
  ///
  /// Callers that walk several rows in one pass need this to avoid acting
  /// on one cel twice: a second recolour of the same bank would record the
  /// colour the first one just wrote as "the original", and undo would
  /// stop halfway.
  BrushFrameKey canonicalKeyOf(BrushFrameKey key) => _canonicalize(key);

  /// How far past the paper every picture this store keeps reaches: the
  /// project's pasteboard for the canvas's store (I-109), the whole 3x for
  /// a sheet's ink, whose panel shows no pasteboard and sets no size.
  ///
  /// 🚨ONE WALL PER STORE. Every picture that enters is put behind it
  /// ([surfaceBehindReach]) — at the hot tier's one door ([_storeHot]) and
  /// at every read of kept bytes, which carry no reach of their own — so no
  /// picture this store hands out stands at another wall, and nothing a
  /// tool writes on one can go past it. The wall moves only with every
  /// picture: [adoptPasteboardReach], or a whole store laid in at one
  /// ([restoreFromFile]).
  PasteboardReach get pasteboardReach => _pasteboardReach;
  PasteboardReach _pasteboardReach = PasteboardReach.whole;

  /// Whether the wall moved to [reach] stands closer to the paper — the
  /// only move with anything of a picture to cut ([adoptPasteboardReach]),
  /// and so with anything to work out ahead of it ([cutCelsAhead]).
  bool wallShrinksTo(PasteboardReach reach) =>
      reach.quartersPerEdge < _pasteboardReach.quartersPerEdge;

  BitmapSurface _behind(BitmapSurface surface) {
    if (surface.pasteboardReach != _pasteboardReach) {
      celsWalledHere += 1;
    }
    return surfaceBehindReach(surface, _pasteboardReach);
  }

  /// [surface] cut behind this store's wall here, on this isolate, when the
  /// wall takes anything of it ([cutBehindReach]) — counted as [_behind]
  /// counts.
  BitmapSurface? _cutHere(BitmapSurface surface) {
    if (surface.pasteboardReach != _pasteboardReach) {
      celsWalledHere += 1;
    }
    return cutBehindReach(surface, _pasteboardReach);
  }

  /// How many pictures [_behind] has put behind this store's wall here, on
  /// this isolate — none that a worker laid behind it already
  /// ([_adoptedBehind]).
  @visibleForTesting
  int celsWalledHere = 0;

  /// [laid] — a kept cel a worker laid behind [standsBehind], the wall it
  /// was asked for ([layCelInWorker]) — adopted here behind this store's
  /// wall: as it came, unless the wall moved while it was worked out.
  BitmapSurface _adoptedBehind(
    AnicelLaidCel laid,
    PasteboardReach standsBehind,
  ) => _behind(laidCelSurface(laid, standsBehind: standsBehind));

  /// Moves every picture's wall to [reach] (I-109) — in every tier, hot,
  /// parked and saved, one cel at a time as a resize walks them, so a
  /// project that is mostly cold never materializes whole. What lies past
  /// the new wall is cut away ([surfaceBehindReach]); a cel the cut does
  /// not touch keeps its bytes where they are.
  ///
  /// Returns the pictures the cut changed, as they were before it, each
  /// with the revision that named it — the undo's whole payload: laid back
  /// under that name once the wall is moved back ([markCelEdited]'s
  /// `backTo`), they restore every pixel, and every picture made of them
  /// answers again.
  ///
  /// What the kept cels make of it may have been worked out AHEAD
  /// ([cutCelsAhead]); this takes those answers, and lets them go
  /// whichever way it moves.
  Map<BrushFrameKey, WallCut> adoptPasteboardReach(
    PasteboardReach reach,
  ) {
    final ahead = _cutAhead;
    _cutAhead = null;
    if (reach == _pasteboardReach) {
      _dropCutAhead(ahead);
      return const {};
    }
    final shrinks = wallShrinksTo(reach);
    _pasteboardReach = reach;
    clearDisplayCaches();
    final cut = <BrushFrameKey, BitmapSurface>{};
    final hotAhead = ahead?.reach == reach ? ahead?.hot : null;
    for (final key in _bakedSurfaces.keys.toList()) {
      final surface = _bakedSurfaces[key]!;
      final worked = hotAhead?[key];
      // Taken only for the very picture it was worked out from: what the
      // worker cut of it, or null where it took nothing.
      final behind = identical(worked?.from, surface)
          ? worked!.made
          : _cutHere(surface);
      if (behind == null) {
        // The wall moved and not a pixel with it: the cel stays as clean as
        // it was, its very tiles.
        _storeHot(key, surface.copyWith(pasteboardReach: reach));
      } else {
        cut[key] = surface;
        storeBakedSurface(key, behind);
      }
    }
    // Kept bytes carry no reach: a wall that grows reaches them on their
    // next read, and only one that shrinks has anything of theirs to cut.
    if (shrinks) {
      final kept = _rewriteKeptCels(
        skips: (key, ref) => _wallPasses(key, ref, reach),
        rewrite: (surface) => cutBehindReach(surface, reach),
        ahead: ahead?.reach == reach ? ahead?.answers : null,
        stands: (ref) => _standsBehind[ref] = reach,
      );
      for (final key in kept.keys) {
        _recordCelContent(key);
      }
      cut.addAll(kept);
    }
    _dropCutAhead(ahead);
    final named = <BrushFrameKey, WallCut>{};
    for (final MapEntry(:key, value: picture) in cut.entries) {
      final cel = _canonicalize(key);
      named[key] = (
        picture: picture,
        revision: getOrCreateFrame(cel).sourceRevision,
      );
      _update(cel, _markCacheDirty);
    }
    if (cut.isNotEmpty) {
      celPixelRevision.value += 1;
    }
    _announceCrossings();
    _scheduleCooling();
    return named;
  }

  /// What [adoptPasteboardReach] to [reach] will make of the cels, worked
  /// out AHEAD on the machine's workers ([cutCelInWorker] for a kept one,
  /// [cutHotCelInWorker] for a hot one, in [celThawTurns]) and held for it —
  /// while a wait window is up, which hears through [report] how much is
  /// done, from 0 to 1.
  ///
  /// 🗣️F-432 (유저 2026-10-21: 「페이스트 보드 배율 전환이 너무 느리고」 — a
  /// project saved and opened again, S5_BA's 127 cels): 3x → 1.5x took
  /// 3.4 s with nothing to cut and 1.5x → off 35 s, 92 cels cut — every
  /// kept cel inflated on the UI thread to see whether the wall cut it,
  /// and every one it cut compressed again there.
  ///
  /// ★Each answer is held by the REF it was worked out from — a hot cel's by
  /// its very picture — and the move takes it only for those very bytes: a
  /// cel kept anew since, drawn on or made hot, is worked out there as it
  /// always was. ⛔So an answer can go stale, and never wrong. A read or a
  /// worker that fails leaves its cel to the move the same way.
  ///
  /// 🗣️[a-pasteboard-redo-cuts-hot-cels-on-the-ui-thread]: an undo lays
  /// back hot every cel its step cut, and the redo cut them on the UI
  /// thread — 0.68 s of S5_BA's 0.7 s redo, 1.5x → off, 92 cels.
  Future<void> cutCelsAhead(
    PasteboardReach reach, {
    void Function(double done)? report,
  }) async {
    _dropCutAhead(_cutAhead);
    final answers = Map<AnicelCelFileRef, _KeptCelRewrite?>.identity();
    final hot = <BrushFrameKey, _RemadeCel>{};
    final ahead = (reach: reach, answers: answers, hot: hot);
    _cutAhead = ahead;
    if (!wallShrinksTo(reach)) {
      return;
    }
    final jobs = <_KeptRead>[
      for (final (from, read) in _keptSources)
        for (final MapEntry(:key, value: ref) in from.entries)
          if (!_wallPasses(key, ref, reach)) (key: key, ref: ref, read: read),
    ];
    final hotCels = {..._bakedSurfaces};
    var done = 0;
    void counted() {
      done += 1;
      report?.call(done / (jobs.length + hotCels.length));
    }

    await Future.wait([
      for (final MapEntry(:key, value: surface) in hotCels.entries)
        _cutHotAhead(key, surface, ahead).whenComplete(counted),
      for (final job in jobs)
        celThawTurns
            .run(() => _cutKeptAhead(job, ahead))
            .whenComplete(counted),
    ]);
  }

  /// HOT [key]'s [surface] cut behind [ahead]'s wall on a worker, held in
  /// [ahead] for the move to take.
  Future<void> _cutHotAhead(
    BrushFrameKey key,
    BitmapSurface surface,
    _CutAhead ahead,
  ) async {
    final worked = await _remadeOnAWorker(
      surface,
      () => cutHotCelInWorker(key, surface, ahead.reach),
    );
    if (worked != null) {
      ahead.hot[key] = worked;
    }
  }

  /// A KEPT cel's bytes, read as [job] says, cut behind [ahead]'s wall on a
  /// worker and parked under a name of their own, held in [ahead] by the
  /// ref they were read off.
  Future<void> _cutKeptAhead(_KeptRead job, _CutAhead ahead) async {
    final (:key, :ref, :read) = job;
    try {
      final blob = read(ref);
      if (blob == null) {
        return;
      }
      final standsBehind = _pasteboardReach;
      final cut = await cutCelInWorker(
        key,
        blob,
        (from: standsBehind, to: ahead.reach),
        // ⛔Never the name the cel is parked under: these bytes are not the
        // cel's until the move takes them ([ScratchCelFiles.newPath]) — and
        // the room can tell what was worked out ahead from what was not.
        parkAt: ScratchCelFiles.newPath(
          _scratchNamespace,
          '${anicelCelEntryName(key)}-ahead',
        ),
      );
      ahead.answers[ref] = cut == null
          ? null
          : (
              kept: _parkedRef(cut.path, cut.blob),
              was: laidCelSurface(cut.was, standsBehind: standsBehind),
            );
      if (!identical(_cutAhead?.answers, ahead.answers)) {
        _dropCutAhead(ahead);
      }
    } on Object {
      // The move reads it again, as it always did. A throw after the park
      // leaves its bytes to the room's own ending, as a removal that fails
      // does ([ScratchFile.letGo]).
    }
  }

  /// What [cutCelsAhead] last worked out — until the next
  /// [adoptPasteboardReach] takes it or lets it go.
  _CutAhead? _cutAhead;

  /// HOT [key] as [cutCelsAhead] worked out its cut, while it is held.
  @visibleForTesting
  BitmapSurface? cutAheadOf(BrushFrameKey key) =>
      _cutAhead?.hot[_canonicalize(key)]?.made;

  /// Lets go of [ahead] — what was worked out ahead and not taken — and of
  /// the bytes it parked in the room.
  static void _dropCutAhead(_CutAhead? ahead) {
    for (final rewrite in ahead?.answers.values ?? const <Never>[]) {
      if (rewrite != null) {
        ScratchFile.letGo(rewrite.kept.filePath);
      }
    }
    ahead?.answers.clear();
    ahead?.hot.clear();
  }

  /// Whether a move of the wall to [reach] leaves [key]'s kept [ref] as it
  /// is, before a byte is read: the cel is hot, and cut by its own pass —
  /// or those very bytes stood behind [reach] when they were last read
  /// ([_standsBehind]).
  bool _wallPasses(
    BrushFrameKey key,
    AnicelCelFileRef ref,
    PasteboardReach reach,
  ) =>
      _bakedSurfaces.containsKey(key) ||
      (_standsBehind[ref]?.quartersPerEdge ?? _unknownReach) <=
          reach.quartersPerEdge;

  static final int _unknownReach = PasteboardReach.whole.quartersPerEdge + 1;

  /// The nearest wall each kept ref's picture is known to stand behind —
  /// learnt where its bytes were read for a move of the wall, so a move
  /// back and forth, an undo's redo among them, reads them once. A
  /// property of the bytes alone: a ref kept anew knows nothing.
  ///
  /// ⚠️Learnt only where the wall did not pass ([_wallPasses]), so what is
  /// learnt is always nearer than what was known.
  final Expando<PasteboardReach> _standsBehind = Expando('stands behind');

  final Map<BrushFrameKey, BrushFrameDrawingState> _frames = {};

  /// R27 #13: bumps whenever a cel crosses the EMPTY ↔ has-picture line.
  ///
  /// The timeline's "no picture yet" tint reads [celHasRenderableContent],
  /// which flips on the first committed stroke — but nothing told the
  /// timeline to look again, so the tint sat there until some unrelated
  /// rebuild (switching layers) came along. Only the CROSSING bumps, so a
  /// stroke on an already-drawn cel costs nothing.
  ///
  /// 🚨It is the tint's ONLY pixel event (F-166, 2026-09-26): the per-edit
  /// signal below stopped reaching it, because it repainted every row after
  /// every stroke. So every surface this store replaces runs the detector —
  /// a way of emptying a cel that skips it leaves a block white over nothing.
  final ValueNotifier<int> celContentRevision = ValueNotifier<int>(0);

  /// The cels the last bump of [celContentRevision] announced crossed, by
  /// the keys this store keeps them under.
  ///
  /// 🚨A listener that answers for a cel by more than this store — the live
  /// stroke counts its cel as drawn before any pixel lands here
  /// (`LayerStack.celHoldsAPicture`) — has to know WHICH cels crossed, or
  /// the stroke landing reads as every block changing (pen-up-dock-tail,
  /// 2026-10-24: a first stroke's commit repainted every row of the
  /// timeline, and not one of the panel's pixels moved).
  Set<BrushFrameKey> get celsLastCrossed => _celsLastCrossed;
  Set<BrushFrameKey> _celsLastCrossed = const {};

  /// The cels crossed since the last bump — what [_announceCrossings]
  /// tells.
  final Set<BrushFrameKey> _crossing = {};

  /// Bumps on EVERY pixel edit ([markCelEdited]), crossing or not.
  ///
  /// Playback composites self-validate against a signature that folds in
  /// each cel's `sourceRevision`, so a stroke silently invalidates them —
  /// nothing raises an "invalidated" event. Cheap UI that DISPLAYS
  /// cached-ness (the rulers' green bar) therefore has no token to compare
  /// and must simply re-read after any edit; this is that signal. Keep the
  /// listeners cheap: this fires as often as the user draws.
  final ValueNotifier<int> celPixelRevision = ValueNotifier<int>(0);

  /// Keys last seen holding a picture — the crossing detector's memory.
  final Set<BrushFrameKey> _celsWithContent = {};

  void _noteCelContent(BrushFrameKey canonicalKey) {
    _recordCelContent(canonicalKey);
    _announceCrossings();
  }

  /// Brings the detector's memory up to date for [canonicalKey], noting a
  /// crossing for the next [_announceCrossings] — a batch records each of
  /// its cels and bumps once.
  void _recordCelContent(BrushFrameKey canonicalKey) {
    // ⛔The SAME question the block draws, not a second copy of it — a
    // detector that crossed on one rule while the paint read another is how
    // the block came to disagree with the drawing in the first place.
    final has = celHasRenderableContent(canonicalKey);
    final had = _celsWithContent.contains(canonicalKey);
    if (has == had) {
      return;
    }
    if (has) {
      _celsWithContent.add(canonicalKey);
    } else {
      _celsWithContent.remove(canonicalKey);
    }
    _crossing.add(canonicalKey);
  }

  /// One bump of [celContentRevision] for every cel crossed since the last
  /// — none when nothing did — naming them in [celsLastCrossed].
  void _announceCrossings() {
    if (_crossing.isEmpty) {
      return;
    }
    _celsLastCrossed = Set.unmodifiable(_crossing);
    _crossing.clear();
    celContentRevision.value += 1;
  }

  /// Derived preview caches. NOT byte-budgeted (R19 P3a): every donated or
  /// baked-seeded entry ALIASES the cel's [_bakedSurfaces] truth (the same
  /// immutable surface object), so evicting one freed nothing — the old
  /// budget/LRU/protected-cut machinery (R13/R16-⑤) only ever caused
  /// rebuild storms. Replay-built entries (legacy this-session command
  /// cels) are superseded by donations on the next edit.
  final Map<BrushFrameKey, BrushFrameDisplayCache> _displayCaches = {};

  BrushFrameDrawingState getOrCreateFrame(BrushFrameKey key) {
    key = _canonicalize(key);
    return _frames.putIfAbsent(key, () => BrushFrameDrawingState(key: key));
  }

  /// The revision [_nextRevision] gave last.
  int _lastRevision = 1;

  /// 🚨A REVISION NO CEL OF THIS STORE HAS HELD — every content a cel
  /// takes is given one: a frame's picture is kept under its cels'
  /// revisions (`FramePictureKey`), and a cel that came back to a revision
  /// it once had at other pixels was shown the picture of those. A cel
  /// carried onto a row's key took the revision it had where it came from
  /// — the same number the cel it replaced had been drawn at, and the
  /// screen showed the cel that was gone (F-313 again, under the frame's
  /// one picture: one-picture-per-frame ②-5b-1, 2026-10-25). ↩️Each cel
  /// counted its own, until then.
  int _nextRevision() => _lastRevision += 1;

  /// A MOVIE cel exists before anything decodes it — its held cel is on the
  /// timeline, and a movie always has a picture — so its state is made on
  /// first ask ([installMovieCel] moves it on).
  BrushFrameDrawingState? frameOrNull(BrushFrameKey key) {
    final canonical = _canonicalize(key);
    return _frames[canonical] ??
        (movieCelOf(canonical.frameId) == null
            ? null
            : getOrCreateFrame(canonical));
  }

  /// The revision [key]'s cel stands at — what a composite signature reads
  /// it by; 0 for a cel the store has never held.
  ///
  /// ↩️The export renderer and the playback's frame pictures each read it
  /// for themselves; the merge (I-78) was the third.
  int sourceRevisionOf(BrushFrameKey key) =>
      frameOrNull(key)?.sourceRevision ?? 0;

  BrushFrameDisplayCache? displayCacheOrNull(BrushFrameKey key) =>
      _displayCaches[_canonicalize(key)];

  bool hasValidDisplayCache(BrushFrameKey key) =>
      displayCacheOrNull(key)?.isValid ?? false;

  BitmapSurface? validPreviewSurfaceOrNull(BrushFrameKey key) {
    final cache = displayCacheOrNull(key);
    return cache != null && cache.isValid ? cache.previewSurface : null;
  }

  void _putDisplayCache(BrushFrameKey key, BrushFrameDisplayCache cache) {
    _displayCaches[key] = cache;
  }

  // --- Movie cels -------------------------------------------------------
  //
  // A movie kept as a reference is decoded when it is shown (08-31 「굽지
  // 않고 재생할 때 디코드」). Its pictures live HERE, beside the tiers and
  // never in them: they are not the project's — nothing saves them, nothing
  // marks them edited, no display cache is banked for them — and a picture
  // let go of is decoded again.

  /// Decoded movie pictures by cel key, least recently used first.
  /// Positions that show one movie frame hold the SAME surface.
  ///
  /// 🚨BOUNDED IN BYTES, BY THE HOT TIER'S OWN BUDGET — the law the viewer's
  /// rasters were brought under (「a count is not a bound」): one
  /// full-canvas picture is megabytes, so no number of them is a limit on
  /// anything. They take only the room the DRAWINGS leave, and they give way
  /// first: a decode is the cheapest thing here to redo, while a drawing
  /// that cools pays an encode — so a movie never pushes a drawing out.
  final Map<BrushFrameKey, BitmapSurface> _movieCels = {};

  /// How many keys hold each distinct picture: a picture two positions
  /// share is paid for once.
  final Map<BitmapSurface, int> _movieCelHolders = Map.identity();

  int _movieCelBytes = 0;

  /// What the decoded movie pictures hold right now.
  int get movieCelBytes => _movieCelBytes;

  /// Whether [key]'s movie picture is decoded, at [canvasSize].
  bool hasMovieCel(BrushFrameKey key, CanvasSize canvasSize) =>
      _movieCels[_canonicalize(key)]?.canvasSize == canvasSize;

  /// Installs [surface] as [key]'s movie picture. The cel's revision moves,
  /// so every cache keyed on it — the composite, the layer image, the
  /// canvas — lets go of what it made without the picture, and the pixel
  /// signal wakes the surfaces that draw. The same picture again moves
  /// nothing.
  void installMovieCel(BrushFrameKey key, BitmapSurface surface) {
    key = _canonicalize(key);
    if (identical(_movieCels[key], surface)) {
      return;
    }
    _releaseMovieCel(key);
    _movieCels[key] = surface;
    final holders = _movieCelHolders[surface] ?? 0;
    if (holders == 0) {
      _movieCelBytes += _residentBytes(surface);
    }
    _movieCelHolders[surface] = holders + 1;
    _fitMovieCels();
    _displayCaches.remove(key);
    final state = getOrCreateFrame(key);
    _frames[key] = state.copyWith(sourceRevision: _nextRevision());
    celPixelRevision.value += 1;
  }

  /// Lets the least recently used movie pictures go until they and the hot
  /// drawings fit the hot budget together — always keeping the newest, the
  /// one about to be drawn. A picture let go of keeps its revision: nothing
  /// drawn with it is wrong, and the next ask decodes it again.
  ///
  /// ⛔Not the shared LRU (board every-bounded-cache-is-one-lru — decided
  /// on storyboard-thumbnails-let-go-by-the-one-order, 2026-10-16): a
  /// picture two keys share is paid for once, so letting a key go frees
  /// nothing until the picture's last holder goes, and the sum is read
  /// again each turn — where the shared one fixes an entry's cost as it
  /// goes in. A third cache of this shape is when to share one.
  void _fitMovieCels() {
    while (_hotBytes + _movieCelBytes > hotCelByteBudget &&
        _movieCels.length > 1) {
      _releaseMovieCel(_movieCels.keys.first);
    }
  }

  void _releaseMovieCel(BrushFrameKey key) {
    final surface = _movieCels.remove(key);
    if (surface == null) {
      return;
    }
    final holders = _movieCelHolders[surface]! - 1;
    if (holders > 0) {
      _movieCelHolders[surface] = holders;
      return;
    }
    _movieCelHolders.remove(surface);
    _movieCelBytes -= _residentBytes(surface);
  }

  void _dropMovieCels() {
    _movieCels.clear();
    _movieCelHolders.clear();
    _movieCelBytes = 0;
  }

  /// What [surface] holds in RAM — ONE measure for the hot drawings and the
  /// movie pictures, because the two are paid from one budget. The plates of
  /// the texts a picture carries are tiles like its own, and counted.
  static int _residentBytes(BitmapSurface surface) =>
      surface.keptTileCount * surface.tileBytes;

  /// Drops every derived display cache, e.g. after a canvas resize makes the
  /// cached preview surfaces the wrong size. Source paint commands are kept.
  void clearDisplayCaches() {
    _displayCaches.clear();
  }

  // -------------------------------------------------------------------
  // Baked raster truth (R19 bake-only / R20-A1 / R22-C three-tier).
  //
  // A cel's picture IS its baked tile raster. The truth lives in THREE
  // forms, sized for 400-cut TV / 1500-cut theatrical projects.
  //
  //  - HOT: a BitmapSurface, insertion-ordered as an LRU (access
  //    re-inserts). Byte-budgeted by [hotCelByteBudget].
  //  - COLD-PARKED: one file per cel in the run's 이사대기 room, holding
  //    the cel encoded + COMPRESSED — the SAME bytes the .anicel archive
  //    stores. zstd where the engine answered, deflate as the floor, and
  //    the blob's codec byte says which (see [compressAnicelPayload] — ONE
  //    place decides). Over-budget hot cels cool here in a background
  //    isolate.
  //
  //    🪦**IT WAS A RAM TIER, AND「unsaved cels never leave RAM」WAS THE
  //    RULE.** That is what capped a session: a project big enough to
  //    exceed the hot budget carried its overflow in memory, because the
  //    archive did not hold those bytes and there was nowhere else to put
  //    them. There is now — the room whose contents a CRASH LEAVES
  //    STANDING, which is the only kind of place unsaved pixels may go.
  //    ⛔The failure mode is new and it is the one to respect: a map put
  //    cannot fail and a file write can, so a cel that will not park stays
  //    HOT and a parked cel that will not read is「unavailable」, never
  //    「empty」.
  //  - COLD-FILE: {the .anicel itself, offset, length} — cels whose bytes
  //    are ALREADY in the saved project file drop their RAM entirely
  //    after a save; opens land every cel here (near-zero RAM).
  //
  // A file ref means "the saved file holds this cel's exact current
  // bytes" — it SURVIVES a clean promotion to hot (so cooling a clean
  // cel is a free drop and incremental saves skip it) and dies on any
  // pixel edit, which also marks the cel dirty. Hot/cold-RAM remain
  // mutually exclusive. Truth is never evicted — the tier is
  // representation, not existence. Undo snapshots hold their own
  // surface references, budgeted separately (HistoryManager.byteBudget)
  // — and they share THESE tile objects wherever an edit did not reach,
  // which is why an undo entry's weight is only the tiles the live
  // surface no longer holds (`BitmapSurface.keptTilesNotSharedWith`).
  //
  // ⚠️AND THEY TIER TOO NOW, into the OTHER room. `fdd328ba` wrote the
  // line above when RAM was the only place an undo payload could be, so
  // 「budgeted separately」 meant 「deleted separately」. It parks
  // separately as well (see `UndoSurfaceSnapshot`), in 휘발성 rather than
  // this tier's 이사대기 — a cooled cel is unsaved work waiting to move
  // INTO the project file and must survive a crash, an undo payload dies
  // with its run. One room for both would let a save's own deletion take
  // the history down with it, and it would not look like a bug: the save
  // succeeds, the file is intact, and only Ctrl+Z shows what went.
  //
  // 🪦**THE 「NO TEMP FILES」 HALF OF THIS IS RETRACTED; THE OTHER HALF IS
  // NOT.** `fdd328ba` (#493) deleted the R20-A2 spill machinery citing a
  // user rule with TWO reasons — 「**no temp files, no drive-sync
  // pollution**」 — and only the first is being taken back (유저
  // 2026-09-07, who asked for an app-container room with three kinds of
  // tenant). ⛔The second stands, and it is now the reason that room is in
  // the app container: scratch written BESIDE a `.anicel` lands in the
  // user's Drive or Dropbox folder and gets uploaded, byte for byte, every
  // time. See [SessionScratch].

  final Map<BrushFrameKey, BitmapSurface> _bakedSurfaces = {};

  /// This store's own prefix in the scratch room — see
  /// [ScratchCelFiles.newNamespace] for whose cels it keeps apart.
  final String _scratchNamespace = ScratchCelFiles.newNamespace();
  final Map<BrushFrameKey, AnicelCelFileRef> _coldCels = {};
  final Map<BrushFrameKey, AnicelCelFileRef> _fileCels = {};
  final Map<BrushFrameKey, int> _hotByteEstimates = {};
  int _hotBytes = 0;
  int _coldBytes = 0;

  /// Cels edited since the last successful save (donations, removals,
  /// moves and rewrites — not mere promotions) — exactly the set an
  /// incremental save must write — each with the tick of its last edit.
  ///
  /// The tick answers the one question the set cannot: "was this cel
  /// edited AFTER the save snapshot was taken?" The marks survive the
  /// whole save, so at adoption time a key that was dirty when the
  /// snapshot was captured and a key that went dirty DURING the save look
  /// identical without it — and treating them the same is how an in-flight
  /// stroke used to vanish: adoption re-installed the pre-edit file ref,
  /// the wholesale clear() wiped the mark, and cooling then "free-dropped"
  /// the only copy of the new pixels. Marks are removed when their edit is
  /// adopted into a save, so the map holds only unsaved work.
  ///
  /// 🚨ONE MAP, ONE WAY IN ([_markDirty]). The mark and its tick were two
  /// fields, and five of the eight places that marked a cel set only the
  /// mark — a resize, an anchored resize, a kept cel's rewrite, a cel
  /// moved to another frame, a cel an undo laid back where it had been
  /// emptied. Each, landing while a save ran, was adopted as the save's
  /// own: the cel went clean on the bytes from before (card
  /// a-resize-during-a-save-can-lose-the-resize, 2026-10-21). A mark
  /// without its tick cannot be written now.
  final Map<BrushFrameKey, int> _dirtySinceSave = {};
  int _editTick = 0;

  /// [key] edited now — dirty, at a tick no earlier edit carries.
  void _markDirty(BrushFrameKey key) => _dirtySinceSave[key] = ++_editTick;

  Set<BrushFrameKey> get dirtyCelKeysSinceSave =>
      Set.unmodifiable(_dirtySinceSave.keys);

  /// Hot-tier byte budget. Cels beyond it cool (encode + compress) in LRU
  /// order in a background isolate. Test-settable; the session seeds it
  /// with [deviceScaledHotCelBudget] at construction (유저 확정
  /// 2026-08-16: RAM 비례 + 메모리 압박 반응 — a 3GB tablet was being
  /// asked to hold a desktop's 1.5GB of hot cels).
  int get hotCelByteBudget => _hotBudget.bytes;
  set hotCelByteBudget(int value) => _hotBudget.bytes = value;

  /// Cools what the budget no longer holds — asked when a budget MOVES (a
  /// new allowance, a project tab sent behind, I-7) rather than left for
  /// the next cel to arrive, which a tab behind the one on screen never
  /// gets. The budget write itself stays a write: the memory warning is
  /// its own kick ([respondToMemoryPressure]).
  void coolToBudget() => _scheduleCooling();

  /// The least a memory warning leaves the hot tier — and the least the
  /// memory tab's allowance may scale it to ([CacheBudgets.floors]).
  static const int hotCelFloorBytes = 256 * 1024 * 1024;

  /// Halving, floored at 256MB so the working set never thrashes. The
  /// lowers-only guard lives in [MemoryPressureBudget] — it was written
  /// out longhand here, again in `HistoryManager`, and would have been a
  /// third time in the viewer.
  final MemoryPressureBudget _hotBudget = MemoryPressureBudget.halving(
    normal: 1536 * 1024 * 1024,
    floor: hotCelFloorBytes,
  );

  /// The OS said memory is tight (`didHaveMemoryPressure`): halve the
  /// budget — floored so the working set never thrashes — and cool NOW.
  /// Lowering the budget loses nothing: over-budget cels encode to the
  /// cold tier, and dirty cels never leave RAM by design.
  void respondToMemoryPressure() {
    // Decoded movie pictures are the cheapest thing here to give back: a
    // frame shown again is decoded again.
    _dropMovieCels();
    _hotBudget.respondToMemoryPressure();
    // Cool even when the budget did not move: a warning arriving while
    // the hot tier is already over an ALREADY-low budget is exactly when
    // cooling matters most.
    _scheduleCooling();
    // ⛔NOT PARKED — RECLAIMED. What an open tool holds is a VIEW now (an
    // open move session's holed cel), and a view can be rebuilt from the
    // picture it was derived from. Parking it would encode bytes to disk
    // that the very next paint needs back, and a painter reaching for a
    // parked surface is the blank frame 유저 forbade outright for this
    // round: 「조작 전/중/후가 빈 프레임 존재안하고 눈에 보이는 결과가
    // 달라지지 않는건 절대조건」.
    //
    // 🚨★★★**A COPY OF THE LIST, AND `.values` WAS A CRASH** — kept from
    // the parking pass this replaced, because the hazard is the same one:
    // reclaiming can end a session, and `Map.values` is a LIVE view, so a
    // loop standing on it died with a ConcurrentModificationError inside a
    // future nobody awaits (press Enter during a memory warning; the OS
    // sends them in bursts).
    for (final view in _reclaimableViews.values.toList()) {
      view.reclaim();
    }
  }

  /// Pictures a TOOL has DERIVED and is holding while it works — the cel
  /// with the hole an open move session shows, and nothing else today.
  ///
  /// 🚨★★★**THE SAME BYTES WERE DISCIPLINED ON ONE SIDE OF A CONFIRM AND
  /// NOT THE OTHER**, and that half of 유저 확정 2026-09-08
  /// (`undo-41-hole-scope` = ①) SURVIVES the 09-17 reversal of the other
  /// half. The moment a confirm turns a move into a history entry its
  /// pixels are budgeted and parkable ([UndoSurfacePair]); while the box is
  /// open they were a plain Map field in a widget's State, with no budget,
  /// no cap and no spill — so a user who had NOT confirmed was held to less
  /// discipline than one who had. Measured on a 2340×1654 cel: a
  /// whole-picture Ctrl+T pins 17.5 MiB, and the image cache keys on these
  /// very tile objects, so up to 17.5 MiB of GPU textures ride along.
  ///
  /// ↩️**What changed on 09-17 is WHICH bytes and HOW they come back.** The
  /// session used to hold a pre-lift SNAPSHOT — the picture as it was
  /// before an erase that had already been committed — and a snapshot can
  /// only be given back by parking it to disk, because losing it loses the
  /// user's pixels. A session holds a DERIVED surface now (the cel plus the
  /// erase, computed and never written), and a derivation cannot be lost:
  /// dropping it costs one recompute on the next paint. So the discipline
  /// is the same and the recovery is cheaper and safer — no isolate, no
  /// encode, no file, and nothing that can refuse to come back.
  ///
  /// 🔬**The 09-08 research still stands** and is why this is not a claim
  /// about pro tools being non-destructive: Krita clears the source device
  /// the moment the box opens, and the lifted content becomes a
  /// `KisPaintDevice` — a document device like any other — so its tile
  /// swapper spills it under pressure and the transform tool contains no
  /// memory-pressure code at all. OpenToonz holds raw rasters on a global
  /// tool object, outside the image cache, where a floating selection
  /// outlives pressure while cold cels and undo entries die first.
  ///
  /// ⛔The TOOL still owns the lifetime — it mints the token and releases
  /// it on confirm, revert or landing. This owns only the DISCIPLINE.
  final Map<int, ({int Function() bytes, void Function() reclaim})>
  _reclaimableViews = {};

  /// Holds [token]'s derived view under the store's discipline: [bytes]
  /// says what it is worth right now, [reclaim] gives it back.
  ///
  /// ⚠️[reclaim] must leave the holder able to rebuild — it is called on a
  /// memory warning, not at the end of the session.
  void holdReclaimableView(
    int token, {
    required int Function() bytes,
    required void Function() reclaim,
  }) {
    _reclaimableViews[token] = (bytes: bytes, reclaim: reclaim);
  }

  void releaseReclaimableView(int token) {
    _reclaimableViews.remove(token);
  }

  /// How many derived views a tool is holding (diagnostics/tests).
  ///
  /// 🚨★★★**COUNT, NOT BYTES — and it exists because the bytes could not
  /// answer.** [reclaimableViewBytes] asks what a view is WORTH, and an
  /// open move session is worth 0: its holed surface shares every tile it
  /// did not hole. 🧪Measured in F-164 while trying to pin exactly this —
  /// a session that never closed reported zero bytes and looked like no
  /// session at all.
  ///
  /// A view that is still held is a tool that still thinks it is mid-edit,
  /// whatever it weighs, and that is what a test about lifetimes means.
  int get reclaimableViewCount => _reclaimableViews.length;

  /// Bytes a tool's derived views are holding right now
  /// (diagnostics/tests) — zero once they have been reclaimed.
  int get reclaimableViewBytes =>
      _reclaimableViews.values.fold(0, (sum, view) => sum + view.bytes());

  /// Bytes currently resident in the hot tier (diagnostics/tests).
  int get hotBakedBytes => _hotBytes;

  /// Bytes PARKED in the run's 이사대기 room (diagnostics/tests) — no
  /// longer resident, which is the whole point of the tier moving there.
  int get coldBakedBytes => _coldBytes;

  /// Keys currently parked on disk (diagnostics/tests).
  Iterable<BrushFrameKey> get coldCelKeys => _coldCels.keys;

  /// Keys currently backed by the saved project file (diagnostics/tests).
  Iterable<BrushFrameKey> get fileCelKeys => _fileCels.keys;

  bool isCelCold(BrushFrameKey key) => _coldCels.containsKey(key);

  bool isCelFileBacked(BrushFrameKey key) => _fileCels.containsKey(key);

  /// The cel's baked raster truth, or null for a never-drawn cel. A cold
  /// cel materializes (inflate + decode) and promotes to hot right here;
  /// a file-backed cel reads its bytes from the saved .anicel first — this
  /// is the ONE seam every pixel consumer goes through.
  ///
  /// [read] says what the read is for ([CelRead]): a [CelRead.look] gets
  /// the same pixels and leaves the store as it found it.
  BitmapSurface? bakedSurfaceOrNull(
    BrushFrameKey key, {
    CelRead read = CelRead.use,
  }) {
    key = _canonicalize(key);
    final hot = _bakedSurfaces[key];
    if (hot != null) {
      if (read == CelRead.use) {
        // LRU touch.
        _bakedSurfaces
          ..remove(key)
          ..[key] = hot;
      }
      return hot;
    }
    final blob = _keptBlobOrNull(key);
    if (blob == null) {
      return null;
    }
    final surface = _behind(blob.decode().toSurface());
    if (read == CelRead.use) {
      _keepThawed(key, surface);
    }
    return surface;
  }

  /// Where a cel that is not hot is kept — its parked blob in the room,
  /// else its stretch of the saved file — or null when it has neither: the
  /// ONE order every read of the kept bytes takes.
  ({AnicelCelFileRef ref, bool parked})? _kept(BrushFrameKey key) {
    final parked = _coldCels[key];
    if (parked != null) {
      return (ref: parked, parked: true);
    }
    final fileRef = _fileCels[key];
    return fileRef == null ? null : (ref: fileRef, parked: false);
  }

  /// [_kept]'s ref when it was kept at [canvasSize]: a read at another size
  /// thaws nothing ([currentSurfaceWithoutReplay]).
  AnicelCelFileRef? _keptAt(BrushFrameKey key, CanvasSize canvasSize) {
    final kept = _kept(key)?.ref;
    return kept?.canvasSize == canvasSize ? kept : null;
  }

  /// The bytes a cel that is not hot is kept as ([_kept]), or null when it
  /// has none.
  AnicelCelBlob? _keptBlobOrNull(BrushFrameKey key) {
    final kept = _kept(key);
    if (kept == null) {
      return null;
    }
    if (!kept.parked) {
      // The ref stays: the file still holds these exact bytes, so a
      // later cooling of this (clean) cel is a free drop.
      return AnicelCelBlob(_readFileRefBytes(kept.ref));
    }
    // 🚨★★★**THE REF STAYS AND SO DOES THE FILE when this answers null.**
    // A cold cel is the only copy of that picture outside the hot tier, so
    // a read that fails right now — a volume that blinked, an antivirus
    // holding the file — must not be turned into 「this cel is empty」,
    // which is what dropping the ref would say to every caller and to the
    // next save. The picture is UNAVAILABLE this moment; the next access
    // tries again.
    return _readScratchBlob(kept.ref);
  }

  /// A thawed cel made the app's: hot, its display cache reseeded from the
  /// same object so first paint after a promotion is O(1) (mirroring what
  /// open used to do eagerly), and its parking space let go.
  void _keepThawed(BrushFrameKey key, BitmapSurface surface) {
    // The bytes are in hand, so the parking space is free. ⛔Dropped only
    // AFTER the read, never before it — and after the decode, so a blob
    // that will not decode keeps its only copy.
    _dropCold(key);
    _storeHot(key, surface);
    storeRebuiltDisplayCache(key: key, previewSurface: surface);
    _scheduleCooling();
  }

  /// [key]'s thaw made AHEAD, off the UI thread: what reading it at
  /// [canvasSize] would thaw here ([currentSurfaceWithoutReplay]) is
  /// inflated and laid into its tiles on a worker ([layCelInWorker]), and
  /// only adopted and kept here — as a [CelRead.use] keeps it. The card
  /// `cel-thaw-holds-the-ui-thread` holds its promises; in short:
  ///
  /// • it completes once reading the cel thaws nothing here — at once when
  ///   nothing would (hot, empty, kept at another size), else when the cel
  ///   is hot, its wait for a worker's turn included ([celThawTurns]);
  /// • asked again while it runs, it answers the same future;
  /// • a cel that moved on meanwhile — made hot, kept anew, gone — keeps
  ///   what it has: the thaw is let go, never written over it;
  /// • it never throws: a read or a decode that fails leaves the kept bytes
  ///   as they are, and the next read tries again here, as it always did.
  ///
  /// ⚠️The bytes are still READ here — the saved file's through the
  /// session's one handle ([_readFileRefBytes]) — so a thaw reads exactly
  /// what [bakedSurfaceOrNull] would.
  Future<void> thawAhead(
    BrushFrameKey key, {
    required CanvasSize canvasSize,
  }) {
    key = _canonicalize(key);
    if (_bakedSurfaces.containsKey(key) || _keptAt(key, canvasSize) == null) {
      return Future<void>.value();
    }
    return _thawing.join(
      key,
      () => _thawOnAWorker(key, () => _keptAt(key, canvasSize), _layThawed),
    );
  }

  final InFlight<BrushFrameKey, void> _thawing = InFlight();

  /// [key]'s kept bytes — while they are what [keptNow] names — thawed on a
  /// worker by [thaw] and kept hot here: the surface kept, or null when the
  /// cel moved on meanwhile (made hot, kept anew, gone) and keeps what it
  /// has, or when the bytes would not read.
  Future<BitmapSurface?> _thawOnAWorker(
    BrushFrameKey key,
    AnicelCelFileRef? Function() keptNow,
    Future<BitmapSurface> Function(AnicelCelBlob blob) thaw,
  ) => celThawTurns.run(() async {
    // Asked again in its turn: the cel may have moved on in the line.
    final kept = keptNow();
    if (_bakedSurfaces.containsKey(key) || kept == null) {
      return null;
    }
    try {
      final blob = _keptBlobOrNull(key);
      if (blob == null) {
        return null;
      }
      final surface = await thaw(blob);
      if (_bakedSurfaces.containsKey(key) ||
          !identical(_kept(key)?.ref, kept)) {
        return null;
      }
      _keepThawed(key, surface);
      return surface;
    } on Object {
      // The kept bytes stay as they are; the next read tries again.
      return null;
    }
  });

  /// [blob] thawed on a worker as a read here would thaw it — behind the
  /// wall there too.
  Future<BitmapSurface> _layThawed(AnicelCelBlob blob) async {
    final reach = _pasteboardReach;
    return _adoptedBehind(
      await layCelInWorker(blob, BitmapTile.blocks, reach: reach),
      reach,
    );
  }

  /// 🚨Through the SESSION'S handle, not a fresh open per cel.
  ///
  /// This used to `openSync`/`closeSync` around every read, which is why
  /// deleting the `.anicel` mid-session took the work with it: between two
  /// reads the app held nothing, so there was nothing to stop the delete
  /// and nothing left to read after it. See [OpenProjectFile] — including
  /// the measurement that says a full save has to make it let go first.
  static Uint8List _readFileRefBytes(AnicelCelFileRef ref) =>
      OpenProjectFile.instance.readAt(
        ref.filePath,
        ref.dataOffset,
        ref.length,
      );

  /// Parks [blob]'s bytes in the run's 이사대기 room and keeps a ref.
  ///
  /// 🚨★★★**ANSWERS FALSE WHEN THE ROOM REFUSED, AND THE CALLER MUST CARE.**
  /// A cooled cel is UNSAVED work — the archive does not hold it — so a
  /// write that fails cannot end with the blob dropped. The cooling pass
  /// parks first and only then lets go of the hot surface: over budget is
  /// a number, and losing the drawing is not.
  ///
  /// ⛔A refusal ends the WHOLE pass, not just that cel. Nothing about the
  /// next one is more likely to succeed (the room is full, read-only or
  /// gone), so carrying on asks the same failing question once per cel
  /// while the user waits.
  ///
  /// 🚨And the pass then DISARMS its own reschedule. `_scheduleCooling`
  /// re-runs on completion for exactly the case where a pass could not
  /// finish — which is this case, for ever: the budget is still exceeded,
  /// so it fires again immediately, fails again, and spins the isolate for
  /// as long as the room stays unwritable. A test found that as a
  /// 30-second hang; a user would have found it as a hot device.
  bool _storeCold(BrushFrameKey key, AnicelCelBlob blob) {
    final name = anicelCelEntryName(key);
    final path = ScratchCelFiles.write(_scratchNamespace, name, blob.bytes);
    if (path == null) {
      return false;
    }
    _keepCold(key, _parkedRef(path, blob));
    return true;
  }

  /// [ref] — bytes already in the room, under a name of their own
  /// ([ScratchCelFiles.newPath]) — made [key]'s cold bytes, and the file it
  /// was kept in before let go.
  void _keepCold(BrushFrameKey key, AnicelCelFileRef ref) {
    final previous = _coldCels[key];
    if (previous != null) {
      _coldBytes -= previous.length;
      ScratchFile.letGo(previous.filePath);
    }
    _coldCels[key] = ref;
    _coldBytes += ref.length;
  }

  /// The ref of [blob] parked alone at [path]: one cel, one file.
  static AnicelCelFileRef _parkedRef(String path, AnicelCelBlob blob) =>
      AnicelCelFileRef(
        filePath: path,
        dataOffset: 0,
        length: blob.bytes.length,
        canvasSize: blob.canvasSize,
        tileSize: blob.tileSize,
        photoPaths: blob.photoPaths,
        showsSomething: blob.showsSomething,
      );

  /// Drops [key]'s cold ref and the file behind it.
  void _dropCold(BrushFrameKey key) {
    final gone = _coldCels.remove(key);
    if (gone == null) {
      return;
    }
    _coldBytes -= gone.length;
    ScratchFile.letGo(gone.filePath);
  }

  /// The blob [ref] names, read back out of the scratch room.
  ///
  /// ⛔A plain open, NOT [OpenProjectFile]: that handle is the session's
  /// hold on ONE file — the project — and pointing it at a scratch cel
  /// would drop the project's handle on every materialization and take it
  /// again on the next cel read.
  static AnicelCelBlob? _readScratchBlob(AnicelCelFileRef ref) =>
      ScratchCelFiles.read(ref.filePath);

  void _storeHot(BrushFrameKey key, BitmapSurface surface) {
    // A cel arriving in the hot tier is the app still working, which is
    // the moment to let the cooling pass try the room again — a volume
    // that was unmounted may be back, and standing down for ever would
    // turn one bad minute into a session with no cold tier at all.
    _coolingStoodDown = false;
    final previous = _hotByteEstimates.remove(key);
    if (previous != null) {
      _hotBytes -= previous;
    }
    // Behind this store's wall, whatever it came from ([pasteboardReach]).
    final kept = _behind(surface);
    final estimate = _residentBytes(kept);
    _bakedSurfaces.remove(key);
    _bakedSurfaces[key] = kept;
    _hotByteEstimates[key] = estimate;
    _hotBytes += estimate;
    // A drawing that grew takes its room back from the movie pictures.
    _fitMovieCels();
  }

  void _removeBaked(BrushFrameKey key) {
    _bakedSurfaces.remove(key);
    _dropCold(key);
    _fileCels.remove(key);
    final estimate = _hotByteEstimates.remove(key);
    if (estimate != null) {
      _hotBytes -= estimate;
    }
    _markDirty(key);
    _noteCelContent(key);
  }

  /// Stores [surface] as the cel's baked truth (commit donations and
  /// snapshot restores land here) — always hot: it was just touched.
  void storeBakedSurface(BrushFrameKey key, BitmapSurface surface) {
    key = _canonicalize(key);
    if (identical(_bakedSurfaces[key], surface)) {
      // Re-donation of the identical truth (session seeding does this on
      // every cel view): bytes unchanged, so the cel stays CLEAN and any
      // file ref stays alive — only the LRU position refreshes. Real
      // edits always build a new immutable surface.
      _storeHot(key, surface);
      return;
    }
    // ⚠️NOTHING AT ALL — a cel that carries only texts has no tile and is
    // still a picture (유저 2026-10-06: a text is 「셀의 그림이랑 정확히
    // 동일」), and dropping it here would be a text lost on its way in.
    if (surface.holdsNothing) {
      _removeBaked(key);
      return;
    }
    _dropCold(key);
    _fileCels.remove(key);
    _storeHot(key, surface);
    _markDirty(key);
    _noteCelContent(key);
    _scheduleCooling();
  }

  /// Every tile the HOT surfaces hold, into [tiles] (an identity set) — what
  /// a holder that shares tiles with this store must not count again (the
  /// app's clipboard, in the memory census). Cold and file cels hold no
  /// tile objects.
  void addHotTilesTo(Set<Object> tiles) {
    for (final surface in _bakedSurfaces.values) {
      tiles.addAll(surface.tiles.values);
    }
  }

  /// Whether a cel's HOT surface holds [tile] at [coord] — the question a
  /// copy-on-write fork makes necessary (undo-held-tile-pictures, stage 2).
  /// An independent paste or duplicate (`carryBakedPictures`) and an unlink
  /// (`UnlinkLayerCommand`) store the SAME surface under a second key, so a
  /// tile one cel's history holds alone can still be another cel's current
  /// picture. Cold and file cels hold no tile objects, so they cannot hold
  /// this one.
  bool holdsTile(TileCoord coord, BitmapTile tile) {
    for (final surface in _bakedSurfaces.values) {
      if (identical(surface.tileAt(coord), tile)) {
        return true;
      }
    }
    return false;
  }

  /// Every baked cel for the save payload: hot surfaces (the saver
  /// encodes them), cold blobs (already archive bytes — written through
  /// with ZERO re-encode) and file refs (already IN the saved .anicel; a
  /// compaction reads them back, an incremental save skips them
  /// entirely).
  ({
    Map<BrushFrameKey, BitmapSurface> hot,
    Map<BrushFrameKey, AnicelCelFileRef> cold,
    Map<BrushFrameKey, AnicelCelFileRef> fileRefs,
    Map<BrushFrameKey, int> dirtyTicks,
  })
  bakedSnapshotForSave() {
    return (
      hot: {..._bakedSurfaces},
      cold: {..._coldCels},
      fileRefs: {..._fileCels},
      // The dirty keys WITH their edit marks — what [adoptSavedFile] needs
      // to tell "written by this save" apart from "edited while it ran".
      dirtyTicks: {
        ..._dirtySinceSave,
      },
    );
  }

  void _clearAllTiers() {
    _dropMovieCels();
    // 🚨★★★**THE FILE REFS GO, SO THE FILE GOES.** A handle nobody can read
    // through still keeps the OS from letting the file be deleted or moved.
    // Holding it past this point is not protection, it is a lock on a file
    // this session has closed.
    //
    // 🧪Found by a test, not by reasoning: `load_heals_mismatched_cels_test`
    // could not delete its own temp folder afterwards. That is exactly what
    // a user closing a project and then tidying the folder would hit.
    //
    // ⚠️**EVERY cel store of a session shares the one handle** — the main
    // cel store and each sheet's ink store, all holding refs into the SAME
    // `.anicel` (one open fills them all: `ProjectFileDoor.settle`). So
    // this is not「nothing can name the file any more」, it is「this store
    // cannot」, and it is only the whole truth because the product always
    // fills them together — and, since a file opens as a session of its own
    // (I-7), only once. ⛔Nothing rests on that: letting go early costs one
    // re-open on the next sibling's read, which is why the release is not
    // counted.
    //
    // ↩️It was UNCONDITIONAL — the one handle, whatever it held. With a
    // project per tab (I-7) that let go of every OTHER tab's file too, so it
    // lets go of the files THIS store read from and no others.
    releaseFilesReadFrom();
    _letGoOfEveryCel();
    // R27 #13: a whole-store swap (project open) is one crossing for
    // every cel there was — one bump covers the lot.
    _crossing.addAll(_celsWithContent);
    _celsWithContent.clear();
    _announceCrossings();
  }

  /// A CLOSED project's store lets go of every cel it holds — and the
  /// engine gives back its parking once the collector has found them
  /// ([QaNativeEngine.giveBackOnceCollected]).
  ///
  /// 🗣️유저 2026-10-29 (F-505): 「무거운거 닫으면 … 초기프로젝트분만큼만
  /// 메모리 존재해야하는데 무거운 프로젝트의 메모리가 아직 남아있는듯함」.
  /// 🔬Measured (a heavy tab closed beside an empty one, two collections
  /// after): the session disposed, its store still holding 3,262MB of hot
  /// cels — whatever still reached the closed session reached them, and the
  /// panel read them as 「엔진·폰트·프레임워크」. A closed project's pictures
  /// go at the close, whoever still holds its session.
  ///
  /// ⚠️After its files are released (`EditorSessionManager`'s teardown reads
  /// [filesReadFrom] first) and announcing nothing: nobody listens to a
  /// closed project's crossings.
  void dispose() {
    for (final surface in [..._bakedSurfaces.values, ..._movieCels.values]) {
      QaNativeEngine.giveBackOnceCollected(surface);
    }
    _dropMovieCels();
    _letGoOfEveryCel();
  }

  void _letGoOfEveryCel() {
    _frames.clear();
    clearDisplayCaches();
    _bakedSurfaces.clear();
    _coldCels.clear();
    _fileCels.clear();
    _hotByteEstimates.clear();
    _hotBytes = 0;
    _coldBytes = 0;
    _dirtySinceSave.clear();
    _dropCutAhead(_cutAhead);
    _cutAhead = null;
    _movedAhead = null;
  }

  /// Replaces the WHOLE store with loaded cels as COLD-RAM blobs (tests
  /// and non-file flows), kept behind [pasteboardReach].
  void restoreBaked(
    Map<BrushFrameKey, AnicelCelBlob> cels, {
    PasteboardReach pasteboardReach = PasteboardReach.whole,
  }) => _restoreAll(cels, _storeCold, pasteboardReach);

  /// Replaces the WHOLE store with FILE-BACKED cels (project open,
  /// R22-C): near-zero RAM — every cel reads from the .anicel on first
  /// access. No temp files, ever. They are kept behind [pasteboardReach] —
  /// the project's, which the file's cels were saved at.
  void restoreFromFile(
    Map<BrushFrameKey, AnicelCelFileRef> cels, {
    PasteboardReach pasteboardReach = PasteboardReach.whole,
  }) => _restoreAll(
    cels,
    (key, ref) => _fileCels[key] = ref,
    pasteboardReach,
  );

  /// The whole-store swap both entry points are: every tier cleared, the
  /// store's wall set at [reach] — every picture is new, so none stands at
  /// another — then each cel seeded and [place]d in the tier its payload
  /// belongs to. Frames reseed at sourceRevision 1.
  ///
  /// ⚠️[place] runs BEFORE [_noteCelContent], which asks
  /// [celHasRenderableContent] — and that reads the tiers.
  void _restoreAll<T>(
    Map<BrushFrameKey, T> cels,
    void Function(BrushFrameKey key, T cel) place,
    PasteboardReach reach,
  ) {
    _clearAllTiers();
    _pasteboardReach = reach;
    for (final entry in cels.entries) {
      _frames[entry.key] = BrushFrameDrawingState(
        key: entry.key,
        sourceRevision: 1,
      );
      place(entry.key, entry.value);
      _noteCelContent(entry.key);
    }
  }

  /// After a successful save: every saved cel gains a file ref (hot
  /// cels KEEP their surface — hot + ref coexist until cooling drops
  /// the bytes for free), cold blobs are redundant with the file and
  /// drop, and the SNAPSHOT'S dirty marks clear — the next incremental
  /// save starts from what changed since.
  ///
  /// [dirtyTicksAtSnapshot] is this save's own capture (what
  /// [bakedSnapshotForSave] returned when it began). A cel whose edit
  /// tick moved past its captured mark was edited WHILE the save ran; its
  /// ref describes the pre-edit bytes and must not adopt. Adopting it —
  /// which the wholesale `_dirtySinceSave.clear()` here used to pair with
  /// — marked the stroke clean (the next incremental save skipped it) and
  /// handed cooling a "free drop" that reverted the pixels to the file's:
  /// total, silent loss of the edit. The pen already down when Ctrl+S
  /// fired was the reachable case. The cel stays hot and dirty instead,
  /// and the next save writes it.
  void adoptSavedFile(
    Map<BrushFrameKey, AnicelCelFileRef> saved, {
    required Map<BrushFrameKey, int> dirtyTicksAtSnapshot,
  }) {
    bool editedSinceSnapshot(BrushFrameKey key) =>
        (_dirtySinceSave[key] ?? 0) > (dirtyTicksAtSnapshot[key] ?? 0);
    for (final entry in saved.entries) {
      if (editedSinceSnapshot(entry.key)) {
        continue;
      }
      _dropCold(entry.key);
      _fileCels[entry.key] = entry.value;
      // R27 #13: a ref landing on a key that held no tier at all is a
      // crossing (the cel emptied between the save snapshot and this
      // adoption), and this was the other silent tier move the timeline
      // never heard. No-op for the everyday save, where the cel is
      // already hot or cold.
      _noteCelContent(entry.key);
    }
    // The dirty CLEAR follows the same law, key by key. Keys the snapshot
    // captured (written or removed by this save) go clean unless re-edited
    // since; keys that went dirty during the save keep their mark.
    for (final entry in dirtyTicksAtSnapshot.entries) {
      if (!editedSinceSnapshot(entry.key)) {
        _dirtySinceSave.remove(entry.key);
      }
    }
  }

  /// The files this store's clean cels read from — the project file, or a
  /// copy a save moved them onto.
  Set<String> get filesReadFrom => {
    for (final ref in _fileCels.values) ref.filePath,
  };

  /// Lets go of the held handle on every file in [filesReadFrom] — the
  /// store's own, and no other open project's (see [OpenProjectFile]).
  void releaseFilesReadFrom() {
    for (final path in filesReadFrom) {
      OpenProjectFile.instance.releaseFor(path);
    }
  }

  /// Moves every ref into [from] onto [to] — same offsets, same lengths,
  /// nothing else touched: the bytes at [to] are a copy of [from] (the
  /// save's rescue of a file whose name vanished while the session held it;
  /// see `AnicelFileService.save`).
  ///
  /// ⛔Not [adoptSavedFile]: adopting CLEARS the dirt of what it adopts, and
  /// nothing was saved here — what was drawn since the last save is exactly
  /// as unsaved as it was.
  ///
  /// ⚠️The exact string, on purpose: every ref and the held path are made
  /// from the same argument (the save's `filePath`, the opened path), so
  /// there is no second spelling to normalise away.
  void repointFileRefs(String from, String to) {
    for (final entry in _fileCels.entries.toList()) {
      final ref = entry.value;
      if (ref.filePath == from) {
        _fileCels[entry.key] = ref.movedTo(filePath: to);
      }
    }
  }

  /// Every ref into a file [inFile] accepts whose bytes were at a DATA
  /// offset in [moved] now reads them where they went — whatever key holds
  /// it (a rekeyed cel still points at its old name's bytes).
  ///
  /// 🚨★★★THE SAVE WAITS FOR THIS BEFORE IT WRITES OVER THE OLD BYTES. The
  /// in-place push-down (유저 2026-09-23, deleting-save-compacts-Q1) moves
  /// entries these refs read from, in another isolate, while the session
  /// keeps drawing and reading cold cels. A ref still aimed at the old
  /// offset once the next round had landed there would decode someone
  /// else's bytes as this picture — and the next save would write that back
  /// as the cel. `compactAnicelInPlace` announces each round's moves and
  /// does not continue until this has run.
  ///
  /// ⚠️Refs only. Clean or dirty is unchanged: the bytes are the same bytes.
  void relocateFileRefs(
    bool Function(String path) inFile,
    Map<int, AnicelRelocation> moved,
  ) {
    for (final entry in _fileCels.entries.toList()) {
      final ref = entry.value;
      if (!inFile(ref.filePath)) {
        continue;
      }
      final to = moved[ref.dataOffset];
      if (to == null) {
        continue;
      }
      _fileCels[entry.key] = ref.movedTo(
        dataOffset: to.dataOffset,
        length: to.length,
      );
    }
  }

  /// Lets go of the cels a save could not carry forward — each was only a
  /// ref into a file that is gone, descriptor and all
  /// (`AnicelFileService.save` returns them).
  ///
  /// 🚨★★★**THE REF DID NOT POINT AT NOTHING — IT POINTED INTO THE NEW
  /// FILE.** The save that reported the loss had just written a fresh
  /// archive at that very path, so the old offset landed inside whatever
  /// sits there now, and the next save APPENDED onto that file carrying the
  /// ref forward as this cel (F-72 follow-up, 2026-09-11). The pixels were
  /// gone either way; what goes here is the claim that they are still at
  /// that offset. The cel reads as empty from now on, which is what the
  /// person was told.
  void forgetCelsLostWithTheirFile(Iterable<BrushFrameKey> keys) {
    for (final key in keys) {
      if (_fileCels.remove(key) != null) {
        _noteCelContent(key);
      }
    }
  }

  /// Whether the cel shows ANY picture content — the composite/export/
  /// fill resolvers' emptiness oracle. Every tier counts: representation
  /// is not existence.
  bool celHasRenderableContent(BrushFrameKey key) {
    key = _canonicalize(key);
    // A MOVIE cel has a picture before it is decoded. Answering "empty"
    // would let the display cache bank a blank stand-in as VALID — and a
    // valid cache is exactly what stops anyone looking again.
    if (movieCelOf(key.frameId) != null) {
      return true;
    }
    final baked = _bakedSurfaces[key];
    if (baked != null) {
      // 🚨A CLEARED CEL STILL HAS A SURFACE. 픽셀 비우기 writes alpha 0 across
      // the tiles and puts them straight back — it cannot drop them, because
      // undo computes its walk from the tiles that EXIST (see
      // `celPixelWalkFor`, and the round carded as `undo-weight`). So map
      // membership alone answered 「그려짐」 about a cel with nothing left in
      // it: the block stayed white and the pixel buttons stayed lit (유저
      // 2026-08-27: 「삭제눌렀으면 그림이 사라진거니 블록이 회색되고 버튼도
      // 비활성화되야하는데 둘다 아님」).
      return baked.showsSomething;
    }
    // ⛔Cold and file-backed cels are NOT asked by decoding: that would
    // MATERIALIZE every cel of the project, and this is called per visible
    // block. They answer with what their head kept — the same question,
    // asked of the picture the moment its bytes were written
    // ([AnicelCelFileRef.showsSomething]).
    // ↩️They answered by membership until 2026-10-24, on the premise that
    // they were written from a surface that had ink. Three roads write one
    // that has none — the cooling pass, a wall that shrinks past a cel's
    // only lines, and a save of a cleared cel opened again — and each such
    // block read 「그려짐」 again (board a-cooled-empty-cel-reads-drawn).
    return _kept(key)?.ref.showsSomething ?? false;
  }

  /// The cel's current pixels: a VALID display cache at [canvasSize]
  /// first (donations keep it fresh), else the baked truth (a cold cel
  /// materializes if its recorded size matches). Null = the cel is empty
  /// (or sized for another canvas — resize flows reseed). [read] as
  /// [bakedSurfaceOrNull]'s.
  BitmapSurface? currentSurfaceWithoutReplay(
    BrushFrameKey key, {
    required CanvasSize canvasSize,
    CelRead read = CelRead.use,
  }) {
    key = _canonicalize(key);
    final cached = validPreviewSurfaceOrNull(key);
    if (cached != null && cached.canvasSize == canvasSize) {
      return cached;
    }
    final movie = _movieCels.remove(key);
    if (movie != null) {
      // Read is use: it goes back in as the newest.
      _movieCels[key] = movie;
      return movie.canvasSize == canvasSize ? movie : null;
    }
    final hot = _bakedSurfaces[key];
    if (hot != null) {
      return hot.canvasSize == canvasSize
          ? bakedSurfaceOrNull(key, read: read)
          : null;
    }
    return _keptAt(key, canvasSize) == null
        ? null
        : bakedSurfaceOrNull(key, read: read);
  }

  // --- Cooling (hot → cold) -------------------------------------------

  Future<void>? _activeCooling;

  /// Completes when no cooling pass is running (tests).
  Future<void> drainCooling() async {
    while (_activeCooling != null) {
      await _activeCooling;
    }
  }

  /// Set when a pass could not park a cel, and cleared by anything that
  /// could plausibly change the answer — a new edit, a project swap.
  ///
  /// ⛔Without it the completion re-schedule is an infinite loop: the pass
  /// stands down BECAUSE the budget is still exceeded, which is the very
  /// condition the re-schedule fires on.
  bool _coolingStoodDown = false;

  void _scheduleCooling() {
    if (_activeCooling != null ||
        _coolingStoodDown ||
        _hotBytes <= hotCelByteBudget ||
        _bakedSurfaces.length <= 1) {
      // The length guard both mirrors the loop's never-cool-the-last-hot
      // rule and keeps the completion re-schedule from spinning when the
      // one remaining cel alone exceeds the budget.
      return;
    }
    _activeCooling = _coolLoop().whenComplete(() {
      _activeCooling = null;
      // Work stored while this pass ran (or that this pass could not cool
      // yet — e.g. a lone hot cel that stopped the loop) gets a fresh
      // pass; without this, a skipped schedule during an active pass
      // would never retry.
      _scheduleCooling();
    });
  }

  /// Cools LRU hot cels until the budget holds, one at a time: snapshot
  /// bytes on the main isolate, COMPRESS in a background isolate, then
  /// commit the swap ONLY if the cel's surface is still the identical
  /// object (a donation in between wins and the stale blob is dropped).
  ///
  /// 🚨★★★**THIS IS WHERE A CEL'S CODEC IS DECIDED — not at save time.**
  /// A save passes a cold blob through byte-for-byte, so whatever this
  /// wrote is what the .anicel gets. Two consequences worth knowing:
  ///
  /// • The isolate re-probes for the engine, because statics do not cross
  ///   an isolate boundary. If it could not find it there while the main
  ///   isolate could, every cel would cool to deflate and NOTHING would
  ///   say so — the floor is silent by design. `the_cooling_path_is_zstd_test`
  ///   is the only thing standing between that and a silent regression.
  /// • A「save at maximum compression」cannot be a flag on the save: the
  ///   cold and file-ref tiers hand over bytes that were compressed here,
  ///   minutes earlier, at [anicelZstdLevel] — the only level there is.
  /// The most recently used cel never cools — the one being painted or
  /// displayed must not thrash even if it alone exceeds the budget.
  ///
  /// ⛔Not the shared LRU (board every-bounded-cache-is-one-lru — decided
  /// on storyboard-thumbnails-let-go-by-the-one-order, 2026-10-16): the
  /// same order, a different walk. A cel is let go of only once its park
  /// has said yes, after an await, and a refusal stands the whole pass
  /// down — a cache that lets go the moment it is over its limit cannot
  /// keep that order. A third cache of this shape is when to share one.
  Future<void> _coolLoop() async {
    while (_hotBytes > hotCelByteBudget && _bakedSurfaces.length > 1) {
      final key = _bakedSurfaces.keys.first;
      if (_fileCels.containsKey(key)) {
        // Clean file-backed cel (edits kill the ref): the saved .anicel
        // already holds its exact bytes — cooling is a free drop.
        _bakedSurfaces.remove(key);
        _hotBytes -= _hotByteEstimates.remove(key)!;
        _displayCaches.remove(key);
        continue;
      }
      final surface = _bakedSurfaces[key]!;
      // 🎯The park path's shape, and DELIBERATELY the same one: these
      // two were matched on purpose (fixing one alone would make it a
      // copy of the other), so they moved together. One copy of the
      // payload instead of four — see [compressAnicelPayloadInWorker].
      final body = encodeCelEntryFromSurface(key, surface);
      final compressed = await compressAnicelPayloadInWorker(body);
      final blob = AnicelCelBlob.fromCompressedBody(
        key: key,
        canvasSize: surface.canvasSize,
        tileSize: surface.tileSize,
        photoPaths: celPhotoPaths(surface.photos),
        showsSomething: surface.showsSomething,
        codec: compressed.codec,
        body: compressed.bytes,
      );
      if (identical(_bakedSurfaces[key], surface)) {
        // 🚨★★★**PARK IT BEFORE LETTING GO OF IT.** These bytes are
        // UNSAVED — the archive does not hold them — so the order here is
        // the difference between over budget and a lost drawing. The old
        // shape could not fail (the blob went into a map), and it dropped
        // the hot surface first; a write can fail, so the drop happens
        // only once the park has answered yes.
        // ⛔Park BEFORE letting go — see [_storeCold] for why a refusal
        // ends the whole pass rather than skipping one cel.
        if (!_storeCold(key, blob)) {
          _coolingStoodDown = true;
          return;
        }
        _bakedSurfaces.remove(key);
        _hotBytes -= _hotByteEstimates.remove(key)!;
        // Drop the derived alias too, or the surface stays resident.
        _displayCaches.remove(key);
      }
    }
  }

  /// Completes when no background tiering pass is running (tests).
  ///
  /// Cooling is the only background pass. 🪦This used to add 「the
  /// scratch-disk spill is gone — the saved .anicel itself is the disk
  /// tier」, which was true while an unsaved cel had nowhere to go but
  /// RAM. Cooling IS a spill again, into the run's 이사대기 room; what
  /// stays true is the half that reason rested on — ⛔nothing is ever
  /// written beside the project file.
  Future<void> drainTiering() => drainCooling();

  /// [surface] stored under [key] as a COPY of the cel [source]
  /// ([storeBakedSurface]) — and when it is the very surface [source] holds,
  /// the preview [source] is drawn from is the copy's too. Any other
  /// surface (a copy taken before the source was drawn over, one laid to
  /// another canvas) is only stored.
  ///
  /// 🚨F-275 (유저 2026-10-08): 「링크독립하면 싱크어태치 그림 사라지길래
  /// 해결안된건가 했는데 다른 레이어 이동하니 화면에 정상표시」 — 링크 독립
  /// hands a block a cel of its own and its attach row a mirror of it, the
  /// same pixels under new keys, and the rows went blank on the frame after
  /// it until an asynchronous build came back with what they had shown —
  /// 🔬0 of 7225 pixels on that frame, in
  /// `an_unlinked_cel_keeps_its_attach_on_screen_test`.
  void storeCopiedSurface(
    BrushFrameKey key,
    BitmapSurface surface, {
    required BrushFrameKey source,
  }) {
    storeBakedSurface(key, surface);
    final from = _canonicalize(source);
    if (!identical(_bakedSurfaces[from], surface)) {
      return;
    }
    // The preview a cel is drawn from is the copy's too, as a rekey carries
    // it ([_rehome]): the frame a screen shows while its picture is laid
    // draws a cel only once its preview is prepared, and the copy had none
    // for a frame — F-275 again, under the frame's one picture
    // (one-picture-per-frame ②-3, 2026-10-25). ↩️The pictures made of the
    // source were handed on to the copy too, through listeners the image
    // cache and the editing stack held, until no row's picture was kept
    // (②-5b-1).
    final preview = _displayCaches[from];
    if (preview != null && preview.isValid) {
      final to = _canonicalize(key);
      _displayCaches[to] = BrushFrameDisplayCache(
        frameKey: to,
        previewSurface: preview.previewSurface,
        sourceRevision: getOrCreateFrame(to).sourceRevision,
      );
    }
  }

  /// Re-homes stored drawings under new keys, AS GIVEN — the cut-scoped ops
  /// that manage canonical storage directly (a cut deleted, a cut made
  /// 겸용). Content is untouched, so the display cache travels along and
  /// stays valid. Missing sources are skipped (an empty cel moved). The
  /// inverse pair list undoes the move exactly.
  void rekeyFrames(List<(BrushFrameKey from, BrushFrameKey to)> pairs) =>
      _rehome(pairs);

  /// Carries cels from one ROW to another (a block moved across rows,
  /// R10-④b): [rowPairs] are the keys the rows ask with. The pixels are
  /// re-homed where those keys resolve — a 겸용 row is a window onto its
  /// group's canonical cel ([setLinkResolver]).
  ///
  /// 🚨F-413 (유저 2026-10-19): 「겸용컷일때 프레임블록 드래그해서
  /// 다른행으로 이동시키면 그림이 사라짐」 — the carry re-homed the rows'
  /// keys as given: in a cut its group is not canonical in, the row's key
  /// held nothing to move, and the row it landed on resolved to an empty
  /// cel.
  void carryCels(List<(BrushFrameKey from, BrushFrameKey to)> rowPairs) =>
      _rehome([
        for (final (from, to) in rowPairs)
          (_canonicalize(from), _canonicalize(to)),
      ]);

  void _rehome(List<(BrushFrameKey from, BrushFrameKey to)> pairs) {
    for (final (from, to) in pairs) {
      // A content new to [to]'s key: a revision of its own ([_nextRevision]).
      final state = _frames.remove(from);
      final revision = state == null ? null : _nextRevision();
      if (state != null) {
        _frames[to] = state.copyWithKey(to).copyWith(sourceRevision: revision);
      }
      // 🚨F-313 (유저 2026-10-08: 「다른행이동하면 일시적으로 빈 블록으로
      // 만드는 로직 있는거같은데 싹 삭제하고 법 통일. 항상 보여야함」): the
      // preview a cel is drawn from travels with it, so the frame it lands
      // on draws it while its picture is laid — 🔬0 of 32 columns on that
      // frame where a cel's pictures stayed under the key the move left, in
      // `a_cel_carried_onto_another_row_shows_on_the_frame_it_lands_test`.
      // ↩️The image cache's and the editing stack's pictures of it were
      // told the move through listeners too, until no row's picture was
      // kept (one-picture-per-frame ②-5b-1).
      final cache = _displayCaches.remove(from);
      if (cache != null) {
        _displayCaches[to] = cache.copyWith(sourceRevision: revision);
      }
      // The baked truth travels with the cel (R19) — either tier.
      final baked = _bakedSurfaces.remove(from);
      if (baked != null) {
        _bakedSurfaces[to] = baked;
        _hotByteEstimates[to] = _hotByteEstimates.remove(from)!;
      }
      final cold = _coldCels.remove(from);
      if (cold != null) {
        _coldCels[to] = cold;
      }
      final fileRef = _fileCels.remove(from);
      if (fileRef != null) {
        _fileCels[to] = fileRef;
      }
      if (baked != null || cold != null || fileRef != null) {
        // The saved file still labels these bytes with the OLD key, so
        // both cels are save-relevant: [from]'s entry must vanish and
        // [to] must be rewritten under its own key (the saver re-keys
        // moved blobs/refs — pixels are identical, only the label
        // changes, so reads through a moved ref stay valid meanwhile).
        _markDirty(from);
        _markDirty(to);
      }
      // R27 #13, rekey edition: the move crosses the empty ↔ has-picture
      // line at BOTH ends ([from] always empties; [to] usually gains its
      // first content), and nothing else tells the timeline's content
      // tint to look again — a rekey was a silent tier move whose tiles
      // kept answering for the old world. No-ops when nothing crossed.
      _noteCelContent(from);
      _noteCelContent(to);
    }
  }

  /// D5 (R7): adopts [canvasSize] for every cel of [cutId] AND applies
  /// the resize anchor's ([dx], [dy]) content offset in the SAME blit —
  /// the resize command's one-pass raster adoption
  /// ([translateBitmapSurface] already takes the target canvas and clips
  /// against ITS pasteboard). dx=dy=0 (top-left anchor) is the plain
  /// crop/extend ([resizeBakedSurfaces] — hot cels keep their tiles,
  /// cold/file cels stay cold).
  ///
  /// The COMMAND completes the adoption for its target and every 겸용
  /// sibling, so no state the widget half used to depend on (active cut,
  /// live selection, a mounted canvas host) can leave a cel behind at
  /// the old size — a mismatched cel displayed as EMPTY and turned into
  /// permanent loss on the first stroke (the D5 picture loss). R19:
  /// anchors produce whole-pixel offsets; the resize command's reference
  /// snapshot covers the exact undo.
  void adoptCutCanvasSize({
    required CutId cutId,
    required CanvasSize canvasSize,
    double dx = 0,
    double dy = 0,
  }) {
    if (dx == 0 && dy == 0) {
      resizeBakedSurfaces(canvasSize, cutId: cutId);
      return;
    }
    final move = (canvasSize: canvasSize, dx: dx.round(), dy: dy.round());
    var edited = false;
    for (final key in _celKeysOfCut(cutId)) {
      // Cold cels of the cut materialize first (cut-scoped = bounded).
      _storeHot(key, _moved(key, bakedSurfaceOrNull(key)!, move));
      _fileCels.remove(key);
      _markDirty(key);
      // Per-cel signature bump WITHOUT the per-cel global notify: the
      // global signal fires as often as the user draws and its
      // listeners are honed for single strokes — N cels × N listener
      // walks was part of D3's freeze. One bump covers the lot (the
      // [_clearAllTiers] precedent).
      _update(_canonicalize(key), _markCacheDirty);
      edited = true;
      // An offset can carry every line off the canvas.
      _recordCelContent(key);
    }
    if (edited) {
      celPixelRevision.value += 1;
    }
    _announceCrossings();
    _scheduleCooling();
  }

  /// [surface] — [key]'s — as [move] leaves it: worked out AHEAD
  /// ([moveCutCelsAhead]) when it was worked out from these very pixels,
  /// else here.
  BitmapSurface _moved(
    BrushFrameKey key,
    BitmapSurface surface,
    CelMove move,
  ) {
    final ahead = _movedAhead?.move == move ? _movedAhead : null;
    final answer = ahead?.answers.remove(key);
    if (ahead == null) {
      _movedAhead = null;
    }
    if (answer != null && identical(answer.from, surface)) {
      return answer.moved;
    }
    celsMovedHere += 1;
    return movedBy(surface, move);
  }

  /// How many cels [adoptCutCanvasSize] has moved here, on this isolate —
  /// none whose move was worked out ahead and taken ([moveCutCelsAhead]).
  @visibleForTesting
  int celsMovedHere = 0;

  /// What [adoptCutCanvasSize] will make of [cutIds]' cels, worked out
  /// AHEAD on the machine's workers ([moveCelInWorker], in [celThawTurns])
  /// — each kept one thawed as a read here thaws it and kept hot, and every
  /// one moved by [move] as the resize moves it — while a wait window is up,
  /// which hears through [report] how much is done, from 0 to 1. The thaw is
  /// ahead even where the move is not: the resize's undo holds every cel it
  /// touched, and reading them is what took the time.
  ///
  /// 🔬Card `a-canvas-resize-rewrites-kept-cels-on-the-ui-thread` (S5_BA
  /// saved and opened again — 127 cels of 2436×1524, `flutter test`,
  /// 2026-10-22): the thaw took 1.9 s on the UI thread, and a move of the
  /// picture — any anchor but the top left — 2.4 s more.
  ///
  /// ★Each answer is held with the very surface it was worked out from and
  /// taken only for it ([_moved]): a cel made hot, drawn on or kept anew
  /// since is moved there as it always was. ⛔So an answer can go stale, and
  /// never wrong. A hot cel is moved on a worker that reads its blocks where
  /// they lie ([moveHotCelInWorker]); a move of whole tiles, nothing to move
  /// among them, is thawed alone ([moveCelInWorker]) and a hot cel left be.
  Future<void> moveCutCelsAhead(
    Iterable<CutId> cutIds,
    CelMove move, {
    void Function(double done)? report,
  }) async {
    final answers = <BrushFrameKey, _MovedCel>{};
    _movedAhead = (move: move, answers: answers);
    final keys = [for (final cutId in cutIds) ..._celKeysOfCut(cutId)];
    var done = 0;
    await Future.wait([
      for (final key in keys)
        _moveOnAWorker(key, move, answers).whenComplete(() {
          done += 1;
          report?.call(done / keys.length);
        }),
    ]);
  }

  /// [key]'s kept cel thawed and moved by [move] on a worker
  /// ([moveCelInWorker]): kept hot here, and its move held in [answers] —
  /// or, hot already, moved there alone ([_moveHotOnAWorker]).
  Future<void> _moveOnAWorker(
    BrushFrameKey key,
    CelMove move,
    Map<BrushFrameKey, _MovedCel> answers,
  ) async {
    final hot = _bakedSurfaces[key];
    if (hot != null) {
      return _moveHotOnAWorker(key, hot, move, answers);
    }
    BitmapSurface? moved;
    final from = await _thawOnAWorker(key, () => _kept(key)?.ref, (
      blob,
    ) async {
      final reach = _pasteboardReach;
      final laid = await moveCelInWorker(
        key,
        blob,
        reach: reach,
        move: move,
      );
      final laidMoved = laid.moved;
      moved = laidMoved == null ? null : _adoptedBehind(laidMoved, reach);
      return _adoptedBehind(laid.was, reach);
    });
    final worked = moved;
    if (from != null && worked != null) {
      answers[key] = (from: from, moved: worked);
    }
  }

  /// [key]'s hot [surface] moved by [move] on a worker that reads its blocks
  /// where they lie ([moveHotCelInWorker]); the move held in [answers]. None
  /// for a move of whole tiles: [_moved] renames the very tiles where it is
  /// taken.
  Future<void> _moveHotOnAWorker(
    BrushFrameKey key,
    BitmapSurface surface,
    CelMove move,
    Map<BrushFrameKey, _MovedCel> answers,
  ) async {
    final tileSize = surface.tileSize;
    if (movesWholeTiles(dx: move.dx, dy: move.dy, tileSize: tileSize)) {
      return;
    }
    final worked = await _remadeOnAWorker(
      surface,
      () => moveHotCelInWorker(key, surface, move: move),
    );
    final moved = worked?.made;
    if (worked != null && moved != null) {
      answers[key] = (from: worked.from, moved: moved);
    }
  }

  /// [surface] — a hot cel's — made anew on a worker that reads its blocks
  /// where they lie ([remake]), in [celThawTurns]: [made] null where the
  /// remake leaves the picture as it is. Null as a whole where the worker
  /// failed: the step makes it as it always did.
  Future<_RemadeCel?> _remadeOnAWorker(
    BitmapSurface surface,
    Future<BitmapSurface?> Function() remake,
  ) => celThawTurns.run(() async {
    try {
      final made = await remake();
      // [surface] is held to here, past the worker that read its blocks.
      return (from: surface, made: made);
    } on Object {
      return null;
    }
  });

  /// What [moveCutCelsAhead] last worked out — until the next one replaces
  /// it, a move it was not worked out for asks ([_moved]), or the store is
  /// laid in anew.
  _MovedAhead? _movedAhead;

  /// [key] as [moveCutCelsAhead] worked out its move, while it is held.
  @visibleForTesting
  BitmapSurface? movedAheadOf(BrushFrameKey key) =>
      _movedAhead?.answers[_canonicalize(key)]?.moved;

  /// The pool files each cel's photos name, by cel — every cel that has
  /// any (I-97): what the media pool asks of a sheet's ink (사용 중 · 제거 ·
  /// 다시 연결 · 열 때 옮기기).
  ///
  /// Off the picture for a hot cel and off the ref for one whose bytes are
  /// in a file, so asking decodes nothing. A cel in two tiers at once — a
  /// clean promoted cel, hot AND file-backed — is the same bytes in both:
  /// an edit lets go of the ref ([storeBakedSurface]).
  Map<BrushFrameKey, List<String>> get celPhotoPathsByKey {
    final named = <BrushFrameKey, List<String>>{
      for (final MapEntry(:key, value: surface) in _bakedSurfaces.entries)
        if (surface.photos.isNotEmpty) key: celPhotoPaths(surface.photos),
    };
    for (final refs in [_coldCels, _fileCels]) {
      for (final MapEntry(:key, value: ref) in refs.entries) {
        if (ref.photoPaths.isNotEmpty) {
          named.putIfAbsent(key, () => ref.photoPaths);
        }
      }
    }
    return named;
  }

  List<BrushFrameKey> _celKeysOfCut(CutId cutId) => <BrushFrameKey>{
    // A set: a clean promoted cel is hot AND file-backed at once.
    for (final key in _bakedSurfaces.keys)
      if (key.cutId == cutId) key,
    for (final key in _coldCels.keys)
      if (key.cutId == cutId) key,
    for (final key in _fileCels.keys)
      if (key.cutId == cutId) key,
  }.toList();

  /// Adopts a new canvas size for every baked surface (R19: a resize is
  /// a raster crop/extend — top-left anchored, every tile kept, so
  /// shrinking then growing back restores exactly). Cold cels transform
  /// one at a time through a decode→resize→re-encode round trip and STAY
  /// cold — a 1500-cel project must never materialize whole for a resize.
  /// Resizes EVERY cel regardless of cut — ONLY for single-canvas
  /// dedicated stores (the timesheet ink planes, whose band keys spread
  /// across sentinel cut ids but share one page geometry). The MAIN
  /// canvas store must never call this: its canvas sizes are per-cut
  /// (see [resizeBakedSurfaces]).
  void resizeAllBakedSurfacesSingleCanvas(CanvasSize canvasSize) {
    final cutIds = <CutId>{
      for (final key in _bakedSurfaces.keys) key.cutId,
      for (final key in _coldCels.keys) key.cutId,
      for (final key in _fileCels.keys) key.cutId,
    };
    for (final cutId in cutIds) {
      resizeBakedSurfaces(canvasSize, cutId: cutId);
    }
  }

  /// R27: STRICTLY cut-scoped. Canvas sizes are PER-CUT, and the old
  /// store-global resize ran on every cut SWITCH between different
  /// sizes — clipping every other-sized cut's cels to the new active
  /// size (954 of 1024 tiles of an 8K fill deleted by one visit to a
  /// default-sized cut; the user's data-loss report).
  void resizeBakedSurfaces(CanvasSize canvasSize, {required CutId cutId}) {
    for (final key in _bakedSurfaces.keys.toList()) {
      if (key.cutId != cutId) {
        continue;
      }
      final surface = _bakedSurfaces[key]!;
      if (surface.canvasSize == canvasSize) {
        continue;
      }
      _storeHot(key, resizeBitmapSurfaceCanvas(surface, canvasSize));
      _fileCels.remove(key);
      _markDirty(key);
      // A crop can take every line with it.
      _recordCelContent(key);
    }
    _announceCrossings();
    _rewriteKeptCels(
      skips: (key, ref) => key.cutId != cutId || ref.canvasSize == canvasSize,
      rewrite: (surface) =>
          resizeBitmapSurfaceCanvas(_behind(surface), canvasSize),
    );
  }

  /// Rewrites every cel whose bytes are kept in a FILE — parked in the
  /// run's room or in the saved project — that [rewrite] changes: decoded,
  /// rewritten, re-encoded and re-parked in the room. [skips] answers from
  /// the ref alone, before a byte is read; [rewrite] answers null for a
  /// picture that stays as it is. Returns the pictures rewritten, as they
  /// were read.
  ///
  /// 🚨★★★**ONE LOOP, BECAUSE THE TWO WERE THE SAME ALGORITHM.** The
  /// parked half and the project-file half differ in exactly one thing —
  /// how the bytes are read — and everything else (skip, decode, rewrite,
  /// re-encode, park, mark dirty) was written out twice — and then a
  /// third time, when a pasteboard's wall moved (I-109) as a resize does.
  /// ⛔The destination is the same either way: the `.anicel` is read-only
  /// from here, so a rewritten cel is unsaved work and belongs in the room
  /// with the rest of it.
  ///
  /// ⛔A read that answers null leaves the cel EXACTLY as it was — ref,
  /// file and all. A cel that will not read right now is not a cel to
  /// rewrite into nothing; the next pass finds it again.
  ///
  /// [ahead] holds what was worked out already, by the ref it was worked
  /// out from ([cutCelsAhead]) — null for a cel left as it is — and a
  /// ref it holds is not read again. [stands] hears each ref the pass
  /// leaves standing: one left as it is, and one kept anew.
  Map<BrushFrameKey, BitmapSurface> _rewriteKeptCels({
    required bool Function(BrushFrameKey key, AnicelCelFileRef ref) skips,
    required BitmapSurface? Function(BitmapSurface surface) rewrite,
    Map<AnicelCelFileRef, _KeptCelRewrite?>? ahead,
    void Function(AnicelCelFileRef ref)? stands,
  }) {
    final rewritten = <BrushFrameKey, BitmapSurface>{};
    for (final (from, read) in _keptSources) {
      for (final key in from.keys.toList()) {
        final ref = from[key]!;
        if (skips(key, ref)) {
          continue;
        }
        final worked = ahead != null && ahead.containsKey(ref)
            ? (rewrite: ahead.remove(ref))
            : _rewriteHere(key, read(ref), rewrite);
        if (worked == null) {
          continue;
        }
        final next = worked.rewrite;
        if (next == null) {
          stands?.call(ref);
          continue;
        }
        // ⚠️Out of the source map FIRST when it is not the destination: a
        // file-backed cel that stayed in `_fileCels` would claim the saved
        // archive still holds bytes the rewrite just replaced.
        if (!identical(from, _coldCels)) {
          from.remove(key);
        }
        _keepCold(key, next.kept);
        stands?.call(next.kept);
        _markDirty(key);
        rewritten[key] = next.was;
      }
    }
    return rewritten;
  }

  /// [key]'s kept [blob] rewritten HERE: its rewrite — null for a picture
  /// left as it is — or null when there is nothing to read or the room
  /// would not take the rewritten bytes, and the cel waits for the next
  /// pass exactly as it was.
  ({_KeptCelRewrite? rewrite})? _rewriteHere(
    BrushFrameKey key,
    AnicelCelBlob? blob,
    BitmapSurface? Function(BitmapSurface surface) rewrite,
  ) {
    if (blob == null) {
      return null;
    }
    final was = blob.decode().toSurface();
    final cut = rewrite(was);
    if (cut == null) {
      return (rewrite: null);
    }
    final kept = AnicelCelBlob.ofSurface(key, cut);
    final path = ScratchCelFiles.write(
      _scratchNamespace,
      anicelCelEntryName(key),
      kept.bytes,
    );
    return path == null
        ? null
        : (rewrite: (kept: _parkedRef(path, kept), was: was));
  }

  /// Where a cel that is not hot keeps its bytes, each with how they are
  /// read: parked in the run's room, or in the saved project — what a pass
  /// over the kept cels walks ([_rewriteKeptCels]), and what one worked
  /// out ahead of it walks too ([cutCelsAhead]).
  List<
    (
      Map<BrushFrameKey, AnicelCelFileRef>,
      AnicelCelBlob? Function(AnicelCelFileRef),
    )
  >
  get _keptSources => [
    (_coldCels, _readScratchBlob),
    (_fileCels, (ref) => AnicelCelBlob(_readFileRefBytes(ref))),
  ];

  /// The HOT surface for [key], or null — NO materialization: cold and
  /// file cels answer null. The resize command's retained-bytes account
  /// reads this to identity-diff its snapshot against the live tiles
  /// without pulling anything hot as a side effect.
  BitmapSurface? hotBakedSurfaceOrNull(BrushFrameKey key) =>
      _bakedSurfaces[_canonicalize(key)];

  /// The cut's baked surfaces by key — cold cels of the cut materialize
  /// (cut-scoped = bounded); surfaces are immutable, so the snapshot is
  /// reference-cheap from there (the anchored-resize command keeps one
  /// for its exact undo).
  Map<BrushFrameKey, BitmapSurface> bakedSurfacesForCut(CutId cutId) {
    return {
      for (final key in _celKeysOfCut(cutId)) key: bakedSurfaceOrNull(key)!,
    };
  }

  /// Restores a [bakedSurfacesForCut] snapshot (anchored-resize undo):
  /// the cut's baked set becomes exactly the snapshot again.
  void restoreBakedForCut(
    CutId cutId,
    Map<BrushFrameKey, BitmapSurface> snapshot,
  ) {
    for (final key in _celKeysOfCut(cutId)) {
      _removeBaked(key);
    }
    for (final entry in snapshot.entries) {
      _storeHot(entry.key, entry.value);
      _fileCels.remove(entry.key);
      _markDirty(entry.key);
      // The display caches follow the restored truth.
      storeRebuiltDisplayCache(key: entry.key, previewSurface: entry.value);
      // The removal above crossed each drawn cel to empty; this crosses it
      // back, or the detector would remember the cut as blank.
      _recordCelContent(entry.key);
    }
    _announceCrossings();
    _scheduleCooling();
  }

  BrushFrameDisplayCache storeRebuiltDisplayCache({
    required BrushFrameKey key,
    required BitmapSurface previewSurface,
  }) {
    key = _canonicalize(key);
    final state = getOrCreateFrame(key);
    final cache = BrushFrameDisplayCache(
      frameKey: key,
      previewSurface: previewSurface,
      sourceRevision: state.sourceRevision,
      dirty: false,
    );
    // A movie cel's picture already lives in the movie tier; banking a copy
    // per position would hold a whole take here with nothing to let it go.
    if (movieCelOf(key.frameId) != null) {
      return cache;
    }
    _putDisplayCache(key, cache);
    _frames[key] = state.copyWith(inactivePreviewDirty: false);
    return cache;
  }

  /// Records a pixel edit on the cel (R19 P3b — commands retired, this
  /// is the ONLY mutation signal): bumps the source revision so playback
  /// image caches invalidate, and dirties the display-cache bookkeeping
  /// until the follow-up donation refreshes it.
  ///
  /// ⚠️It does NOT take the tiles the edit touched, and asking for them
  /// here would be asking twice: the tile-granular answer is what
  /// `BrushFrameCacheInvalidation` carries, and that one has readers. This
  /// used to accept a `dirtyTiles` set and union it into two ledgers
  /// neither of which was ever read — while one call away the same word
  /// meant the opposite (`_invalidateBrushFrame(dirtyTiles: null)` says
  /// 「the whole frame」, and this said 「add nothing」).
  ///
  /// [backTo] is the revision that named the pixels this edit lays back —
  /// an undo giving a cel back the very picture a revision named
  /// ([adoptPasteboardReach]'s answer). The cel is at that revision again,
  /// and every picture made under it answers for it again.
  ///
  /// 🔬F-432 ④ (2026-10-27, Surface Pro 11, the verifier's pasteboard
  /// project): undoing the pasteboard turned off gave its five cels new
  /// revisions, so the frame's picture — the wall's whole 7040×4992 — was
  /// made again from every tile, 0.5–1.1 s on the raster thread, while the
  /// picture of exactly those pixels was still in the store.
  /// ⛔Only for the pixels that revision named: a revision names one
  /// picture of one cel, and a cache under it would show that picture for
  /// any other.
  BrushFrameDrawingState markCelEdited(BrushFrameKey key, {int? backTo}) {
    final next = _update(
      _canonicalize(key),
      (state) => _markCacheDirty(state, revision: backTo),
    );
    // The composite caches this edit just invalidated have no event of
    // their own (they self-validate by signature) — see [celPixelRevision].
    celPixelRevision.value += 1;
    return next;
  }

  BrushFrameDrawingState _markCacheDirty(
    BrushFrameDrawingState state, {
    int? revision,
  }) {
    final next = state.copyWith(
      inactivePreviewDirty: true,
      sourceRevision: revision ?? _nextRevision(),
    );
    final existing = _displayCaches[state.key];
    if (existing != null) {
      _displayCaches[state.key] = existing.copyWith(
        dirty: true,
        sourceRevision: next.sourceRevision,
      );
    }
    return next;
  }

  BrushFrameDrawingState _update(
    BrushFrameKey key,
    BrushFrameDrawingState Function(BrushFrameDrawingState state) update,
  ) {
    final next = update(getOrCreateFrame(key));
    _frames[key] = next;
    return next;
  }
}

/// A cel whose bytes are IN A FILE: {path, offset, length} plus the canvas
/// geometry, so a size check never touches the disk.
///
/// 🚨★★★**TWO FILES USE THIS SHAPE, AND WHICH MAP HOLDS IT IS WHAT SAYS
/// WHICH.**
/// · `_fileCels` — the SAVED `.anicel` (R22-C). Its STORE'd entry bytes
///   ARE the [AnicelCelBlob], the ref survives a clean promotion, and an
///   incremental save may SKIP the cel because the file already holds it.
/// · `_coldCels` — the run's 이사대기 room. Same shape, opposite meaning:
///   these bytes are UNSAVED, so the next save must write them and the
///   room's own ending is what eventually takes the file.
///
/// ⛔The two are not merged into one map with a flag. 「Where are the
/// bytes」 and 「may the save skip this」 are two questions, and one field
/// answering both is the shape this codebase treats as an invention. The
/// second question already has an owner: `_dirtySinceSave`.
///
/// An append never moves existing entry data, but the in-place compaction
/// does — and moves the refs with it first ([BrushFrameStore.
/// relocateFileRefs]); a whole write re-issues refs. A scratch ref is
/// always at offset 0 — one cel, one file.
class AnicelCelFileRef {
  const AnicelCelFileRef({
    required this.filePath,
    required this.dataOffset,
    required this.length,
    required this.canvasSize,
    required this.tileSize,
    required this.photoPaths,
    required this.showsSomething,
  });

  /// The ref to the SAME bytes where they are now — moved to another file
  /// or another offset, everything they say about themselves carried as it
  /// was.
  ///
  /// 🚨★★★ONE door for every move of a ref (a rescue's repoint, a
  /// compaction's relocation, the coordinated swap's new path). Each wrote
  /// the fields out by hand, so a field added here dropped silently out of
  /// all three — the photo index (I-97) would have, 저장 세션 2026-10-15
  /// (`coordinated_project_swap.dart` was the one easy to miss).
  AnicelCelFileRef movedTo({String? filePath, int? dataOffset, int? length}) =>
      AnicelCelFileRef(
        filePath: filePath ?? this.filePath,
        dataOffset: dataOffset ?? this.dataOffset,
        length: length ?? this.length,
        canvasSize: canvasSize,
        tileSize: tileSize,
        photoPaths: photoPaths,
        showsSomething: showsSomething,
      );

  final String filePath;
  final int dataOffset;
  final int length;
  final CanvasSize canvasSize;
  final int tileSize;

  /// The pool files the cel's photos name, as its head indexes them
  /// (`AnicelCelBlob.photoPaths`, I-97) — what the media pool asks of a cel
  /// it does not decode.
  final List<String> photoPaths;

  /// Whether the picture these bytes hold has anything to show, as its head
  /// says (`AnicelCelBlob.showsSomething`) — what a cel's block asks of a
  /// cel that is not hot ([BrushFrameStore.celHasRenderableContent]).
  final bool showsSomething;
}

/// A picture a move of the pasteboard's wall cut from a cel, as it was, and
/// the revision that named it ([BrushFrameStore.adoptPasteboardReach]).
typedef WallCut = ({BitmapSurface picture, int revision});

/// A kept cel rewritten: the bytes it is [kept] as now, in the room, and the
/// picture it [was] — what the move that rewrote it hands its undo.
typedef _KeptCelRewrite = ({AnicelCelFileRef kept, BitmapSurface was});

/// What a move of the wall to [reach] makes of the cels, worked out
/// ahead of it ([BrushFrameStore.cutCelsAhead]): the kept ones by the ref
/// each answer was worked out from — null for a cel the wall leaves as it
/// is — and the [hot] ones by cel.
typedef _CutAhead = ({
  PasteboardReach reach,
  Map<AnicelCelFileRef, _KeptCelRewrite?> answers,
  Map<BrushFrameKey, _RemadeCel> hot,
});

/// A hot cel made anew on a worker, with the picture it was made [from]:
/// [made] null where the work left it as it is.
typedef _RemadeCel = ({BitmapSurface from, BitmapSurface? made});

/// A kept cel and how its bytes are [read] off its [ref], as
/// [BrushFrameStore.cutCelsAhead] walks them.
typedef _KeptRead = ({
  BrushFrameKey key,
  AnicelCelFileRef ref,
  AnicelCelBlob? Function(AnicelCelFileRef ref) read,
});

/// A cel as a [CelMove] leaves it, with the picture it was worked out [from].
typedef _MovedCel = ({BitmapSurface from, BitmapSurface moved});

/// What a resize's [move] makes of a cut's kept cels, worked out ahead of
/// it ([BrushFrameStore.moveCutCelsAhead]), by cel.
typedef _MovedAhead = ({
  CelMove move,
  Map<BrushFrameKey, _MovedCel> answers,
});
