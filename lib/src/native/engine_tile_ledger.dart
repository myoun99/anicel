import 'dart:async';
import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart' show ListExtensions;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart';

import '../models/bitmap_tile.dart';
import '../models/tile_coord.dart';
import 'app_gpu_engine.dart';

/// The engine's copy of each tile asked for — a slot of a pool of its own
/// ([pool]) — found FROM the tile object and let go WITH it, as the tile's
/// picture is (`BitmapTileImageCache`): a tile is immutable, so the object
/// is the key, and a tile of other bytes is another object, stored once
/// (캔버스 베이스 2026-11-08 00:27 ⓐ). `==` compares pixels and is not
/// asked: two tiles alike are two slots.
///
/// 🚨A TILE IS STORED INSIDE THE CALL THAT ASKS FOR ITS SLOT
/// ([TileHold.slotsOf]), not at the commit that made it (ⓑ, 브러시/렌더링
/// 01:10): a commit makes the tiles of surfaces nothing shows or scans — an
/// import, an undo brought back, a verb over every cel — and the first ask
/// after a commit stores only the tiles it made, the rest being the same
/// objects. The door a tile's picture comes through keeps the same law.
///
/// ⛔THE SLOTS A CALL IS HANDED STAY TILL IT RETURNS ([held], ⓓ). Only a
/// store the pool is full at lets slots go, and only the ones no open hold
/// has: a tile whose bytes are here is stored again when asked, never read
/// back (screen-on-the-engine c4, 관제 2026-11-07). The tiles a hold has
/// are then stored past [byteBudget], as the pictures' budget lets go what
/// nobody shows and never what a paint did (`TilePictureBudget`): a budget
/// refusing what a call holds would be a failure with no fallback — a cel
/// of 5800² inked whole is past the 128 MB it gives a device of 2 GB.
///
/// 🚨A TILE THE ENGINE ALONE HOLDS GIVES ITS SLOT ONLY ONCE ITS BYTES ARE
/// HERE ([BitmapTile.isOnlyOnEngine]), and a pool still full reads them
/// here to have it: the oldest no hold has, a read's batch at the least —
/// then, still short, makes a page past the budget the OS gives (Windows
/// only advises one; past it the process's video memory moves to system
/// memory, packages/gpu_engine/rust/src/platform/windows.rs). ↩️Till 11-10
/// such a slot never went and the OS's budget was final: at that line a
/// stroke's landing threw inside paint and the stroke was gone with no
/// word, and tiles read from a file were refused their slots — neither of
/// which master did, its slots all copies of bytes in RAM (measured by
/// 브러시/렌더링 11-10 on a line lowered in a test, card
/// gpu-canonical-store). The 11-07 law — 「Full → 셀을 식혀 칸을 놓는다」 —
/// stood in the pool's notes and nowhere in the code. 🔢"Oldest" is stored
/// longest ago, not shown longest ago — 브러시/렌더링's pick, to measure.
/// Only a driver refusing a page fails now.
///
/// 🚨A TILE THE ENGINE ALONE HOLDS IS COPIED HERE ONCE THE HAND RESTS
/// ([copyHereABatch]), AND TILL THEN KEEPS THE TILE IT LANDED ON
/// ([_Slot.under]) — 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에
/// 사본을 두고 앱을 유지한다」. A device the driver takes away (a reset, an
/// update, a wake from sleep) takes every tile on it. A tile whose copy is
/// here loses nothing; one whose copy had not come reads as the picture it
/// landed on ([readInto]) — the last strokes on that tile are gone, the
/// picture they were laid on is not, and a save after it has every tile to
/// read. ↩️Till then such a tile had no bytes anywhere once its device
/// went: every read of it was refused, a save among them, and what could
/// be kept of the session was the last save.
///
/// The pages nobody holds are given back ([respondToMemoryPressure],
/// [byteBudget] falling under them) — the slots of tiles collected let go
/// first, their finalizers' messages or not (pool-pages-given-back): a
/// closed project's tiles are collected with it, and the give-back its
/// collection brings (`DrawingEngines.giveBackOnceCollected`) may land
/// before them.
///
/// The main isolate's alone ([instance]): a worker that asked would open an
/// engine of its own and read its tiles there — stored over from the CPU's
/// bytes today, and nothing at all once the engine's are the only ones
/// (저장's review of the flip lane, 11-09; ⓗ had let a worker open its own).
// ⏳The screen asks after its view is swapped (screen-on-the-engine c6).
class EngineTileLedger implements TilePixelsOnEngine {
  /// A ledger of a pool of its own on [engine], making no page past
  /// [byteBudget] but for the tiles a call holds — none but the OS's where
  /// null.
  EngineTileLedger(GpuEngine engine, {int? byteBudget})
    : _engine = engine,
      pool = GpuPool(engine, byteBudget ?? _unbounded),
      _byteBudget = byteBudget;

