import 'package:gpu_engine/gpu_engine.dart';

import '../models/bitmap_tile.dart';
import '../models/tile_roll.dart';
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
  /// none but the OS's where null. The pages made stay when it falls.
  int? get byteBudget => _byteBudget;
  set byteBudget(int? bytes) {
    _byteBudget = bytes;
    pool.makeNoPagePast(bytes ?? _unbounded);
  }

  int? _byteBudget;

  final Expando<GpuTile> _slots = Expando<GpuTile>('engineTileSlots');

  /// Every tile given a slot here — the walk a full pool lets slots go by,
  /// since [_slots] cannot be walked.
  final TileRoll _stored = TileRoll();

  late final Finalizer<GpuTile> _letGoWithTile = Finalizer<GpuTile>(_letGo);

  /// How many slots tiles have here — let go of with their tile or by a
  /// full pool. A probe.
  int get slotCount => _slotCount;
  int _slotCount = 0;

  void _letGo(GpuTile slot) {
    pool.release(slot);
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
  GpuTile? slotOf(BitmapTile tile) => _slots[tile];

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
    return [for (final tile in tiles) _slots[tile]!];
  }

  /// [tiles], none with a slot, each given one of [cel]'s: within the
  /// budget, else past it once what no hold has is let go.
  void _store(int cel, List<BitmapTile> tiles) {
    var stored = _put(cel, tiles);
    if (stored == tiles.length) {
      return;
    }
    _letGoUnheld();
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
      _slots[tile] = slots[at];
      _letGoWithTile.attach(tile, slots[at], detach: tile);
      _stored.hold(tile);
    }
    _slotCount += slots.length;
    return slots.length;
  }

  /// Lets go the slot of every tile no open hold has.
  void _letGoUnheld() {
    for (final tile in _stored.alive()) {
      final slot = _slots[tile];
      if (slot == null || _holds.any((hold) => hold._tiles.contains(tile))) {
        continue;
      }
      _slots[tile] = null;
      _letGoWithTile.detach(tile);
      _letGo(slot);
    }
  }
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
  /// its cel (`(layerId, frameId)`): what keeps a cel's tiles to pages of
  /// its own, which a pass binds few of (1a ④).
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
