import 'dart:async';
import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart' show ListExtensions;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart';

import '../core/zero_bytes.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/tile_coord.dart';
import '../services/cel_shells.dart';
import 'app_gpu_engine.dart';

/// The engine's copy of each tile asked for — a slot of a pool of its own
/// ([pool]) — found FROM the tile object and let go WITH it, as the tile's
/// picture is (`BitmapTileImageCache`): a tile is immutable, so the object
/// is the key, and a tile of other bytes is another object, stored once
/// (캔버스 베이스 2026-11-08 00:27 ⓐ). `==` compares pixels and is not
/// asked: two tiles alike are two slots.
///
/// 🚨BUT THE TILES OF ONE COLOUR ARE ONE SLOT (card
/// uniform-tiles-take-a-pool-slot-each, 관제 2026-11-16 「① 네가 먼저」):
/// a tile of one colour holds its colour's block, one object for every
/// tile of the colour alive, and the block is their key
/// ([BitmapTile.pixelsKey]) — what a hold holds, what a full pool lets go
/// once no hold has it, and what lets the slot go as it is collected, with
/// the last tile of the colour. No pixel is compared for it, still: two
/// tiles alike of bytes of their own are two slots. 🔬Why: a user's file
/// kept 30,536 tiles of one clear word and 8,753 of one opaque colour
/// (`BitmapTile`'s note), and each was a slot of its own and a copy up.
///
/// 🚨A TILE IS STORED INSIDE THE CALL THAT ASKS FOR ITS SLOT
/// ([TileHold.slotsOf]), not at the commit that made it (ⓑ, 브러시/렌더링
/// 01:10): a commit makes the tiles of surfaces nothing shows or scans — an
/// import, an undo brought back, a verb over every cel — and the first ask
/// after a commit stores only the tiles it made, the rest being the same
/// objects. The door a tile's picture comes through keeps the same law.
///
/// ⛔THE SLOTS A CALL IS HANDED STAY TILL IT RETURNS ([held], ⓓ). Only a
/// store the pool is full at lets slots go, only the ones no open hold
/// has, and the ones stored longest ago first — as many as it is short, a
/// page's worth at the least ([_shortAsRoomIsMade]): a tile whose bytes
/// are here is stored again when asked, never read back
/// (screen-on-the-engine c4, 관제 2026-11-07). The tiles a hold has are
/// then stored past [byteBudget], as the pictures' budget lets go what
/// nobody shows and never what a paint did (`TilePictureBudget`): a
/// budget refusing what a call holds would be a failure with no fallback
/// — a cel of 5800² inked whole is past the 128 MB it gives a device of
/// 2 GB.
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
/// 🚨AND ONE WHOSE LANDING SAID HOW IT IS MADE READS AS ITSELF, MADE AGAIN
/// ([LandsAgain], [_Slot.made]) — 🗣️유저 2026-11-19
/// (cel-originals-are-held-twice-in-ram-and-on-the-gpu-Q2): 「픽셀 대신 「한
/// 일의 기록」을 들고, 잃으면 다시 그린다」. Where the app stands on another
/// engine by then, the landing is made there once more, over the tile it
/// landed on — itself made again the same way, where its own copy had not
/// come — and the last strokes are not gone. Kept as long as the tile it
/// landed on is: till the copy comes. ⏳The copies still come
/// ([copyHereABatch]): what a landing with no such word has, and all there
/// is where no other engine opens.
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
class EngineTileLedger implements TilePixelsOnEngine, CelShells {
  /// A ledger of a pool of its own on [engine], making no page past
  /// [byteBudget] but for the tiles a call holds — none but the OS's where
  /// null —, a full pool letting go [roomBatch] slots at the least: a
  /// page's worth where null.
  EngineTileLedger(GpuEngine engine, {int? byteBudget, int? roomBatch})
    : _engine = engine,
      pool = GpuPool(engine, byteBudget ?? _unbounded),
      _byteBudget = byteBudget,
      _roomBatch = roomBatch ?? EngineTileLedger.roomBatch {
    pool.onUnwritten = _letGoUnwritten;
  }

  /// The app's, on its engine — opened the first time anything asks, and
  /// another on the next engine once the app lets this one go
  /// ([KeptOnTheAppsEngine]).
  ///
  /// Refused on a worker, by name ([TileLedgerAskedOnAWorker]).
  static EngineTileLedger get instance {
    if (!appGpuEngineIsHere) {
      throw TileLedgerAskedOnAWorker();
    }
    return _instance.of(
      () => EngineTileLedger(appGpuEngine, byteBudget: _appByteBudget),
    );
  }

  /// ⛔Let go with nothing freed: the ledger of an engine the app has let
  /// go is its tiles' still. Each reads through it once more — its own
  /// bytes where their copy came, else the picture it landed on
  /// ([_layThePictureUnder]) — which is how the next ledger, asked for a
  /// tile it never stored, comes by the bytes it stores ([_put]); and each
  /// lets its slot go there when it is collected.
  static final _instance = KeptOnTheAppsEngine<EngineTileLedger>();

  /// The app's, where anything has opened it — none for a warning to open.
  static EngineTileLedger? get opened => _instance.orNull;

  /// The budget of the app's ledger: the tile pictures' line
  /// (`CacheBudgetLine.tileImages`), which the session gives both — before
  /// the ledger is opened too. Null till it does: none but the OS's.
  static int? get appByteBudget => _appByteBudget;
  static set appByteBudget(int? bytes) {
    _appByteBudget = bytes;
    opened?.byteBudget = bytes;
  }

  static int? _appByteBudget;