  /// The app's, on its engine — opened the first time anything asks.
  ///
  /// Refused on a worker, by name ([TileLedgerAskedOnAWorker]).
  static EngineTileLedger get instance {
    if (!appGpuEngineIsHere) {
      throw TileLedgerAskedOnAWorker();
    }
    return _instance ??= EngineTileLedger(
      appGpuEngine,
      byteBudget: _appByteBudget,
    );
  }

  static EngineTileLedger? _instance;

  /// The app's, where anything has opened it — none for a warning to open.
  static EngineTileLedger? get opened => _instance;

  /// The budget of the app's ledger: the tile pictures' line
  /// (`CacheBudgetLine.tileImages`), which the session gives both — before
  /// the ledger is opened too. Null till it does: none but the OS's.
  static int? get appByteBudget => _appByteBudget;
  static set appByteBudget(int? bytes) {
    _appByteBudget = bytes;
    _instance?.byteBudget = bytes;
  }

  static int? _appByteBudget;

  /// The bytes of the pages the app's ledger has made — none before
  /// anything asks it — for the memory census.
  static int get appPoolBytes => _instance?.pool.bytes ?? 0;

  /// The most a pool is told it may make: past any device.
  static const int _unbounded = 0x7fffffffffffffff;

  /// The pool the slots are of — what a plan over them runs on.
  final GpuPool pool;
final GpuEngine _engine;

  /// The bytes past which no page is made but for the tiles a call holds;
  /// none but the OS's where null. Falling under the pages made, it gives
  /// back those nobody holds till they keep within it.
  int? get byteBudget => _byteBudget;
  set byteBudget(int? bytes) {
    _byteBudget = bytes;
    pool.makeNoPagePast(bytes ?? _unbounded);
    _giveBackPast(bytes ?? _unbounded);
  }

  int? _byteBudget;

  /// Test seam: keeps the pool to [bytes] in place of the budget the OS
  /// gives — a device at its line, which no test fills a device to reach;
  /// the OS's again where null.
  @visibleForTesting
  void debugKeepToOsBudget(int? bytes) {
    _osBudgetInstead = bytes;
    pool.keepToInsteadOfTheOs(bytes);
  }

  int? _osBudgetInstead;

  /// The OS says memory is tight, or a closed project was collected: every
  /// page nobody holds goes back — what only makes the next store cheaper.
  void respondToMemoryPressure() => _giveBackPast(0);

  void _giveBackPast(int bytes) {
    _letGoWhere((tile) => tile == null);
    pool.giveBackPast(bytes);
  }

  final Expando<_Slot> _slots = Expando<_Slot>('engineTileSlots');

  /// Every slot handed out here and not yet swept — the walk a full pool
  /// and a give-back let slots go by, since [_slots] cannot be walked.
  final List<_Slot> _stored = [];

  late final Finalizer<_Slot> _letGoWithTile = Finalizer<_Slot>(_letGo);

  /// How many slots tiles have here — let go of with their tile or by a
  /// full pool. A probe.
  int get slotCount => _slotCount;
  int _slotCount = 0;

  /// How many slots [retire] has let go that [_stored] still lists.
  int _retired = 0;

  /// Retired slots [_stored] may list before they are swept out.
  static const int _retiredSwept = 4096;

  /// Lets [tile]'s slot go now, not with the tile: a tile its maker knows
  /// nothing reads again — the result a stroke showed, made anew at the next
  /// frame. Asked for pixels after this, the tile throws. Its collection
  /// would be seconds away, and a stroke's slots a frame's worth each.
  void retire(BitmapTile tile) {
    final slot = _slots[tile];
    if (slot == null) {
      return;
    }
    _slots[tile] = null;
    _letGoWithTile.detach(slot);
    _letGo(slot);
    _retired += 1;
    if (_retired > _retiredSwept) {
      _stored.removeWhere((slot) => slot.out);
      _retired = 0;
    }
  }

