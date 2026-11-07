import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart';

import '../models/bitmap_tile.dart';
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
/// has: while the CPU's tiles are the canonical ones (2단계) a tile let go
/// is stored again when asked, never read back (screen-on-the-engine c4,
/// 관제 2026-11-07). The tiles a hold has are then stored past
/// [byteBudget], as the pictures' budget lets go what nobody shows and
/// never what a paint did (`TilePictureBudget`): a budget refusing what a
/// call holds would be a failure with no fallback — a cel of 5800² inked
/// whole is past the 128 MB it gives a device of 2 GB.
///
/// The pages nobody holds are given back ([respondToMemoryPressure],
/// [byteBudget] falling under them) — the slots of tiles collected let go
/// first, their finalizers' messages or not (pool-pages-given-back): a
/// closed project's tiles are collected with it, and the give-back its
/// collection brings (`DrawingEngines.giveBackOnceCollected`) may land
/// before them.
///
/// One an isolate, as the engine is ([appGpuEngine]): a worker that asked
/// would open its own (ⓗ — no law says otherwise).
// ⏳Tests alone ask till the screen does (screen-on-the-engine c6), and
// the ink box after it (2번 레인 커밋 3 — 관제 2026-11-08 01:12).
class EngineTileLedger {
  /// A ledger of a pool of its own on [engine], making no page past
  /// [byteBudget] but for the tiles a call holds — none but the OS's where
  /// null.
  EngineTileLedger(GpuEngine engine, {int? byteBudget})
    : pool = GpuPool(engine, byteBudget ?? _unbounded),
      _byteBudget = byteBudget;

  /// The app's, on its engine — opened the first time anything asks.
  static EngineTileLedger get instance => _instance ??= EngineTileLedger(
    appGpuEngine,
    byteBudget: _appByteBudget,
  );
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

  /// Lets [slot] go, once: its tile's finalizer and a walk that found the
  /// tile collected first both come to it.
  void _letGo(_Slot slot) {
    if (slot.out) {
      return;
    }
    slot.out = true;
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

  /// The slot [tile] has, or null — nothing is stored here. A probe: a
  /// call that runs over slots asks [held].
  GpuTile? slotOf(BitmapTile tile) => _slots[tile]?.at;

  /// The record of the slot [tile] has, or null — a probe of what holds a
  /// record once its slot goes, which a test reads off the heap.
  @visibleForTesting
  Object? recordOf(BitmapTile tile) => _slots[tile];

  List<GpuTile> _slotsOf(TileHold hold, Object cel, List<BitmapTile> tiles) {
    for (final tile in tiles) {
      if (tile.size != gpuTileSide) {
        throw StateError(
          'a tile of ${tile.size}² — the engine stores $gpuTileSide²',
        );
      }
    }
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
  /// budget, else past it once what no hold has is let go.
  void _store(int cel, List<BitmapTile> tiles) {
    var stored = _put(cel, tiles);
    if (stored == tiles.length) {
      return;
    }
    _letGoWhere((tile) => !_holds.any((hold) => hold._tiles.contains(tile)));
    pool.makeNoPagePast(_unbounded);
    try {
      stored += _put(cel, tiles.sublist(stored));
    } finally {
      pool.makeNoPagePast(_byteBudget ?? _unbounded);
    }
    // ⚠️No test reaches the throw: past the budget a store falls short only
    // where the OS's budget or the driver refuses a page, and no test lowers
    // either (rust/src/kernels/pool/mod.rs says why).
    if (stored < tiles.length) {
      throw StateError(
        'the device stores $stored of the ${tiles.length} tiles a call holds',
      );
    }
  }

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
  /// collected — and sweeps what is let go out of [_stored].
  void _letGoWhere(bool Function(BitmapTile? tile) goes) {
    _stored.removeWhere((slot) {
      final tile = slot.tile.target;
      if (!goes(tile)) {
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

/// A slot a tile has here, its tile held weakly: being stored must not keep
/// a tile alive.
final class _Slot {
  _Slot(BitmapTile tile, this.at) : tile = WeakReference(tile);

  final WeakReference<BitmapTile> tile;
  final GpuTile at;

  /// Let go already — by its tile's finalizer, a full pool or a give-back.
  bool out = false;
}

/// What a call of [EngineTileLedger.held] is handed: the slots asked for
/// through it stay till that call returns.
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
}