  /// The bytes of the pages the app's ledger has made — none before
  /// anything asks it — for the memory census: the page its pool made ahead
  /// of the store that needs it among them (관제 2026-11-15,
  /// a-picture-lay-holds-the-raster-thread), which the pool's own `bytes`
  /// leaves to its budget.
  static int get appPoolBytes => switch (opened?.pool) {
    null => 0,
    final pool => pool.bytes + pool.aheadBytes,
  };

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
    _letGoWhere((key, _) => key == null);
    pool.giveBackPast(bytes);
  }

  /// The place of every key given a slot here ([_give]): a tile, or the
  /// block every tile of a colour holds ([BitmapTile.pixelsKey]).
  final Expando<_Place> _places = Expando<_Place>('engineTilePlaces');

  /// The slot [tile] has now, or null: never stored, or let go since — its
  /// colour's, for a tile of one colour.
  _Slot? _slotNow(BitmapTile tile) => _places[tile.pixelsKey]?.slot;

  /// Every slot handed out here and not yet swept, the one stored longest
  /// ago first — the walk a full pool and a give-back let slots go by,
  /// since [_places] cannot be walked.
  final List<_Slot> _stored = [];

  /// Lets a key's slot go with the key: handed its place once the
  /// collector finds the key — a tile, or a colour's block once the last
  /// tile of the colour is —, it lets go the slot that holds, none where a
  /// full pool came first. Attached once a key ([_give]), with no token to
  /// detach it by ([_Place]).
  late final Finalizer<_Place> _letGoWithKey = Finalizer<_Place>((place) {
    final slot = place.slot;
    if (slot != null) {
      _letGo(slot);
    }
  });

  /// How many slots tiles have here — let go of with their key or by a
  /// full pool: one for every tile of a colour. A probe.
  int get slotCount => _slotCount;
  int _slotCount = 0;

  /// How many slots [retire] has let go, and [shellOf] moved, that
  /// [_stored] still lists.
  int _retired = 0;

  /// Retired slots [_stored] may list before they are swept out.
  static const int _retiredSwept = 4096;

  /// Lets [tile]'s slot go now, not with the tile: a tile its maker knows
  /// nothing reads again — the result a stroke showed, made anew at the next
  /// frame. Asked for pixels after this, the tile throws. Its collection
  /// would be seconds away, and a stroke's slots a frame's worth each.
  ///
  /// ⛔A TILE OF ONE COLOUR LETS NOTHING GO: its slot is its colour's
  /// ([BitmapTile.pixelsKey]), which other tiles of the colour may be
  /// drawing from inside a call that holds them — one tile cannot say
  /// nothing reads the rest (uniform-tiles-take-a-pool-slot-each, 11-16).
  /// It goes with the colour, or by a full pool.
  void retire(BitmapTile tile) {
    final slot = _slotNow(tile);
    if (slot == null || !identical(tile.pixelsKey, tile)) {
      return;
    }
    _letGo(slot);
    _countedOut();
  }

  /// One more slot [_stored] lists that is out — all of them swept out once
  /// they are [_retiredSwept].
  void _countedOut() {
    _retired += 1;
    if (_retired > _retiredSwept) {
      _stored.removeWhere((slot) => slot.out);
      _retired = 0;
    }
  }

  /// 🚨A CEL A LOOK LETS GO KEEPS WHAT THE ENGINE HOLDS OF IT (card
  /// let-go-cels-keep-their-gpu-tiles, 유저 2026-11-16 03:10 on Q3: 「지금
  /// 착지하고, GPU 타일을 남기는 일을 바로 다음으로」): each tile of
  /// [surface] with bytes of its own and a slot here gives that slot to a
  /// tile of the same pixels that holds none here, a shell's — and the
  /// tile with the bytes goes with the look, its slot no longer its. 🔬What
  /// it was for: a ghost turned on read every cel from the file again and
  /// put every tile back on the engine once the walk let go of its cels
  /// (FNK_02 copy, main PC, 11-16).
  ///
  /// A tile of a colour, one with no slot here and one the engine made stay
  /// as they are: the first two hold their bytes already, and the last is
  /// a hot cel's, which keeps no shell. None where no tile is a shell's.
  ///
  /// A shell's slots go as freely as any whose bytes are here
  /// ([TilePixelsKeptBesides]): a tile whose slot went reads the cel's kept
  /// bytes again ([readAgain]) — once for every tile a turn reads so
  /// ([_KeptCel]) — as the cel's next thaw would. ⚠️A shell's tile weighs a
  /// tile's bytes ([BitmapTile.ownBytes]), as any the engine made does: the
  /// looks weigh what the engine keeps for them, as before.
  @override
  BitmapSurface? shellOf(
    BitmapSurface surface, {
    required BitmapSurface Function() readAgain,
  }) {
    if (surface.tileSize != gpuTileSide) {
      return null;
    }
    final kept = _KeptCel(readAgain);
    var shelled = 0;
    var already = 0;
    final tiles = <TileCoord, BitmapTile>{};
    for (final MapEntry(key: at, value: tile) in surface.tiles.entries) {
      final slot = _slotNow(tile);
      if (slot == null || !identical(tile.pixelsKey, tile)) {
        tiles[at] = tile;
      } else if (tile.isOnEngine) {
        tiles[at] = tile;
        already += 1;
      } else {
        tiles[at] = _shellOf(tile, slot, _ShellPixels(this, kept, at));
        shelled += 1;
      }
    }
    if (shelled == 0) {
      return already == 0 ? null : surface;
    }
    return surface.copyWith(tiles: tiles);
  }

  /// Whether every tile of [shell] the engine holds has its slot here: a
  /// full pool lets a shell's go, and a shell kept from the ledger of an
  /// engine the app let go has none here.
  @override
  bool isWhole(BitmapSurface shell) => shell.tiles.values.every(
    (tile) => !tile.isOnEngine || _slotNow(tile) != null,
  );

  /// A shell's tile of [tile]'s pixels, read through [pixels], given
  /// [slot] — [tile]'s till now, which has none from here on.
  BitmapTile _shellOf(BitmapTile tile, _Slot slot, _ShellPixels pixels) {
    final shell = BitmapTile.onEngine(
      size: tile.size,
      on: pixels,
      hasInk: tile.hasInk,
    );
    if (tile.inkBoundsKnown) {
      shell.rememberInkBounds(tile.inkBounds);
    }
    slot.out = true;
    slot.place.slot = null;
    _slotCount -= 1;
    _give(shell, slot.at);
    _countedOut();
    return shell;
  }

  /// Whether [tile]'s slot here read into [into] — not where it has none,
  /// or the device went with it.
  bool _readsItsSlot(BitmapTile tile, Pointer<Uint8> into) {
    final slot = _slotNow(tile);
    if (slot == null) {
      return false;
    }
    debugTileReads += 1;
    return _reads(() => pool.read([slot.at], into));
  }

  /// The tiles the engine made that were read back: what a landing must not
  /// wait for.
  @visibleForTesting
  int debugTileReads = 0;

  @override
  void readInto(BitmapTile tile, Pointer<Uint8> into) {
    debugTileReads += 1;
    final slot = _slotNow(tile);
    if (slot == null) {
      throw StateError('a tile the engine made was read after it was let go');
    }
    if (!_reads(() => pool.read([slot.at], into)) &&
        !_makesAgain(slot, into)) {
      _layThePictureUnder(tile, slot, into);
    }
    // Its bytes are here: the tile it landed on is its to keep no longer,
    // nor how it was made.
    slot.keepsNothing();
  }

  /// Whether [slot]'s tile, gone with the device, was made again in
  /// [into]: its landing once more ([_Slot.made]), over the tile it landed
  /// on, on the engine the app stands on now.
  ///
  /// Not where its landing said nothing of how it is made; nor while the
  /// app still stands on this ledger's engine ([opened]) — one device went
  /// within a minute of another (`EngineRefusals.openAnotherApart`), or no
  /// other opened —, where there is nothing to make it on; nor where the
  /// making is refused in its turn, that engine's device gone too. Each
  /// then reads as the picture it landed on ([_layThePictureUnder]).
  bool _makesAgain(_Slot slot, Pointer<Uint8> into) {
    final made = slot.made;
    if (made == null || identical(opened, this)) {
      return false;
    }
    final under = slot.under;
    try {
      final (:change, tile: again) = made.by.again([
        (column: made.column, row: made.row, under: under),
      ]).single;
      // The landing left the tile under it as it was: that tile's bytes.
      _layBytesOf(change == GpuChange.same ? under : again, into);
      return true;
    } on GpuRefused {
      return false;
    }
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
    _layBytesOf(slot.under, into);
    tile.forgetInk();
  }

  /// A tile of the slot [at], which it now holds: the only copy of its
  /// pixels till they are read here ([BitmapTile.isOnlyOnEngine]), so till
  /// then nothing but its collection or [retire] lets it go — and till then
  /// it keeps [under], the tile it landed on ([_Slot.under]), and [made],
  /// how its landing is made again ([_Slot.made]).
  BitmapTile _adopted(
    GpuTile at, {
    bool? hasInk,
    BitmapTile? under,
    _Made? made,
  }) {
    final tile = BitmapTile.onEngine(
      size: gpuTileSide,
      on: this,
      hasInk: hasInk,
    );
    _give(tile, at)
      ..under = under
      ..made = made;
    return tile;
  }

  /// Gives [tile] the slot [at], in its key's place — made, and the key's
  /// finalizer attached, where this is the first slot the key is given:
  /// every tile of [tile]'s colour has it, for a tile of one colour.
  _Slot _give(BitmapTile tile, GpuTile at) {
    final key = tile.pixelsKey;
    var place = _places[key];
    if (place == null) {
      place = _places[key] = _Place();
      _letGoWithKey.attach(key, place);
    }
    final slot = place.slot = _Slot(key, at, place);
    _stored.add(slot);
    _slotCount += 1;
    return slot;
  }

  /// Test seam: [tile]'s pixels as a tile the engine alone holds, as a
  /// landing leaves one.
  @visibleForTesting
  BitmapTile debugOnEngine(BitmapTile tile) => _adopted(
    pool.store(_cels.putIfAbsent(landedCel, pool.cel), [tile], _bytesOf).single,
  );

  /// Where [tile]'s bytes are, for a store that holds [tile] while they are
  /// read ([GpuPool.store]) — the one way a pointer outlives the read it
  /// comes from (BitmapTile.readPixels).
  static Pointer<Uint8> _bytesOf(BitmapTile tile) =>
      tile.readPixels((pointer, _) => pointer);

  /// The pages what lands takes: every stroke's and stamp's result, a few
  /// pages between them, whatever cels they land on.
  static final Object landedCel = Object();

  /// What [by] makes of the tiles [asks] — `GpuStroke.land`,
  /// `GpuStampLanding.land` —, each result a tile of its own, on [cel]'s
  /// pages; [compared], [by]'s, says the results' ink is known. A full pool
  /// has room made as [_store]'s is ([_shortAsRoomIsMade]): what is on the
  /// way to the screen has no fallback.
  ///
  /// [again] makes the same landing on another engine, where the caller
  /// can say how ([LandsAgain]): what each tile landed reads as should this
  /// engine's device go before the tile's bytes are here ([_makesAgain]).
  List<LandedTile> land(
    Object cel,
    List<TileAsk> asks, {
    required LandedBy by,
    bool compared = false,
    LandsAgain? again,
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
      final short = _shortAsRoomIsMade(asked.length - landed.length, () {
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
                  made: again == null
                      ? null
                      : (by: again, column: asks[at].column, row: asks[at].row),
                ),
        ),
    ];
  });

  /// Every tile of [rect] — a rectangle of tiles on the canvas's grid: its
  /// first tile's column and row, and how many columns and rows it spans —
  /// landed by [by] on the pages of what lands ([landedCel]), each a tile
  /// where it lies: a picture the engine made whole over its rectangle,
  /// landed as it lies on the device — the letters' plate
  /// (`EngineLetters`), what a plug-in's step made (`GpuFxPlugin`).
  ///
  /// ⚠️One at the second, not the third (캔버스 베이스 2026-11-15): the
  /// plug-in's landing spelled the plate's steps token for token, and all
  /// that differs between the two is what [land] takes already ([by]) —
  /// nothing to reconcile and no flag to invent, so the clone ratchet read
  /// the pair as what it was (`one_algorithm_one_place_test`). The engine's
  /// two doors stay two: each lands a thing of its own (`GpuLetters.land` ·
  /// `GpuPluginMade.land`) — the letters' laid on the engine's thread
  /// unwaited (2026-11-18), the plug-in's waited for.
  Map<TileCoord, BitmapTile> landWhole(
    ({int x0, int y0, int columns, int rows}) rect, {
    required LandedBy by,
  }) {
    final (:x0, :y0, :columns, :rows) = rect;
    final asks = <TileAsk>[
      for (var down = 0; down < rows; down++)
        for (var across = 0; across < columns; across++)
          (column: x0 + across, row: y0 + down, under: null),
    ];
    final landed = land(landedCel, asks, by: by);
    return {
      for (final (at, (:column, :row, under: _)) in asks.indexed)
        TileCoord(x: column, y: row): landed[at].tile!,
    };
  }

  /// Lets [slot] go, once — its tile's finalizer and a walk that found the
  /// tile collected first both come to it —, and its tile's place empty:
  /// the tile has no slot till it is stored again.
  void _letGo(_Slot slot) {
    if (slot.out) {
      return;
    }
    slot.out = true;
    slot.keepsNothing();
    slot.place.slot = null;
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

  /// The slots a full pool lets go at the least ([_shortAsRoomIsMade]): a
  /// page's worth of the pool's, 128 MiB of tiles.
  static const int roomBatch = 2048;

  final int _roomBatch;

  /// The slot [tile] has, or null — nothing is stored here. A probe: a
  /// call that runs over slots asks [held].
  GpuTile? slotOf(BitmapTile tile) => _slotNow(tile)?.at;

  /// The record of the slot [tile] has, or null — a probe of what holds a
  /// record once its slot goes, which a test reads off the heap.
  @visibleForTesting
  Object? recordOf(BitmapTile tile) => _slotNow(tile);

  /// How [tile]'s landing is made again, where its slot keeps that
  /// ([_Slot.made]), or null — a probe of what a tile holds while it waits
  /// for its bytes, and lets go of once they are here.
  @visibleForTesting
  LandsAgain? madeBy(BitmapTile tile) => _slotNow(tile)?.made?.by;

  /// The place [tile]'s key has ([BitmapTile.pixelsKey]), or null before
  /// its first store — a probe: a key stored again is in the one it had,
  /// its finalizer attached once.
  @visibleForTesting
  Object? placeOf(BitmapTile tile) => _places[tile.pixelsKey];

  static void _refuseOtherGrids(List<BitmapTile> tiles) {
    for (final tile in tiles) {
      if (tile.size != gpuTileSide) {
        throw StateError(
          'a tile of ${tile.size}² — the engine stores $gpuTileSide²',
        );
      }
    }
  }

  /// [TileHold.gridOf]: the grid answered for [tiles] the last time, where
  /// none of the slots it answered is out ([_Slot.out]) — [hold] then
  /// holds its keys as they were kept —, else the grid asked anew, and
  /// kept.
  ///
  /// 🚨A MAP OF TILES IS ASKED AGAIN AT EVERY PLAN (card
  /// every-plan-asks-every-rows-tile-slots-again): a plan asks every row's
  /// tiles whole (`composite_tree_plan.dart`), at every step of a stroke
  /// as its frame's picture is patched and at every frame the band bakes,
  /// and a row that did not change hands over the same map — its
  /// surface's own, which no one writes to. A slot changes only where it
  /// is let go, or moved to a shell's tile ([_shellOf]) — out, either
  /// way —, so a grid stands while none of its own is. 🔬The test VM,
  /// S5_BA cut 352 (68 rows), a stroke on a full band: 282 ms of the UI
  /// thread's 1,566 asking every row's slots, 18% (2026-11-18).
  /// ↩️It stood while no slot at all had been let go since (cd6c872a6,
  /// mine): the tiles a stroke leaves behind are collected as it goes,
  /// each letting its slot go, so hardly a plan found its grids — 🔬the
  /// same stroke after it, 159 ms of 1,279 still asking, 118 of them each
  /// tile's slot (k1279).
  TileGrid _gridOf(
    TileHold hold,
    Object cel,
    Map<TileCoord, BitmapTile> tiles,
  ) {
    final kept = _grids[tiles];
    if (kept != null && !kept.slots.any((slot) => slot.out)) {
      hold._keptKeys.add(kept.keys);
      return kept.grid;
    }
    final coords = tiles.keys;
    final x0 = coords.map((coord) => coord.x).reduce(math.min);
    final y0 = coords.map((coord) => coord.y).reduce(math.min);
    final columns = coords.map((coord) => coord.x).reduce(math.max) - x0 + 1;
    final rows = coords.map((coord) => coord.y).reduce(math.max) - y0 + 1;
    final slots = _heldSlotsOf(hold, cel, tiles.values.toList());
    final grid = List<GpuTile?>.filled(columns * rows, null);
    for (final (at, coord) in coords.indexed) {
      grid[(coord.y - y0) * columns + coord.x - x0] = slots[at].at;
    }
    final answered = (
      x0: x0,
      y0: y0,
      columns: columns,
      rows: rows,
      tiles: List<GpuTile?>.unmodifiable(grid),
    );
    _grids[tiles] = (
      slots: slots,
      keys: Set<Object>.identity()
        ..addAll(tiles.values.map((tile) => tile.pixelsKey)),
      grid: answered,
    );
    return answered;
  }

  /// The grid each map of tiles was last answered ([_gridOf]).
  final Expando<_KeptGrid> _grids = Expando('engine tile grids');

  /// How many tiles were asked their slots ([_slotsOf]) — what a kept
  /// grid ([_gridOf]) spares.
  @visibleForTesting
  int debugSlotsAsked = 0;

  List<GpuTile> _slotsOf(TileHold hold, Object cel, List<BitmapTile> tiles) =>
      [for (final slot in _heldSlotsOf(hold, cel, tiles)) slot.at];

  /// The slot of each of [tiles], held by [hold] — stored on [cel]'s pages
  /// where it has none ([_slotsOf]).
  List<_Slot> _heldSlotsOf(
    TileHold hold,
    Object cel,
    List<BitmapTile> tiles,
  ) {
    debugSlotsAsked += tiles.length;
    _refuseOtherGrids(tiles);
    hold._keys.addAll(tiles.map((tile) => tile.pixelsKey));
    // Once a key: two tiles of a colour asked together are one store.
    final asked = Set<Object>.identity();
    final missing = [
      for (final tile in tiles)
        if (_slotNow(tile) == null && asked.add(tile.pixelsKey)) tile,
    ];
    if (missing.isNotEmpty) {
      _store(_cels.putIfAbsent(cel, pool.cel), missing);
    }
    return [for (final tile in tiles) _slotNow(tile)!];
  }

  /// [tiles], none with a slot, each given one of [cel]'s: within the
  /// budget, else as room is made ([_shortAsRoomIsMade]).
  void _store(int cel, List<BitmapTile> tiles) {
    var stored = _put(cel, tiles);
    if (stored == tiles.length) {
      return;
    }
    final short = _shortAsRoomIsMade(tiles.length - stored, () {
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

  /// How many of the [short] tiles a store had no slot for are still
  /// without one once room is made for them: [placeRest] places what is
  /// left and answers how many still are, asked again after each step —
  /// the slots no hold has, of tiles whose bytes are here, let go, the
  /// ones stored longest ago first, as many as the store is short and
  /// [roomBatch] at the least, and [byteBudget] lifted; the bytes of tiles
  /// the engine alone holds moved here ([_moveBytesHere]); a page past the
  /// OS's budget.
  ///
  /// ↩️Till 2026-11-15 the first step let go EVERY slot no hold had (캔버스
  /// 베이스's own, 11-08 — nobody's order): the pictures' budget, which it
  /// was written after, lets go the least recently shown till the rest fit
  /// (`TilePictureBudget.letGo`), not all of them. 🔬The Surface, FNK_02
  /// cut 59 as the onion's ghosts were laid, the pool's 22,000 slots
  /// turning over 3.7 times a pass whatever the law (2026-11-15, card
  /// a-picture-lay-holds-the-raster-thread, a quiet run each): let go
  /// whole, 4 times a pass, 15.2 to 22.0 ms of the UI thread a time and 40
  /// to 50 ms a pass; as many as each store was short and no more, some
  /// 600 times a pass, 0.17 ms a time and 92 to 123 ms a pass — a walk's
  /// own cost at every store; a page's worth at the least, 35 times a
  /// pass, 1.2 ms a time (6.6 once) and 18 to 29 ms a pass.
  int _shortAsRoomIsMade(int short, int Function() placeRest) {
    _letGoWhere(
      (key, _) => _noHoldHas(key),
      most: math.max(short, _roomBatch),
    );
    pool.makeNoPagePast(_unbounded);
    try {
      short = placeRest();
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
    final going = [
      for (final (:tile, slot: _)
          in _engineAlone
              .where((held) => _noHoldHas(held.tile))
              .take(math.max(short, readBatch)))
        tile,
    ];
    if (going.isEmpty) {
      return false;
    }
    _copyHere(going);
    _letGoWhere((key, _) => _noHoldHas(key));
    return true;
  }

  /// The tiles the engine alone holds, each with its slot, the oldest
  /// first.
  Iterable<({BitmapTile tile, _Slot slot})> get _engineAlone sync* {
    for (final slot in _stored) {
      final tile = slot.out ? null : slot.onlyOnEngine;
      if (tile != null) {
        yield (tile: tile, slot: slot);
      }
    }
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
        _slotNow(tile)?.keepsNothing();
      }
    });
  }

  /// Copies here the bytes of the oldest tiles the engine alone holds that
  /// no copy on its way was asked for ([_Slot.onItsWay]) — [copyBatch] of
  /// them —, their slots kept; whether there may be more.
  ///
  /// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에 사본을 두고 앱을
  /// 유지한다」 — a device the driver takes away takes every tile on it. One
  /// whose copy is here is stored again from it on the next device; one
  /// whose copy had not come reads as the picture it landed on
  /// ([_layThePictureUnder]).
  ///
  /// 🚨THIS ISOLATE WAITS FOR NO GPU HERE (🗣️관제 2026-11-12,
  /// a-lost-gpu-device-keeps-the-unsaved-tiles: 「UI(또는 래스터) 스레드를
  /// 붙잡는가? 붙잡으면 (B) 안에서 엔진 스레드 비동기로 옮긴 뒤 착지한다
  /// (구형 기기 방침 — 서피스는 더 느리다)」). The tiles' copy is submitted
  /// here, where the pool is this isolate's alone ([GpuPool.readout]), and
  /// waited for on the engine's thread ([GpuReadout.mapping]), which tells
  /// this isolate once the bytes are mapped: a press, a frame of a
  /// playback started as the hand came to rest go between the two.
  /// ⚠️What they submit meanwhile goes behind that thread's poll — for as
  /// long as the GPU still takes over what was submitted before it
  /// (rust/src/device.rs, `Engine::map_then`). ↩️Read here ([_copyHere])
  /// till 2026-11-12, a batch held this isolate for the GPU, one behind
  /// another.
  ///
  /// 🚨WHAT COMES BACK IS KEPT BY THE TILE IT WAS ASKED OF, AND ONLY WHERE
  /// THAT TILE STILL WAITS FOR IT ([_stillWaits]). The bytes are its own
  /// whatever landed since: they are the ones its slot held as the copy
  /// was submitted (rust/src/kernels/pool/mod.rs, `Pool::read_out`), and a
  /// stroke over it lands on a tile of its own. But meanwhile it may have
  /// come to hold them by a read here — a save's, a full pool's
  /// ([_moveBytesHere]) — or been retired ([retire]).
  ///
  /// A device that goes under the wait takes these tiles with it: each
  /// reads as the picture it landed on, as under a read here ([_copyHere]).
  ///
  /// The bytes come through one block [blocks] gives, given back whatever
  /// becomes of the copy.
  Future<bool> copyHereABatch({Allocator blocks = malloc}) async {
    final asked = _engineAlone
        .where((held) => !held.slot.onItsWay)
        .take(copyBatch)
        .toList();
    if (asked.isEmpty) {
      return false;
    }
    final tiles = [for (final (:tile, slot: _) in asked) tile];
    final block = blocks<Uint8>(tiles.length * gpuTileBytes);
    for (final (tile: _, :slot) in asked) {
      slot.onItsWay = true;
    }
    try {
      final readout = held(
        (hold) => pool.readout(hold.slotsOf(landedCel, tiles)),
      );
      try {
        await readout.mapping();
        readout.rows(
          block,
          offset: 0,
          stride: gpuTileBytes,
          rowBytes: gpuTileBytes,
          rows: tiles.length,
          dstStride: gpuTileBytes,
        );
      } finally {
        readout.free();
      }
      final bytes = block.asTypedList(tiles.length * gpuTileBytes);
      for (final (at, (:tile, :slot)) in asked.indexed) {
        if (_stillWaits(tile, slot)) {
          final from = at * gpuTileBytes;
          tile.keepBytesHere(
            Uint8List.sublistView(bytes, from, from + gpuTileBytes),
          );
          slot.keepsNothing();
        }
      }
    } on GpuRefused {
      if (!_engine.isGone) {
        rethrow;
      }
      _copyHere([
        for (final (:tile, :slot) in asked)
          if (_stillWaits(tile, slot)) tile,
      ]);
    } finally {
      for (final (tile: _, :slot) in asked) {
        slot.onItsWay = false;
      }
      blocks.free(block);
    }
    return asked.length == copyBatch;
  }

  /// Whether [tile] still waits for the bytes asked of [slot], its own as
  /// they were asked ([copyHereABatch]): the engine still holds the only
  /// copy of them, in that slot.
  bool _stillWaits(BitmapTile tile, _Slot slot) =>
      tile.isOnlyOnEngine && !slot.out;

  /// The tiles a batch of the copies at rest copies ([copyHereABatch]):
  /// what this isolate is held for in one turn is a batch's asking, or its
  /// bytes' keeping. 🔢브러시/렌더링's pick. 🔬Main PC (RTX 4080, DX12),
  /// 2026-11-12, 512 tiles (test/native/copies_at_rest_benchmark_test.dart),
  /// medians: a batch holds this isolate 0.2 ms as it is asked and 0.2 ms
  /// as its bytes are kept, and has come 0.7 ms after it was asked — 0.1 ms
  /// of that the wait for the GPU, the engine's thread's (1.3 ms at its
  /// longest; 36 ms beside a busy test line, where each part is 3–5 times
  /// as long). Read here, as till that day, a batch held this isolate
  /// 0.24 ms and its keeping — that wait in it. 🔬A Surface Pro 11
  /// (검증/서피스, the same day, the same test): 0.2 ms as it is asked and
  /// 0.3 ms as its bytes are kept, come 1.0–1.2 ms after — 0.5 ms of that
  /// the engine's thread's wait (5.3 ms at its longest) — and no turn of
  /// this isolate over 8 ms while the batches went; read here, a batch
  /// held it 0.65 ms and its keeping.
  static const int copyBatch = 8;

  /// How long after the last landing the hand is taken to rest, and the
  /// copies begin ([copyHereABatch]). 🔢브러시/렌더링's pick, to measure: a
  /// landing comes at every frame of a stroke and at each pen's lift.
  static const Duration rest = Duration(milliseconds: 500);

  /// Whether a landing asks for copies once the hand rests: a launch's
  /// word, before its first frame (`main`). False where no launch said so
  /// — a test's ledger arms no timer, which a widget test's clock would
  /// not end of its own accord; the pins of the copies say so themselves.
  static bool copiesAtRest = false;

  Timer? _atRest;

  /// Copies what the engine alone holds here once the hand has rested
  /// ([rest]) from the last landing: one more puts the copies off.
  void _copyHereOnceTheHandRests() {
    if (!copiesAtRest) {
      return;
    }
    _atRest?.cancel();
    _atRest = Timer(rest, () => unawaited(_copyHereAtRest()));
  }

  /// The batches of a rest, one behind another ([copyHereABatch]), till
  /// none is left or a landing puts them off ([_atRest] armed again). A
  /// rest that ends while the last one's batch is still on its way asks
  /// for the tiles after it: no tile is asked for twice ([_Slot.onItsWay]).
  Future<void> _copyHereAtRest() async {
    _atRest = null;
    while (_atRest == null && await copyHereABatch()) {}
  }

  bool _noHoldHas(Object? key) => !_holds.any((hold) => hold._has(key));

  /// Stores [tiles] in one store and gives each landed its slot; how many
  /// landed, the first of them.
  int _put(int cel, List<BitmapTile> tiles) {
    final slots = pool.store(cel, tiles, _bytesOf);
    for (var at = 0; at < slots.length; at++) {
      _give(tiles[at], slots[at]);
    }
    return slots.length;
  }

  /// Lets go the slots whose copy the engine's thread did not write
  /// ([GpuPool.onUnwritten]): their tiles are stored again where they are
  /// next asked for, from the bytes they still hold.
  void _letGoUnwritten(List<GpuTile> unwritten) {
    final places = unwritten.toSet();
    _letGoWhere((_, at) => places.contains(at));
  }

  /// Lets go the slot of every key [goes] names — null for a key collected
  /// —, at its place, but a tile's the engine alone holds, which has no
  /// bytes to be stored again from: the ones stored longest ago first and
  /// no more than [most] of them, where given. What is let go is swept out
  /// of [_stored], as far as the walk went.
  ///
  /// 🚨THE CALLER'S QUESTION FIRST (card a-closed-projects-collection-
  /// walks-the-tile-ledger, 2026-11-18): [goes] is what the walk is for,
  /// and whether the engine alone holds a tile only guards a slot it would
  /// let go. A collected key's walk passes every live slot — some 22,000
  /// of them (FNK_02 cut 59) — to find the few whose key is gone.
  /// ↩️Asked the other way round since the walk was written (nobody's
  /// order): 🔬the test VM, a closed project collected as an eye was
  /// toggled (S5_BA cut 352, a second copy handed over), 194 ms of the UI
  /// thread, 161 of them asking each live slot whether the engine alone
  /// held its tile.
  void _letGoWhere(
    bool Function(Object? key, GpuTile at) goes, {
    int? most,
  }) {
    var gone = 0;
    var kept = 0;
    var walked = 0;
    for (; walked < _stored.length && gone != most; walked++) {
      final slot = _stored[walked];
      if (slot.out) {
        continue;
      }
      final key = slot.key.target;
      if (!goes(key, slot.at) || _guards(key)) {
        _stored[kept++] = slot;
        continue;
      }
      _letGo(slot);
      gone += 1;
    }
    _stored.removeRange(kept, walked);
  }

  /// Whether [key] is a tile the engine alone holds — a slot no walk lets
  /// go ([_letGoWhere]).
  bool _guards(Object? key) {
    debugGuardsAsked += 1;
    return _Slot.onlyOnEngineOf(key) != null;
  }

  /// How many slots a walk asked whether the engine alone holds their
  /// tile ([_guards]): those its caller's question let through.
  @visibleForTesting
  int debugGuardsAsked = 0;
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

/// How a landing is made again once the engine it was made on is gone:
/// what it laid, as values — nothing of that engine's, which a [LandedBy]
/// holds.
///
/// 🗣️유저 2026-11-19 (cel-originals-are-held-twice-in-ram-and-on-the-gpu-Q2):
/// 「픽셀 대신 「한 일의 기록」을 들고, 잃으면 다시 그린다」.
abstract interface class LandsAgain {
  /// The landing of [asks] — each as it was asked, its `under` the tile it
  /// landed on — made on the engine the app stands on now: what it makes
  /// of each, in order. Refused as that engine refuses.
  List<LandedTile> again(List<TileAsk> asks);
}

/// How a landed tile's landing is made again, and where the tile lies in
/// it ([_Slot.made]).
typedef _Made = ({LandsAgain by, int column, int row});

/// What a key has here for as long as it lives — a tile, or a colour's
/// block ([BitmapTile.pixelsKey]): the slot it has now — none once a full
/// pool, a give-back or [EngineTileLedger.retire] let that go, till it is
/// stored again. One a key, made at its first store, and what its
/// finalizer is handed: attached once, and never detached.
///
/// ↩️Till 2026-11-15 the finalizer was handed the slot — attached at every
/// store, the slot its own token, and detached where a full pool let it
/// go: left attached, a tile that lived on kept one record each time a
/// full pool let it go and it was stored again (mutant D10, 관제 11-08
/// 07:11). A detach looks its token up in a table of the finalizer's and a
/// store writes it there, and a full pool did both for every slot it had:
/// 🔬the Surface, FNK_02 cut 59 as the onion's ghosts were laid (캔버스
/// 베이스 2026-11-15, card a-picture-lay-holds-the-raster-thread) — four
/// times a pass, some 21,000 slots each, 10.9 to 22.8 ms of the UI thread
/// a time. With one place a tile nothing piles up to detach: a slot let go
/// leaves the place empty ([EngineTileLedger._letGo]) and the next store
/// fills it — what the heap is still asked
/// (a_tile_collected_lets_its_engine_slot_go_test.dart).
final class _Place {
  _Slot? slot;
}

/// A slot a key has here — a tile, or a colour's block
/// ([BitmapTile.pixelsKey]) —, its key held weakly: being stored must not
/// keep a tile, or a colour, alive.
final class _Slot {
  _Slot(Object key, this.at, this.place) : key = WeakReference(key);

  final WeakReference<Object> key;
  final GpuTile at;

  /// Its key's place, which holds it till it is let go.
  final _Place place;

  /// Its tile, where the engine holds the only copy of that tile's pixels
  /// ([BitmapTile.isOnlyOnEngine]) — null for a tile collected or one whose
  /// pixels are here, and for a colour's block, whose tiles' pixels are
  /// here from the start.
  BitmapTile? get onlyOnEngine => onlyOnEngineOf(key.target);

  /// [key] where it is a tile the engine holds the only copy of the
  /// pixels of ([onlyOnEngine]), else null.
  static BitmapTile? onlyOnEngineOf(Object? key) => switch (key) {
    final BitmapTile tile when tile.isOnlyOnEngine => tile,
    _ => null,
  };

  /// The tile [onlyOnEngine] landed on — null where it landed on none, or
  /// was not landed — kept while the engine holds the only copy of its
  /// pixels: what it reads as where a device goes with them
  /// (`EngineTileLedger._layThePictureUnder`). Let go once its bytes are
  /// here, and with the slot.
  BitmapTile? under;

  /// How the landing that made [onlyOnEngine] is made again, where it said
  /// ([LandsAgain]) — what the tile reads as before [under], should the
  /// device go with its pixels (`EngineTileLedger._makesAgain`). Kept and
  /// let go as [under] is.
  _Made? made;

  /// Its tile's bytes are here: neither is its to keep any longer.
  void keepsNothing() {
    under = null;
    made = null;
  }

  /// Let go already — by its key's finalizer, a full pool or a give-back.
  bool out = false;

  /// Asked for by a copy that is still on its way
  /// (`EngineTileLedger.copyHereABatch`): not one the next batch asks for
  /// again.
  bool onItsWay = false;
}

/// What reads a shell's tile ([EngineTileLedger.shellOf]): its slot where
/// the ledger still has one, else the tile [at] of its cel's kept bytes,
/// read again.
final class _ShellPixels implements TilePixelsKeptBesides {
  _ShellPixels(this._ledger, this._cel, this.at);

  final EngineTileLedger _ledger;
  final _KeptCel _cel;
  final TileCoord at;

  @override
  void readInto(BitmapTile tile, Pointer<Uint8> into) {
    if (!_ledger._readsItsSlot(tile, into)) {
      _layBytesOf(_cel.read().tiles[at], into);
    }
  }
}

/// Lays [tile]'s bytes in [into], a tile's worth — none, where there is no
/// tile: what a tile reads as where its slot cannot be read.
void _layBytesOf(BitmapTile? tile, Pointer<Uint8> into) {
  final bytes = into.asTypedList(gpuTileBytes);
  if (tile == null) {
    zeroBytes(bytes);
  } else {
    tile.readPixels((_, view) => bytes.setAll(0, view));
  }
}

/// A shell's cel as its kept bytes hold it, read again where the engine
/// let a slot of it go: once for every tile a turn reads so, then let go.
final class _KeptCel {
  _KeptCel(this._readAgain);

  final BitmapSurface Function() _readAgain;
  BitmapSurface? _read;

  BitmapSurface read() {
    final read = _read;
    if (read != null) {
      return read;
    }
    scheduleMicrotask(() => _read = null);
    return _read = _readAgain();
  }
}

/// What a call of [EngineTileLedger.held] is handed: the slots asked for
/// through it stay till that call returns.
/// A grid answered for a map of tiles ([EngineTileLedger._gridOf]): the
/// slots it answered, its tiles' keys, and the grid.
typedef _KeptGrid = ({List<_Slot> slots, Set<Object> keys, TileGrid grid});

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

  /// The key of every tile asked for through this hold
  /// ([BitmapTile.pixelsKey]) — by identity, as `==` reads every pixel.
  final Set<Object> _keys = Set<Object>.identity();

  /// The keys of the grids answered as they were kept
  /// ([EngineTileLedger._gridOf]): held as their sets, and put in [_keys]
  /// the first time a walk asks ([_has]) — a plan asks every row's grid,
  /// and a walk that lets slots go is rare.
  final List<Set<Object>> _keptKeys = [];

  /// Whether a tile of [key] was asked for through this hold.
  bool _has(Object? key) {
    for (final keys in _keptKeys) {
      _keys.addAll(keys);
    }
    _keptKeys.clear();
    return _keys.contains(key);
  }

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
    if (!_open) {
      throw StateError('a hold is asked inside the call it was handed to');
    }
    return _ledger._gridOf(this, cel, tiles);
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