  /// The tiles the engine made that were read back: what a landing must not
  /// wait for.
  @visibleForTesting
  int debugTileReads = 0;

  @override
  void readInto(BitmapTile tile, Pointer<Uint8> into) {
    debugTileReads += 1;
    final slot = _slots[tile];
    if (slot == null) {
      throw StateError('a tile the engine made was read after it was let go');
    }
    if (!_reads(() => pool.read([slot.at], into))) {
      _layThePictureUnder(tile, slot, into);
    }
    // Its bytes are here: the tile it landed on is its to keep no longer.
    slot.under = null;
  }

  /// Whether [read] reads what it asks of the device: not where the device
  /// is gone ([GpuEngine.isGone]), the only copy of what was asked with it
  /// — a tile asked then reads as the picture it landed on
  /// ([_layThePictureUnder]). What else the engine refuses is thrown on.
  ///
  /// ⚠️ASKED OF THE DEVICE EVEN ONCE IT IS GONE, and told by its refusal:
  /// a device goes when its driver says, between any two lines here, so
  /// the refusal is the one place that hears it (the engine refuses every
  /// wait of a device that is gone — rust/src/device.rs `wait_within`).
  bool _reads(void Function() read) {
    try {
      read();
      return true;
    } on GpuRefused {
      if (!_engine.isGone) {
        rethrow;
      }
      return false;
    }
  }

  /// Lays in [into], [tile]'s bytes, the picture it landed on
  /// ([_Slot.under]) — nothing, where it landed on no tile — in place of
  /// its own, which went with the device.
  ///
  /// 🚨THE ONE WAY A TILE'S PIXELS ARE NOT THE ONES ITS MAKER MADE, so what
  /// the tile remembers of them is forgotten ([BitmapTile.forgetInk]).
  /// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에 사본을 두고 앱을
  /// 유지한다」 — what is lost with a device is what landed since the last
  /// copy came here ([copyHereABatch]), tile by tile; never the picture it
  /// landed on.
  void _layThePictureUnder(BitmapTile tile, _Slot slot, Pointer<Uint8> into) {
    final bytes = into.asTypedList(gpuTileBytes);
    final under = slot.under;
    if (under == null) {
      bytes.fillRange(0, gpuTileBytes, 0);
    } else {
      under.readPixels((_, view) => bytes.setAll(0, view));
    }
    tile.forgetInk();
  }

  /// A tile of the slot [at], which it now holds: the only copy of its
  /// pixels till they are read here ([BitmapTile.isOnlyOnEngine]), so till
  /// then nothing but its collection or [retire] lets it go — and till then
  /// it keeps [under], the tile it landed on ([_Slot.under]).
  BitmapTile _adopted(GpuTile at, {bool? hasInk, BitmapTile? under}) {
    final tile = BitmapTile.onEngine(
      size: gpuTileSide,
      on: this,
      hasInk: hasInk,
    );
    final slot = _Slot(tile, at)..under = under;
    _slots[tile] = slot;
    _letGoWithTile.attach(tile, slot, detach: slot);
    _stored.add(slot);
    _slotCount += 1;
    return tile;
  }

  /// Test seam: [tile]'s pixels as a tile the engine alone holds, as a
  /// landing leaves one.
  @visibleForTesting
  BitmapTile debugOnEngine(BitmapTile tile) => _adopted(
    tile.readPixels(
      (pointer, _) =>
          pool.store(_cels.putIfAbsent(landedCel, pool.cel), [pointer]).single,
    ),
  );

  /// The pages what lands takes: every stroke's and stamp's result, a few
  /// pages between them, whatever cels they land on.
  static final Object landedCel = Object();

