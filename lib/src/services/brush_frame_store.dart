import 'dart:io';
import 'dart:typed_data';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../models/bitmap_surface.dart';
import '../models/canvas_size.dart';
import '../models/brush_frame_display_cache.dart';
import '../models/brush_frame_drawing_state.dart';
import '../models/brush_frame_key.dart';
import '../models/cut_id.dart';
import '../models/dirty_tile_set.dart';
import 'bitmap_surface_geometry.dart';
import 'persistence/brush_drawing_binary_codec.dart';

/// The hot-tier default for THIS machine: a quarter of physical RAM,
/// clamped to [384MB, 1536MB]. Null/zero RAM (the platform refused, or
/// no engine — tests, host runs) keeps the desktop-class 1536MB, which
/// is exactly what every machine got before this existed.
///
/// 유저 확정 (2026-08-16): 「추천대로」 — RAM 비례 기본값 + 압박 반응.
/// A 3GB tablet lands at ~768MB instead of being asked to hold a
/// desktop's 1.5GB of hot cels; a 12GB iPad keeps today's number.
int deviceScaledHotCelBudget({required int? physicalMemoryBytes}) {
  const desktopDefault = 1536 * 1024 * 1024;
  const floor = 384 * 1024 * 1024;
  if (physicalMemoryBytes == null || physicalMemoryBytes <= 0) {
    return desktopDefault;
  }
  final quarter = physicalMemoryBytes ~/ 4;
  if (quarter < floor) {
    return floor;
  }
  return quarter > desktopDefault ? desktopDefault : quarter;
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
  /// manage canonical storage directly.
  BrushFrameKey Function(BrushFrameKey key) _canonicalize = _identityKey;

  static BrushFrameKey _identityKey(BrushFrameKey key) => key;

  /// Installs (or clears, with null) the canonical-key resolver — wire it
  /// to the current project's [LayerLinkRegistry.canonicalCelKey]. The
  /// resolver must be idempotent.
  void setLinkResolver(BrushFrameKey Function(BrushFrameKey key)? resolver) {
    _canonicalize = resolver ?? _identityKey;
  }

  final Map<BrushFrameKey, BrushFrameDrawingState> _frames = {};

  /// R27 #13: bumps whenever a cel crosses the EMPTY ↔ has-picture line.
  ///
  /// The timeline's "no picture yet" tint reads [celHasRenderableContent],
  /// which flips on the first committed stroke — but nothing told the
  /// timeline to look again, so the tint sat there until some unrelated
  /// rebuild (switching layers) came along. Only the CROSSING bumps, so a
  /// stroke on an already-drawn cel costs nothing.
  final ValueNotifier<int> celContentRevision = ValueNotifier<int>(0);

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
    final has = _bakedSurfaces.containsKey(canonicalKey) ||
        _coldCels.containsKey(canonicalKey) ||
        _fileCels.containsKey(canonicalKey);
    final had = _celsWithContent.contains(canonicalKey);
    if (has == had) {
      return;
    }
    if (has) {
      _celsWithContent.add(canonicalKey);
    } else {
      _celsWithContent.remove(canonicalKey);
    }
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

  BrushFrameDrawingState? frameOrNull(BrushFrameKey key) =>
      _frames[_canonicalize(key)];

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

  /// Drops every derived display cache, e.g. after a canvas resize makes the
  /// cached preview surfaces the wrong size. Source paint commands are kept.
  void clearDisplayCaches() {
    _displayCaches.clear();
  }

  // -------------------------------------------------------------------
  // Baked raster truth (R19 bake-only / R20-A1 / R22-C three-tier).
  //
  // A cel's picture IS its baked tile raster. The truth lives in THREE
  // forms (sized for 400-cut TV / 1500-cut theatrical projects with NO
  // temp files — the user's project file is the only disk artifact):
  //
  //  - HOT: a BitmapSurface, insertion-ordered as an LRU (access
  //    re-inserts). Byte-budgeted by [hotCelByteBudget].
  //  - COLD-RAM: a [AnicelCelBlob] — the cel encoded + deflated, the SAME
  //    bytes the .anicel archive stores. Over-budget hot cels cool here in
  //    a background isolate; unsaved (dirty) cels never leave RAM.
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
  // surface references (HistoryManager.retainedByteBudget).

  final Map<BrushFrameKey, BitmapSurface> _bakedSurfaces = {};
  final Map<BrushFrameKey, AnicelCelBlob> _coldCels = {};
  final Map<BrushFrameKey, AnicelCelFileRef> _fileCels = {};
  final Map<BrushFrameKey, int> _hotByteEstimates = {};
  int _hotBytes = 0;
  int _coldBytes = 0;

  /// Cels edited since the last successful save (donations/removals, not
  /// mere promotions) — exactly the set an incremental save must write.
  final Set<BrushFrameKey> _dirtySinceSave = {};

  Set<BrushFrameKey> get dirtyCelKeysSinceSave =>
      Set.unmodifiable(_dirtySinceSave);

  /// Hot-tier byte budget. Cels beyond it cool (encode + deflate) in LRU
  /// order in a background isolate. Test-settable; the session seeds it
  /// with [deviceScaledHotCelBudget] at construction (유저 확정
  /// 2026-08-16: RAM 비례 + 메모리 압박 반응 — a 3GB tablet was being
  /// asked to hold a desktop's 1.5GB of hot cels).
  int hotCelByteBudget = 1536 * 1024 * 1024;

  /// The OS said memory is tight (`didHaveMemoryPressure`): halve the
  /// budget — floored so the working set never thrashes — and cool NOW.
  /// Lowering the budget loses nothing: over-budget cels encode to the
  /// cold tier, and dirty cels never leave RAM by design.
  void respondToMemoryPressure() {
    const floor = 256 * 1024 * 1024;
    final halved = hotCelByteBudget ~/ 2;
    final lowered = halved < floor ? floor : halved;
    // Pressure only ever LOWERS: a budget already under the floor
    // (a test, or a deliberately tight caller) must not be raised by
    // the very signal that says memory is scarce.
    if (lowered < hotCelByteBudget) {
      hotCelByteBudget = lowered;
    }
    _scheduleCooling();
  }

  /// Bytes currently resident in the hot tier (diagnostics/tests).
  int get hotBakedBytes => _hotBytes;

  /// Blob bytes currently resident in the cold RAM tier
  /// (diagnostics/tests).
  int get coldBakedBytes => _coldBytes;

  /// Keys currently in the cold RAM tier (diagnostics/tests).
  Iterable<BrushFrameKey> get coldCelKeys => _coldCels.keys;

  /// Keys currently backed by the saved project file (diagnostics/tests).
  Iterable<BrushFrameKey> get fileCelKeys => _fileCels.keys;

  bool isCelCold(BrushFrameKey key) => _coldCels.containsKey(key);

  bool isCelFileBacked(BrushFrameKey key) => _fileCels.containsKey(key);

  /// The cel's baked raster truth, or null for a never-drawn cel. A cold
  /// cel materializes (inflate + decode) and promotes to hot right here;
  /// a file-backed cel reads its bytes from the saved .anicel first — this
  /// is the ONE seam every pixel consumer goes through.
  BitmapSurface? bakedSurfaceOrNull(BrushFrameKey key) {
    key = _canonicalize(key);
    final hot = _bakedSurfaces.remove(key);
    if (hot != null) {
      _bakedSurfaces[key] = hot; // LRU touch.
      return hot;
    }
    var cold = _coldCels[key];
    if (cold == null) {
      final fileRef = _fileCels[key];
      if (fileRef == null) {
        return null;
      }
      // The ref stays: the file still holds these exact bytes, so a
      // later cooling of this (clean) cel is a free drop.
      cold = AnicelCelBlob(_readFileRefBytes(fileRef));
    } else {
      _coldCels.remove(key);
      _coldBytes -= cold.bytes.length;
    }
    final surface = cold.decode().toSurface();
    _storeHot(key, surface);
    // Reseed the display cache from the same object so first paint after
    // a promotion is O(1), mirroring what open used to do eagerly.
    storeRebuiltDisplayCache(key: key, previewSurface: surface);
    _scheduleCooling();
    return surface;
  }

  static Uint8List _readFileRefBytes(AnicelCelFileRef ref) {
    final raf = File(ref.filePath).openSync();
    try {
      raf.setPositionSync(ref.dataOffset);
      return raf.readSync(ref.length);
    } finally {
      raf.closeSync();
    }
  }

  void _storeHot(BrushFrameKey key, BitmapSurface surface) {
    final previous = _hotByteEstimates.remove(key);
    if (previous != null) {
      _hotBytes -= previous;
    }
    final estimate =
        surface.tiles.length * surface.tileSize * surface.tileSize * 4;
    _bakedSurfaces.remove(key);
    _bakedSurfaces[key] = surface;
    _hotByteEstimates[key] = estimate;
    _hotBytes += estimate;
  }

  void _removeBaked(BrushFrameKey key) {
    _bakedSurfaces.remove(key);
    final cold = _coldCels.remove(key);
    if (cold != null) {
      _coldBytes -= cold.bytes.length;
    }
    _fileCels.remove(key);
    final estimate = _hotByteEstimates.remove(key);
    if (estimate != null) {
      _hotBytes -= estimate;
    }
    _dirtySinceSave.add(key);
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
    if (surface.tiles.isEmpty) {
      _removeBaked(key);
      return;
    }
    final cold = _coldCels.remove(key);
    if (cold != null) {
      _coldBytes -= cold.bytes.length;
    }
    _fileCels.remove(key);
    _storeHot(key, surface);
    _dirtySinceSave.add(key);
    _noteCelContent(key);
    _scheduleCooling();
  }

  /// Every baked cel for the save payload: hot surfaces (the saver
  /// encodes them), cold blobs (already archive bytes — written through
  /// with ZERO re-encode) and file refs (already IN the saved .anicel; a
  /// compaction reads them back, an incremental save skips them
  /// entirely).
  ({
    Map<BrushFrameKey, BitmapSurface> hot,
    Map<BrushFrameKey, AnicelCelBlob> cold,
    Map<BrushFrameKey, AnicelCelFileRef> fileRefs,
  })
  bakedSnapshotForSave() {
    return (
      hot: {..._bakedSurfaces},
      cold: {..._coldCels},
      fileRefs: {..._fileCels},
    );
  }

  void _clearAllTiers() {
    _frames.clear();
    clearDisplayCaches();
    _bakedSurfaces.clear();
    _coldCels.clear();
    _fileCels.clear();
    _hotByteEstimates.clear();
    _hotBytes = 0;
    _coldBytes = 0;
    _dirtySinceSave.clear();
    // R27 #13: a whole-store swap (project open) is one crossing for
    // every cel there was — one bump covers the lot.
    if (_celsWithContent.isNotEmpty) {
      _celsWithContent.clear();
      celContentRevision.value += 1;
    }
  }

  /// Replaces the WHOLE store with loaded cels as COLD-RAM blobs (tests
  /// and non-file flows). Frames reseed at sourceRevision 1.
  void restoreBaked(Map<BrushFrameKey, AnicelCelBlob> cels) {
    _clearAllTiers();
    for (final entry in cels.entries) {
      _frames[entry.key] = BrushFrameDrawingState(
        key: entry.key,
        sourceRevision: 1,
      );
      _coldCels[entry.key] = entry.value;
      _coldBytes += entry.value.bytes.length;
      _noteCelContent(entry.key);
    }
  }

  /// Replaces the WHOLE store with FILE-BACKED cels (project open,
  /// R22-C): near-zero RAM — every cel reads from the .anicel on first
  /// access. No temp files, ever.
  void restoreFromFile(Map<BrushFrameKey, AnicelCelFileRef> cels) {
    _clearAllTiers();
    for (final entry in cels.entries) {
      _frames[entry.key] = BrushFrameDrawingState(
        key: entry.key,
        sourceRevision: 1,
      );
      _fileCels[entry.key] = entry.value;
      _noteCelContent(entry.key);
    }
  }

  /// After a successful save: every saved cel gains a file ref (hot
  /// cels KEEP their surface — hot + ref coexist until cooling drops
  /// the bytes for free), cold blobs are redundant with the file and
  /// drop, and the dirty set clears — the next incremental save starts
  /// from a clean slate.
  void adoptSavedFile(Map<BrushFrameKey, AnicelCelFileRef> saved) {
    for (final entry in saved.entries) {
      final cold = _coldCels.remove(entry.key);
      if (cold != null) {
        _coldBytes -= cold.bytes.length;
      }
      _fileCels[entry.key] = entry.value;
      // R27 #13: a ref landing on a key that held no tier at all is a
      // crossing (the cel emptied between the save snapshot and this
      // adoption), and this was the other silent tier move the timeline
      // never heard. No-op for the everyday save, where the cel is
      // already hot or cold.
      _noteCelContent(entry.key);
    }
    _dirtySinceSave.clear();
  }

  /// Whether the cel shows ANY picture content — the composite/export/
  /// fill resolvers' emptiness oracle. Every tier counts: representation
  /// is not existence.
  bool celHasRenderableContent(BrushFrameKey key) {
    key = _canonicalize(key);
    return _bakedSurfaces.containsKey(key) ||
        _coldCels.containsKey(key) ||
        _fileCels.containsKey(key);
  }

  /// The cel's current pixels: a VALID display cache at [canvasSize]
  /// first (donations keep it fresh), else the baked truth (a cold cel
  /// materializes if its recorded size matches). Null = the cel is empty
  /// (or sized for another canvas — resize flows reseed).
  BitmapSurface? currentSurfaceWithoutReplay(
    BrushFrameKey key, {
    required CanvasSize canvasSize,
  }) {
    key = _canonicalize(key);
    final cached = validPreviewSurfaceOrNull(key);
    if (cached != null && cached.canvasSize == canvasSize) {
      return cached;
    }
    final hot = _bakedSurfaces[key];
    if (hot != null) {
      return hot.canvasSize == canvasSize ? bakedSurfaceOrNull(key) : null;
    }
    final cold = _coldCels[key];
    if (cold != null && cold.canvasSize == canvasSize) {
      return bakedSurfaceOrNull(key);
    }
    final fileRef = _fileCels[key];
    if (fileRef != null && fileRef.canvasSize == canvasSize) {
      return bakedSurfaceOrNull(key);
    }
    return null;
  }

  // --- Cooling (hot → cold) -------------------------------------------

  Future<void>? _activeCooling;

  /// Completes when no cooling pass is running (tests).
  Future<void> drainCooling() async {
    while (_activeCooling != null) {
      await _activeCooling;
    }
  }

  void _scheduleCooling() {
    if (_activeCooling != null ||
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
  /// bytes on the main isolate, deflate in a background isolate, then
  /// commit the swap ONLY if the cel's surface is still the identical
  /// object (a donation in between wins and the stale blob is dropped).
  /// The most recently used cel never cools — the one being painted or
  /// displayed must not thrash even if it alone exceeds the budget.
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
      final entry = AnicelCelEntry.fromSurface(key, surface);
      final blob = await Isolate.run(() => AnicelCelBlob.encode(entry));
      if (identical(_bakedSurfaces[key], surface)) {
        _bakedSurfaces.remove(key);
        _hotBytes -= _hotByteEstimates.remove(key)!;
        _coldCels[key] = blob;
        _coldBytes += blob.bytes.length;
        // Drop the derived alias too, or the surface stays resident.
        _displayCaches.remove(key);
      }
    }
  }

  /// Completes when no background tiering pass is running (tests).
  /// R22-C: cooling is the only background pass left — the scratch-disk
  /// spill is gone (the saved .anicel itself is the disk tier).
  Future<void> drainTiering() => drainCooling();

  /// Re-homes stored drawings under new keys (a cross-layer block move,
  /// R10-④b): content is untouched, so the display cache travels along and
  /// stays valid. Missing sources are skipped (an empty cel moved). The
  /// inverse pair list undoes the move exactly.
  void rekeyFrames(List<(BrushFrameKey from, BrushFrameKey to)> pairs) {
    for (final (from, to) in pairs) {
      final state = _frames.remove(from);
      if (state != null) {
        _frames[to] = state.copyWithKey(to);
      }
      final cache = _displayCaches.remove(from);
      if (cache != null) {
        _displayCaches[to] = cache;
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
        _dirtySinceSave.add(from);
        _dirtySinceSave.add(to);
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
    var edited = false;
    for (final key in _celKeysOfCut(cutId)) {
      // Cold cels of the cut materialize first (cut-scoped = bounded).
      final surface = bakedSurfaceOrNull(key)!;
      _storeHot(
        key,
        translateBitmapSurface(
          surface,
          dx: dx.round(),
          dy: dy.round(),
          canvasSize: canvasSize,
        ),
      );
      _fileCels.remove(key);
      _dirtySinceSave.add(key);
      // Per-cel signature bump WITHOUT the per-cel global notify: the
      // global signal fires as often as the user draws and its
      // listeners are honed for single strokes — N cels × N listener
      // walks was part of D3's freeze. One bump covers the lot (the
      // [_clearAllTiers] precedent).
      _update(_canonicalize(key), _markCacheDirty);
      edited = true;
    }
    if (edited) {
      celPixelRevision.value += 1;
    }
    _scheduleCooling();
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
      _dirtySinceSave.add(key);
    }
    for (final key in _coldCels.keys.toList()) {
      if (key.cutId != cutId) {
        continue;
      }
      final cold = _coldCels[key]!;
      if (cold.canvasSize == canvasSize) {
        continue;
      }
      final resized = AnicelCelBlob.encode(
        AnicelCelEntry.fromSurface(
          key,
          resizeBitmapSurfaceCanvas(cold.decode().toSurface(), canvasSize),
        ),
      );
      _coldBytes += resized.bytes.length - cold.bytes.length;
      _coldCels[key] = resized;
      _dirtySinceSave.add(key);
    }
    for (final key in _fileCels.keys.toList()) {
      if (key.cutId != cutId) {
        continue;
      }
      final fileRef = _fileCels[key]!;
      if (fileRef.canvasSize == canvasSize) {
        continue;
      }
      // The .anicel is read-only from here — a resized file-backed cel
      // promotes to a COLD-RAM blob (it is now dirty anyway).
      final resized = AnicelCelBlob.encode(
        AnicelCelEntry.fromSurface(
          key,
          resizeBitmapSurfaceCanvas(
            AnicelCelBlob(_readFileRefBytes(fileRef)).decode().toSurface(),
            canvasSize,
          ),
        ),
      );
      _fileCels.remove(key);
      _coldCels[key] = resized;
      _coldBytes += resized.bytes.length;
      _dirtySinceSave.add(key);
    }
  }

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
      _dirtySinceSave.add(entry.key);
      // The display caches follow the restored truth.
      storeRebuiltDisplayCache(key: entry.key, previewSurface: entry.value);
    }
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
    _putDisplayCache(key, cache);
    _frames[key] = state.copyWith(
      inactivePreviewDirty: false,
      cacheDirtyTiles: DirtyTileSet.empty(),
    );
    return cache;
  }

  /// Records a pixel edit on the cel (R19 P3b — commands retired, this
  /// is the ONLY mutation signal): bumps the source revision so playback
  /// image caches invalidate, and dirties the display-cache bookkeeping
  /// until the follow-up donation refreshes it.
  BrushFrameDrawingState markCelEdited(
    BrushFrameKey key, {
    DirtyTileSet? dirtyTiles,
  }) {
    final next = _update(
      _canonicalize(key),
      (state) => _markCacheDirty(state, dirtyTiles: dirtyTiles),
    );
    // The composite caches this edit just invalidated have no event of
    // their own (they self-validate by signature) — see [celPixelRevision].
    celPixelRevision.value += 1;
    return next;
  }

  BrushFrameDrawingState _markCacheDirty(
    BrushFrameDrawingState state, {
    DirtyTileSet? dirtyTiles,
  }) {
    final next = state.copyWith(
      inactivePreviewDirty: true,
      sourceRevision: state.sourceRevision + 1,
      cacheDirtyTiles: dirtyTiles == null
          ? state.cacheDirtyTiles
          : state.cacheDirtyTiles.union(dirtyTiles),
    );
    final existing = _displayCaches[state.key];
    if (existing != null) {
      _displayCaches[state.key] = existing.copyWith(
        dirty: true,
        sourceRevision: next.sourceRevision,
        dirtyTiles: dirtyTiles == null
            ? existing.dirtyTiles
            : existing.dirtyTiles.union(dirtyTiles),
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

/// A cel backed by the SAVED PROJECT FILE itself (R22-C): the .anicel's
/// STORE'd entry bytes ARE the [AnicelCelBlob], so {offset, length} into
/// the file is a complete cold reference — no temp files, ever. Canvas
/// geometry rides along so size checks never touch the disk. Offsets
/// stay valid across incremental appends (appends never move existing
/// entry data); a compaction rewrites the file and re-issues refs.
class AnicelCelFileRef {
  const AnicelCelFileRef({
    required this.filePath,
    required this.dataOffset,
    required this.length,
    required this.canvasSize,
    required this.tileSize,
  });

  final String filePath;
  final int dataOffset;
  final int length;
  final CanvasSize canvasSize;
  final int tileSize;
}
