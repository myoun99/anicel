import 'dart:typed_data';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../models/bitmap_surface.dart';
import '../models/canvas_size.dart';
import '../models/brush_frame_display_cache.dart';
import '../models/brush_frame_drawing_state.dart';
import '../models/brush_frame_key.dart';
import '../models/cut_id.dart';
import 'bitmap_surface_geometry.dart';
import 'memory_pressure_budget.dart';
import 'persistence/brush_drawing_binary_codec.dart';
import 'persistence/open_project_file.dart';
import 'persistence/anicel_project_archive.dart' show anicelCelEntryName;
import 'persistence/scratch_cel_files.dart';
import 'persistence/scratch_file.dart';
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

  /// The PHYSICAL cel [key] addresses — linked rows are windows onto one
  /// bank, and two different row keys can name the same pixels.
  ///
  /// Callers that walk several rows in one pass need this to avoid acting
  /// on one cel twice: a second recolour of the same bank would record the
  /// colour the first one just wrote as "the original", and undo would
  /// stop halfway.
  BrushFrameKey canonicalKeyOf(BrushFrameKey key) => _canonicalize(key);

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
  // surface no longer holds (`BitmapSurface.tilesNotSharedWith`).
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
  final Map<BrushFrameKey, AnicelCelFileRef> _coldCels = {};
  final Map<BrushFrameKey, AnicelCelFileRef> _fileCels = {};
  final Map<BrushFrameKey, int> _hotByteEstimates = {};
  int _hotBytes = 0;
  int _coldBytes = 0;

  /// Cels edited since the last successful save (donations/removals, not
  /// mere promotions) — exactly the set an incremental save must write.
  final Set<BrushFrameKey> _dirtySinceSave = {};

  /// Monotonic edit clock + per-key last-edit marks, for the one question
  /// the dirty SET cannot answer: "was this cel edited AFTER the save
  /// snapshot was taken?" The set survives the whole save untouched, so at
  /// adoption time a key that was dirty when the snapshot was captured and
  /// a key that went dirty DURING the save look identical — and treating
  /// them the same is how an in-flight stroke used to vanish: adoption
  /// re-installed the pre-edit file ref, the wholesale clear() wiped the
  /// mark, and cooling then "free-dropped" the only copy of the new
  /// pixels. Marks are removed when their edit is adopted into a save, so
  /// the map holds only unsaved work.
  int _editTick = 0;
  final Map<BrushFrameKey, int> _editTicks = {};

  Set<BrushFrameKey> get dirtyCelKeysSinceSave =>
      Set.unmodifiable(_dirtySinceSave);

  /// Hot-tier byte budget. Cels beyond it cool (encode + compress) in LRU
  /// order in a background isolate. Test-settable; the session seeds it
  /// with [deviceScaledHotCelBudget] at construction (유저 확정
  /// 2026-08-16: RAM 비례 + 메모리 압박 반응 — a 3GB tablet was being
  /// asked to hold a desktop's 1.5GB of hot cels).
  int get hotCelByteBudget => _hotBudget.bytes;

  set hotCelByteBudget(int value) => _hotBudget.bytes = value;

  /// Halving, floored at 256MB so the working set never thrashes. The
  /// lowers-only guard lives in [MemoryPressureBudget] — it was written
  /// out longhand here, again in `HistoryManager`, and would have been a
  /// third time in the viewer.
  final MemoryPressureBudget _hotBudget = MemoryPressureBudget.halving(
    normal: 1536 * 1024 * 1024,
    floor: 256 * 1024 * 1024,
  );

  /// The OS said memory is tight (`didHaveMemoryPressure`): halve the
  /// budget — floored so the working set never thrashes — and cool NOW.
  /// Lowering the budget loses nothing: over-budget cels encode to the
  /// cold tier, and dirty cels never leave RAM by design.
  void respondToMemoryPressure() {
    _hotBudget.respondToMemoryPressure();
    // Cool even when the budget did not move: a warning arriving while
    // the hot tier is already over an ALREADY-low budget is exactly when
    // cooling matters most.
    _scheduleCooling();
    // ⛔Not awaited, exactly as the cooling pass above is not: a memory
    // warning is no place to wait on an isolate. Each snapshot joins its
    // own park if one is already in flight, so a burst of warnings costs
    // one encode.
    _activeLiftParking = UndoSurfaceSnapshot.parkAll(
      _liftedPixels.values,
    ).whenComplete(() => _activeLiftParking = null);
  }

  /// Pixels a TOOL has taken out of the picture and is holding until it
  /// puts them back — a lifted selection under an open transform box, and
  /// nothing else today.
  ///
  /// 🚨★★★**THE SAME BYTES WERE DISCIPLINED ON ONE SIDE OF A CONFIRM AND
  /// NOT THE OTHER.** The moment a confirm turns a lift into a history
  /// entry the pixels are budgeted and parkable ([UndoSurfacePair]); while
  /// the box was still open they were a plain Map field in a widget's
  /// State, with no budget, no cap and no spill — so a user who had NOT
  /// confirmed was held to less discipline than one who had. Measured on a
  /// 2340×1654 cel: a whole-picture Ctrl+T pins 17.5 MiB here, and the
  /// image cache keys on these very tile objects, so up to 17.5 MiB of GPU
  /// textures ride along. 유저 확정 2026-09-08 (`undo-41-hole-scope` = ①).
  ///
  /// 🔬**Krita's answer, and the reason this lives HERE.** Krita clears the
  /// source device the moment the box opens, exactly as we do — the lifted
  /// content becomes a `KisPaintDevice`, which is to say *a document device
  /// like any other*, so the tile swapper spills it under pressure and the
  /// transform tool contains no memory-pressure code at all. OpenToonz
  /// holds the shape we used to: raw rasters on a global tool object,
  /// outside the image cache, where a floating selection outlives pressure
  /// while cold cels and undo entries die first.
  ///
  /// ⛔The TOOL still owns the lifetime — it mints the token and releases
  /// it on confirm, revert or landing. This owns only the DISCIPLINE, the
  /// way the tile store does for Krita: the two hold the same object.
  final Map<int, UndoSurfaceSnapshot> _liftedPixels = {};

  Future<void>? _activeLiftParking;

  /// Completes when the warning's parking pass is done (tests).
  ///
  /// ⚠️It exists because a pin that awaited the SNAPSHOT instead did not
  /// measure this class at all: `park()` called by hand does the same work,
  /// so deleting the call above left every test green. The drain is the
  /// only way to ask「did the STORE move them」.
  Future<void> drainLiftedParking() async {
    while (_activeLiftParking != null) {
      await _activeLiftParking;
    }
  }

  void holdLiftedPixels(int token, UndoSurfaceSnapshot pixels) {
    _liftedPixels[token] = pixels;
  }

  void releaseLiftedPixels(int token) {
    _liftedPixels.remove(token);
  }

  /// Bytes a tool's lifted pixels are holding right now (diagnostics/tests)
  /// — zero once they have parked.
  int get liftedPixelBytes =>
      _liftedPixels.values.fold(0, (sum, held) => sum + held.residentBytes);

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
  BitmapSurface? bakedSurfaceOrNull(BrushFrameKey key) {
    key = _canonicalize(key);
    final hot = _bakedSurfaces.remove(key);
    if (hot != null) {
      _bakedSurfaces[key] = hot; // LRU touch.
      return hot;
    }
    final AnicelCelBlob blob;
    final parked = _coldCels[key];
    if (parked == null) {
      final fileRef = _fileCels[key];
      if (fileRef == null) {
        return null;
      }
      // The ref stays: the file still holds these exact bytes, so a
      // later cooling of this (clean) cel is a free drop.
      blob = AnicelCelBlob(_readFileRefBytes(fileRef));
    } else {
      final read = _readScratchBlob(parked);
      if (read == null) {
        // 🚨★★★**THE REF STAYS AND SO DOES THE FILE.** A cold cel is the
        // only copy of that picture outside the hot tier, so a read that
        // fails right now — a volume that blinked, an antivirus holding
        // the file — must not be turned into 「this cel is empty」, which
        // is what dropping the ref would say to every caller and to the
        // next save. The picture is UNAVAILABLE this moment; the next
        // access tries again.
        return null;
      }
      blob = read;
      // Read succeeded, so the bytes are in hand and the parking space is
      // free. ⛔Dropped only AFTER the read, never before it.
      _dropCold(key);
    }
    final surface = blob.decode().toSurface();
    _storeHot(key, surface);
    // Reseed the display cache from the same object so first paint after
    // a promotion is O(1), mirroring what open used to do eagerly.
    storeRebuiltDisplayCache(key: key, previewSurface: surface);
    _scheduleCooling();
    return surface;
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
    final path = ScratchCelFiles.write(name, blob.bytes);
    if (path == null) {
      return false;
    }
    final previous = _coldCels[key];
    if (previous != null) {
      _coldBytes -= previous.length;
      if (previous.filePath != path) {
        ScratchFile.remove(previous.filePath);
      }
    }
    _coldCels[key] = AnicelCelFileRef(
      filePath: path,
      dataOffset: 0,
      length: blob.bytes.length,
      canvasSize: blob.canvasSize,
      tileSize: blob.tileSize,
    );
    _coldBytes += blob.bytes.length;
    return true;
  }

  /// Drops [key]'s cold ref and the file behind it.
  void _dropCold(BrushFrameKey key) {
    final gone = _coldCels.remove(key);
    if (gone == null) {
      return;
    }
    _coldBytes -= gone.length;
    ScratchFile.remove(gone.filePath);
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
    final estimate = surface.tiles.length * surface.tileBytes;
    _bakedSurfaces.remove(key);
    _bakedSurfaces[key] = surface;
    _hotByteEstimates[key] = estimate;
    _hotBytes += estimate;
  }

  void _removeBaked(BrushFrameKey key) {
    _bakedSurfaces.remove(key);
    _dropCold(key);
    _fileCels.remove(key);
    final estimate = _hotByteEstimates.remove(key);
    if (estimate != null) {
      _hotBytes -= estimate;
    }
    _dirtySinceSave.add(key);
    _editTicks[key] = ++_editTick;
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
    _dropCold(key);
    _fileCels.remove(key);
    _storeHot(key, surface);
    _dirtySinceSave.add(key);
    _editTicks[key] = ++_editTick;
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
        for (final key in _dirtySinceSave) key: _editTicks[key] ?? 0,
      },
    );
  }

  void _clearAllTiers() {
    // 🚨★★★**THE FILE REFS GO, SO THE FILE GOES.** A handle nobody can read
    // through still keeps the OS from letting the file be deleted or moved.
    // Holding it past this point is not protection, it is a lock on a file
    // this session has closed.
    //
    // 🧪Found by a test, not by reasoning: `load_heals_mismatched_cels_test`
    // could not delete its own temp folder afterwards. That is exactly what
    // a user closing a project and then tidying the folder would hit.
    //
    // ⚠️**FOUR stores share the one handle** — the main cel store plus the
    // conté row, conté page and envelope ink stores, all holding refs into
    // the SAME `.anicel` (one `open` fills all four:
    // `project_file_door.dart`). So this is not「nothing can name the file
    // any more」, it is「this store cannot」, and it is only the whole truth
    // because the product always swaps the four together (project open, and
    // `_resetSessionForImportedProject`). ⛔Nothing rests on that: letting
    // go early costs one re-open on the next sibling's read, which is why
    // the release is unconditional rather than counted.
    OpenProjectFile.instance.release();
    _frames.clear();
    clearDisplayCaches();
    _bakedSurfaces.clear();
    _coldCels.clear();
    _fileCels.clear();
    _hotByteEstimates.clear();
    _hotBytes = 0;
    _coldBytes = 0;
    _dirtySinceSave.clear();
    _editTicks.clear();
    // R27 #13: a whole-store swap (project open) is one crossing for
    // every cel there was — one bump covers the lot.
    if (_celsWithContent.isNotEmpty) {
      _celsWithContent.clear();
      celContentRevision.value += 1;
    }
  }

  /// Replaces the WHOLE store with loaded cels as COLD-RAM blobs (tests
  /// and non-file flows).
  void restoreBaked(Map<BrushFrameKey, AnicelCelBlob> cels) =>
      _restoreAll(cels, _storeCold);

  /// Replaces the WHOLE store with FILE-BACKED cels (project open,
  /// R22-C): near-zero RAM — every cel reads from the .anicel on first
  /// access. No temp files, ever.
  void restoreFromFile(Map<BrushFrameKey, AnicelCelFileRef> cels) =>
      _restoreAll(cels, (key, ref) => _fileCels[key] = ref);

  /// The whole-store swap both entry points are: every tier cleared, then
  /// each cel seeded and [place]d in the tier its payload belongs to.
  /// Frames reseed at sourceRevision 1.
  ///
  /// ⚠️[place] runs BEFORE [_noteCelContent], which asks
  /// [celHasRenderableContent] — and that reads the tiers.
  void _restoreAll<T>(
    Map<BrushFrameKey, T> cels,
    void Function(BrushFrameKey key, T cel) place,
  ) {
    _clearAllTiers();
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
        (_editTicks[key] ?? 0) > (dirtyTicksAtSnapshot[key] ?? 0);
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
        _editTicks.remove(entry.key);
      }
    }
  }

  /// Whether the cel shows ANY picture content — the composite/export/
  /// fill resolvers' emptiness oracle. Every tier counts: representation
  /// is not existence.
  bool celHasRenderableContent(BrushFrameKey key) {
    key = _canonicalize(key);
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
      //
      // ⛔It does NOT count ink (유저: 「잉크를 세는건 무거운거아니야?」).
      // [BitmapTile.hasInk] caches per tile and `any` stops at the first one
      // that has some — a drawn cel answers on its first tile, and only a
      // cel that is entirely clear reads to the end, once.
      return baked.tiles.values.any((tile) => tile.hasInk);
    }
    // ⛔Cold and file-backed cels answer by membership, deliberately: asking
    // them would MATERIALIZE every cel of the project, and this is called
    // per visible block. They were written from a surface that had ink, and
    // the moment one is edited it becomes baked and takes the branch above.
    return _coldCels.containsKey(key) || _fileCels.containsKey(key);
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
    _resizeRefCels(_coldCels, canvasSize, cutId: cutId, read: _readScratchBlob);
    _resizeRefCels(
      _fileCels,
      canvasSize,
      cutId: cutId,
      read: (ref) => AnicelCelBlob(_readFileRefBytes(ref)),
    );
  }

  /// Re-sizes every cel of [cutId] whose bytes are in a FILE, from either
  /// map, and re-parks the result in the run's room.
  ///
  /// 🚨★★★**ONE LOOP, BECAUSE THE TWO WERE THE SAME ALGORITHM.** The
  /// parked half and the project-file half differ in exactly one thing —
  /// how the bytes are read — and everything else (skip other cuts, skip a
  /// cel already at this size, decode, resize, re-encode, park, mark
  /// dirty) was written out twice. ⛔The destination is the same either
  /// way: the `.anicel` is read-only from here, so a resized cel is
  /// unsaved work and belongs in the room with the rest of it.
  ///
  /// ⛔A read that answers null leaves the cel EXACTLY as it was — ref,
  /// file and all. A cel that will not read right now is not a cel to
  /// resize into nothing; the size check finds it again next time.
  void _resizeRefCels(
    Map<BrushFrameKey, AnicelCelFileRef> from,
    CanvasSize canvasSize, {
    required CutId cutId,
    required AnicelCelBlob? Function(AnicelCelFileRef ref) read,
  }) {
    for (final key in from.keys.toList()) {
      final ref = from[key]!;
      if (key.cutId != cutId || ref.canvasSize == canvasSize) {
        continue;
      }
      final blob = read(ref);
      if (blob == null) {
        continue;
      }
      final resized = AnicelCelBlob.encode(
        AnicelCelEntry.fromSurface(
          key,
          resizeBitmapSurfaceCanvas(blob.decode().toSurface(), canvasSize),
        ),
      );
      // ⚠️Out of the source map FIRST when it is not the destination: a
      // file-backed cel that stayed in `_fileCels` would claim the saved
      // archive still holds bytes the resize just replaced.
      if (!identical(from, _coldCels)) {
        from.remove(key);
      }
      _storeCold(key, resized);
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
  BrushFrameDrawingState markCelEdited(BrushFrameKey key) {
    final next = _update(_canonicalize(key), _markCacheDirty);
    // The composite caches this edit just invalidated have no event of
    // their own (they self-validate by signature) — see [celPixelRevision].
    celPixelRevision.value += 1;
    return next;
  }

  BrushFrameDrawingState _markCacheDirty(BrushFrameDrawingState state) {
    final next = state.copyWith(
      inactivePreviewDirty: true,
      sourceRevision: state.sourceRevision + 1,
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
/// Offsets stay valid across incremental appends (appends never move
/// existing entry data); a compaction rewrites the file and re-issues
/// refs. A scratch ref is always at offset 0 — one cel, one file.
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