  /// What [by] makes of the tiles [asks] — `GpuStroke.land`,
  /// `GpuStampLanding.land` —, each result a tile of its own, on [cel]'s
  /// pages; [compared], [by]'s, says the results' ink is known. A full pool
  /// has room made as [_store]'s is ([_shortAsRoomIsMade]): what is on the
  /// way to the screen has no fallback.
  List<LandedTile> land(
    Object cel,
    List<TileAsk> asks, {
    required LandedBy by,
    bool compared = false,
  }) => held((hold) {
    final under = hold.slotsOfThose(cel, [
      for (final ask in asks) ask.under,
    ]);
    final asked = <GpuTileAsk>[
      for (final (at, ask) in asks.indexed)
        (column: ask.column, row: ask.row, under: under[at]),
    ];
    List<GpuLanded> landOf(List<GpuTileAsk> asked) =>
        by(pool, _cels.putIfAbsent(cel, pool.cel), asked);
    final landed = landOf(asked);
    if (landed.length < asked.length) {
      final short = _shortAsRoomIsMade(() {
        landed.addAll(landOf(asked.sublist(landed.length)));
        return asked.length - landed.length;
      });
      if (short > 0) {
        throw TileRoomRefused(
          'the device lands ${landed.length} of the ${asked.length} tiles '
          'it was asked for',
        );
      }
    }
    _copyHereOnceTheHandRests();
    return [
      for (final (at, (:change, :tile)) in landed.indexed)
        (
          change: change,
          tile: tile == null
              ? null
              : _adopted(
                  tile,
                  hasInk: compared ? true : null,
                  under: asks[at].under,
                ),
        ),
    ];
  });

  /// Lets [slot] go, once: its tile's finalizer and a walk that found the
  /// tile collected first both come to it.
  void _letGo(_Slot slot) {
    if (slot.out) {
      return;
    }
    slot.out = true;
    slot.under = null;
    pool.release(slot.at);
    _slotCount -= 1;
  }

  /// The pool's cel of each cel asked for, by the name the caller gives it.
  final Map<Object, int> _cels = {};

  final List<TileHold> _holds = [];

  /// [use]'s answer — the slots it is handed through [TileHold.slotsOf]
  /// staying till it returns, whatever is asked meanwhile, a hold inside
  /// this one's too.
  T held<T>(T Function(TileHold hold) use) {
    final hold = TileHold._(this);
    _holds.add(hold);
    try {
      return use(hold);
    } finally {
      hold._open = false;
      _holds.remove(hold);
    }
  }

  /// [tiles]' bytes in [into] — [gpuTileBytes] each, in order: what a save,
  /// a cel cooled and an undo record parked read of the tiles (flip lane ⓓ).
  /// The engine's are read back, which waits for the GPU, on pages of
  /// [cel]'s; the rest give the bytes they hold.
  ///
  /// 🚨A TILE WHOSE BYTES ARE HERE GOES NOWHERE NEAR THE POOL. ↩️They were
  /// stored and read straight back while the CPU's tiles were the canonical
  /// ones (flip lane ⓓ, till ⓒ): a park, which runs when memory is tight,
  /// took slots to read what it held, and a full pool threw on the way to
  /// the user's file (저장's review of the lane, 11-10). A tile the engine
  /// alone holds has its slot, so a read stores nothing and that throw has
  /// no way here; one whose bytes are here gives those, as a tile of the
  /// CPU's does.
  void read(Object cel, List<BitmapTile> tiles, Pointer<Uint8> into) {
    _refuseOtherGrids(tiles);
    final asked = [
      for (final tile in tiles)
        if (tile.isOnlyOnEngine) tile,
    ];
    if (asked.isNotEmpty) {
      final read = held((hold) {
        debugBeforeRead?.call(asked);
        return _reads(() => pool.read(hold.slotsOf(cel, asked), into));
      });
      if (!read) {
        // The device is gone: each gives the bytes it comes to hold, as a
        // tile whose bytes are here — the picture it landed on ([readInto]).
        asked.clear();
      }
    }
    if (asked.length < tiles.length) {
      _laidInPlace(
        tiles,
        asked,
        into.asTypedList(tiles.length * gpuTileBytes),
      );
    }
  }

  /// [tiles] each at its place in [block], the first places of which hold
  /// the bytes of [readBack] — those of [tiles] read from the engine, in
  /// their order — side by side: from the last tile back, so where a tile
  /// goes is past every tile still to move.
  void _laidInPlace(
    List<BitmapTile> tiles,
    List<BitmapTile> readBack,
    Uint8List block,
  ) {
    var next = readBack.length;
    for (var at = tiles.length - 1; at >= 0; at--) {
      final tile = tiles[at];
      final start = at * gpuTileBytes;
      final end = start + gpuTileBytes;
      if (next > 0 && identical(tile, readBack[next - 1])) {
        next -= 1;
        block.setRange(start, end, block, next * gpuTileBytes);
      } else {
        tile.readPixels((_, view) => block.setRange(start, end, view));
      }
    }
  }

  /// Test seam: told the tiles each [read] asks the engine for, before it
  /// asks — how a test counts them, or has one refused as a device refuses
  /// it.
  @visibleForTesting
  static void Function(List<BitmapTile> tiles)? debugBeforeRead;

  /// Each of [tiles]' bytes read back ([read]) and handed to [use] in order
  /// — a view good only inside [use] —, [readBatch] tiles a read, through
  /// one block [blocks] gives.
  ///
  /// 🚨A READ ASKS FOR NO MORE THAN ONE BATCH: a cel is parked when memory
  /// is tight (`encodeCelEntryFromSurface`), so its bytes go a batch at a
  /// time through one block, never the cel whole. 🔢64 tiles, 4 MiB here
  /// and as much on the GPU's side, a cel of 2116 tiles (5800² inked
  /// whole) in 34 maps — 브러시/렌더링's pick (flip lane ⓓ), to measure.
  void readEach(
    Object cel,
    List<BitmapTile> tiles,
    void Function(Uint8List bytes) use, {
    Allocator blocks = malloc,
  }) {
    // No block of none: C may answer a malloc of 0 with null, which
    // package:ffi throws for.
    if (tiles.isEmpty) {
      return;
    }
    final into = blocks<Uint8>(
      math.min(tiles.length, readBatch) * gpuTileBytes,
    );
    try {
      for (final batch in tiles.slices(readBatch)) {
        read(cel, batch, into);
        final bytes = into.asTypedList(batch.length * gpuTileBytes);
        for (var at = 0; at < batch.length; at++) {
          use(
            Uint8List.sublistView(
              bytes,
              at * gpuTileBytes,
              (at + 1) * gpuTileBytes,
            ),
          );
        }
      }
    } finally {
      blocks.free(into);
    }
  }

  /// What the engine finds of each of [tiles]' ink, told to the tile
  /// ([BitmapTile.rememberInkBounds]) — the tiles laid side by side as a
  /// cel of those tiles alone, as the scan takes them. Waits for the GPU.
  void rememberInk(Object cel, List<BitmapTile> tiles) => held((hold) {
    final slots = hold.slotsOf(cel, tiles);
    for (final walked in _ink.run(pool, 0, 0, tiles.length, 1, slots)) {
      final box = walked.box;
      tiles[walked.column].rememberInkBounds(
        box == null
            ? null
            : (
                left: box.left,
                top: box.top,
                rightExclusive: box.right,
                bottomExclusive: box.bottom,
              ),
      );
    }
  });

  late final GpuInk _ink = GpuInk(_engine);

  /// The tiles a read of [readEach] reads at once.
  static const int readBatch = 64;

  /// The slot [tile] has, or null — nothing is stored here. A probe: a
  /// call that runs over slots asks [held].
  GpuTile? slotOf(BitmapTile tile) => _slots[tile]?.at;

  /// The record of the slot [tile] has, or null — a probe of what holds a
  /// record once its slot goes, which a test reads off the heap.
  @visibleForTesting
  Object? recordOf(BitmapTile tile) => _slots[tile];

  static void _refuseOtherGrids(List<BitmapTile> tiles) {
    for (final tile in tiles) {
      if (tile.size != gpuTileSide) {
        throw StateError(
          'a tile of ${tile.size}² — the engine stores $gpuTileSide²',
        );
      }
    }
  }

  List<GpuTile> _slotsOf(TileHold hold, Object cel, List<BitmapTile> tiles) {
    _refuseOtherGrids(tiles);
    hold._tiles.addAll(tiles);
    final asked = Set<BitmapTile>.identity();
    final missing = [
      for (final tile in tiles)
        if (_slots[tile] == null && asked.add(tile)) tile,
    ];
    if (missing.isNotEmpty) {
      _store(_cels.putIfAbsent(cel, pool.cel), missing);
    }
    return [for (final tile in tiles) _slots[tile]!.at];
  }

  /// [tiles], none with a slot, each given one of [cel]'s: within the
  /// budget, else as room is made ([_shortAsRoomIsMade]).
  void _store(int cel, List<BitmapTile> tiles) {
    var stored = _put(cel, tiles);
    if (stored == tiles.length) {
      return;
    }
    final short = _shortAsRoomIsMade(() {
      stored += _put(cel, tiles.sublist(stored));
      return tiles.length - stored;
    });
    // ⚠️No test reaches the throw: past both budgets a store falls short
    // only where the driver refuses a page, which no test has one do.
    if (short > 0) {
      throw TileRoomRefused(
        'the device stores $stored of the ${tiles.length} tiles a call holds',
      );
    }
  }

  /// How many tiles are still without a slot once room is made for them:
  /// [placeRest] places what is left and answers how many still are, asked
  /// again after each step — the slots no hold has, of tiles whose bytes
  /// are here, let go and [byteBudget] lifted; the bytes of tiles the engine
  /// alone holds moved here ([_moveBytesHere]); a page past the OS's budget.
  int _shortAsRoomIsMade(int Function() placeRest) {
    _letGoWhere(_noHoldHas);
    pool.makeNoPagePast(_unbounded);
    try {
      var short = placeRest();
      if (short > 0 && _moveBytesHere(short)) {
        short = placeRest();
      }
      if (short > 0) {
        pool.keepToInsteadOfTheOs(_unbounded);
        try {
          short = placeRest();
        } finally {
          pool.keepToInsteadOfTheOs(_osBudgetInstead);
        }
      }
      return short;
    } finally {
      pool.makeNoPagePast(_byteBudget ?? _unbounded);
    }
  }

  /// Moves here the bytes of the oldest tiles the engine alone holds and no
  /// hold has — [short] of them, a read's batch at the least: one wait of
  /// the GPU's frees as many slots as it reads — and lets their slots go;
  /// whether there was one.
  bool _moveBytesHere(int short) {
    final going = _onlyOnEngine(math.max(short, readBatch), _noHoldHas);
    if (going.isEmpty) {
      return false;
    }
    _copyHere(going);
    _letGoWhere(_noHoldHas);
    return true;
  }

  /// The oldest tiles the engine alone holds that [of] names, [most] of
  /// them at the most.
  List<BitmapTile> _onlyOnEngine(int most, bool Function(BitmapTile) of) {
    final tiles = <BitmapTile>[];
    for (final slot in _stored) {
      if (tiles.length == most) {
        break;
      }
      final tile = slot.out ? null : slot.tile.target;
      if (tile != null && tile.isOnlyOnEngine && of(tile)) {
        tiles.add(tile);
      }
    }
    return tiles;
  }

  /// Reads back the bytes of [tiles], each the engine's alone, and has each
  /// keep its own ([BitmapTile.keepBytesHere]) — its slot staying, and the
  /// tile it landed on its to keep no longer ([_Slot.under]).
  void _copyHere(List<BitmapTile> tiles) {
    var next = 0;
    readEach(landedCel, tiles, (bytes) {
      final tile = tiles[next++];
      // Not one that came to hold bytes inside the read: the picture it
      // landed on, its device gone ([readInto]).
      if (tile.isOnlyOnEngine) {
        tile.keepBytesHere(bytes);
        _slots[tile]?.under = null;
      }
    });
  }

  /// Copies here the bytes of the oldest tiles the engine alone holds —
  /// [copyBatch] of them, one wait of the GPU's —, their slots kept;
  /// whether there may be more.
  ///
  /// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에 사본을 두고 앱을
  /// 유지한다」 — a device the driver takes away takes every tile on it. One
  /// whose copy is here is stored again from it on the next device; one
  /// whose copy had not come reads as the picture it landed on
  /// ([_layThePictureUnder]).
  bool copyHereABatch() {
    final tiles = _onlyOnEngine(copyBatch, (_) => true);
    _copyHere(tiles);
    return tiles.length == copyBatch;
  }

  /// The tiles a turn of the copies at rest copies ([copyHereABatch]): a
  /// press that comes as they go waits for the turn under way, and no
  /// more. 🔢브러시/렌더링's pick. 🔬Main PC (RTX 4080) beside a busy test
  /// line, 2026-11-11: a read of 64 tiles is 5.6–9.6 ms (0.4–1.4 ms of one,
  /// 0.9–3.1 ms of 8), and their bytes kept as 64 tiles as much again
  /// (5.7–8.1 ms) — 15–29 ms a batch of 64, two frames of a hand that had
  /// just come back. ⏳To measure on the Surface Pro 11 (관제 2026-11-11:
  /// past a frame there, the read is taken on the engine's thread).
  static const int copyBatch = 8;

  /// How long after the last landing the hand is taken to rest, and the
  /// copies begin ([copyHereABatch]). 🔢브러시/렌더링's pick, to measure: a
  /// landing comes at every frame of a stroke and at each pen's lift, and
  /// a copy waits for the GPU.
  static const Duration rest = Duration(milliseconds: 500);

  /// Test seam: whether a landing asks for copies once the hand rests. A
  /// widget test's clock ends no timer of its own accord, and a test ends
  /// red with one pending (`flutter_test_config.dart`); the pins of the
  /// copies ask for them.
  @visibleForTesting
  static bool debugCopiesAtRest = true;

  Timer? _atRest;

  /// Copies what the engine alone holds here once the hand has rested
  /// ([rest]) — a batch a turn of this isolate, so a press between two is
  /// heard — from the last landing: one more puts the copies off.
  void _copyHereOnceTheHandRests() {
    if (!debugCopiesAtRest) {
      return;
    }
    _atRest?.cancel();
    _atRest = Timer(rest, _copyHereAtRest);
  }

  void _copyHereAtRest() {
    _atRest = copyHereABatch() ? Timer(Duration.zero, _copyHereAtRest) : null;
  }

  bool _noHoldHas(BitmapTile? tile) =>
      !_holds.any((hold) => hold._tiles.contains(tile));

  /// Stores [tiles] in one store and gives each landed its slot; how many
  /// landed, the first of them.
  int _put(int cel, List<BitmapTile> tiles) {
    // ⚠️Each pointer outlives the read it comes from, as `readPixels` lets
    // one where the tile stays reachable while it is used: the loop below
    // reads [tiles] after the store, and the callers read it after this.
    final slots = pool.store(cel, [
      for (final tile in tiles) tile.readPixels((pointer, _) => pointer),
    ]);
    for (var at = 0; at < slots.length; at++) {
      final tile = tiles[at];
      final slot = _Slot(tile, slots[at]);
      _slots[tile] = slot;
      _letGoWithTile.attach(tile, slot, detach: slot);
      _stored.add(slot);
    }
    _slotCount += slots.length;
    return slots.length;
  }

  /// Lets go the slot of every tile [goes] names — null for a tile
  /// collected — but one the engine alone holds, which has no bytes to be
  /// stored again from, and sweeps what is let go out of [_stored].
  void _letGoWhere(bool Function(BitmapTile? tile) goes) {
    _stored.removeWhere((slot) {
      if (slot.out) {
        return true;
      }
      final tile = slot.tile.target;
      if ((tile != null && tile.isOnlyOnEngine) || !goes(tile)) {
        return false;
      }
      if (tile != null) {
        _slots[tile] = null;
        // The finalizer holds a record strongly and its tile weakly: left
        // attached, a tile that lives on would keep one record each time a
        // full pool let it go and it was stored again. No pixel tells —
        // the slot goes once whichever comes to it ([_letGo]) — so the
        // heap does (mutant D10, 관제 11-08 07:11).
        _letGoWithTile.detach(slot);
      }
      _letGo(slot);
      return true;
    });
  }
}

/// A tile a landing was asked for: its [column] and [row], and the cel's
/// tile there, if it has one.
typedef TileAsk = ({int column, int row, BitmapTile? under});

/// What a landing made of a tile asked: what it is beside the tile under
/// it, and the tile, where one landed.
typedef LandedTile = ({GpuChange change, BitmapTile? tile});

/// What makes a landing of the tiles asked, on a cel of a pool.
typedef LandedBy =
    List<GpuLanded> Function(GpuPool pool, int cel, List<GpuTileAsk> asked);

/// A slot a tile has here, its tile held weakly: being stored must not keep
/// a tile alive.
final class _Slot {
  _Slot(BitmapTile tile, this.at) : tile = WeakReference(tile);

  final WeakReference<BitmapTile> tile;
  final GpuTile at;

  /// The tile [tile] landed on — null where it landed on none, or was not
  /// landed — kept while the engine holds the only copy of [tile]'s pixels:
  /// what [tile] reads as where a device goes with them
  /// (`EngineTileLedger._layThePictureUnder`). Let go once [tile]'s bytes
  /// are here, and with the slot.
  BitmapTile? under;

  /// Let go already — by its tile's finalizer, a full pool or a give-back.
  bool out = false;
}

/// What a call of [EngineTileLedger.held] is handed: the slots asked for
/// through it stay till that call returns.
/// What [TileHold.gridOf] answers.
typedef TileGrid = ({
  int x0,
  int y0,
  int columns,
  int rows,
  List<GpuTile?> tiles,
});

final class TileHold {
  TileHold._(this._ledger);

  final EngineTileLedger _ledger;

  /// Every tile asked for through this hold — by identity, as `==` reads
  /// every pixel.
  final Set<BitmapTile> _tiles = Set<BitmapTile>.identity();

  bool _open = true;

  /// The slot of each of [tiles], in order — the ones without one stored
  /// now, together, on pages of [cel]'s. [cel] is the name a painter gives
  /// its cel (`BrushFrameKey.cel`, and `BrushFrameKey.noCel` for a surface
  /// that is nobody's): what keeps a cel's tiles to pages of its own, which
  /// a pass binds few of (1a ④).
  ///
  /// Throws, nothing stored, for a tile of a side the engine does not
  /// store (ⓖ — no fallback), and where the device stores no more.
  List<GpuTile> slotsOf(Object cel, List<BitmapTile> tiles) {
    if (!_open) {
      throw StateError('a hold is asked inside the call it was handed to');
    }
    return _ledger._slotsOf(this, cel, tiles);
  }

  /// The box [tiles]' coordinates span and, row by row, the slot of each
  /// — null at a place with none: a cel as a kernel reads one. [tiles] is
  /// not empty.
  TileGrid gridOf(Object cel, Map<TileCoord, BitmapTile> tiles) {
    final coords = tiles.keys;
    final x0 = coords.map((coord) => coord.x).reduce(math.min);
    final y0 = coords.map((coord) => coord.y).reduce(math.min);
    final columns = coords.map((coord) => coord.x).reduce(math.max) - x0 + 1;
    final rows = coords.map((coord) => coord.y).reduce(math.max) - y0 + 1;
    final slots = slotsOf(cel, tiles.values.toList());
    final grid = List<GpuTile?>.filled(columns * rows, null);
    for (final (at, coord) in coords.indexed) {
      grid[(coord.y - y0) * columns + coord.x - x0] = slots[at];
    }
    return (x0: x0, y0: y0, columns: columns, rows: rows, tiles: grid);
  }

  /// [slotsOf] for a list with gaps: null where [tiles] has none.
  List<GpuTile?> slotsOfThose(Object cel, List<BitmapTile?> tiles) {
    final slots = slotsOf(cel, tiles.nonNulls.toList());
    var next = 0;
    return [
      for (final tile in tiles)
        if (tile == null) null else slots[next++],
    ];
  }
}

/// The device had no room for tiles asked of it, room made every way the
/// ledger makes it ([EngineTileLedger._shortAsRoomIsMade]): the stroke, the
/// paste or the confirm that asked is not landed. A cause of its own among
/// what the engine refuses, told as one (`EngineRefusals`,
/// 🗣️gpu-canonical-store-Q14, 유저 2026-11-11: 「같은 실행에서 같은
/// 까닭으로는 다시 띄우지 않는다」).
final class TileRoomRefused extends GpuRefused {
  TileRoomRefused(super.message);
}

/// A worker asked for the app's ledger ([EngineTileLedger.instance]): the
/// engine and the tiles' slots are the main isolate's.
final class TileLedgerAskedOnAWorker extends StateError {
  TileLedgerAskedOnAWorker()
    : super('the tile ledger is the main isolate\'s; a worker asked for it');
}
