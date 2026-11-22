import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/native/tile_blocks.dart';
import 'package:anicel/src/native/tiles_at_rest.dart';
import 'package:anicel/src/services/brush_frame_store.dart';

import '../helpers/cels_parked_cold.dart';
import '../helpers/poll_until.dart';
import '../helpers/tiles_on_the_engine.dart';

/// 🚨Card let-go-cels-keep-their-gpu-tiles (유저 2026-11-16 03:10: 「지금
/// 착지하고, GPU 타일을 남기는 일을 바로 다음으로」): a cel a look lets go
/// of keeps what the engine holds of it — each tile's slot given to a
/// shell's tile that holds no bytes here ([EngineTileLedger.shellOf]) —
/// and a shell's tile whose slot a full pool let go reads the cel's kept
/// bytes again. When the store keeps a shell and hands it is the store's
/// (a_cel_a_look_let_go_is_looked_at_again_as_its_shell_test.dart).
///
/// And what a rest lays of a kept cel before it makes its shell
/// ([EngineTileLedger.lay] — card
/// cel-originals-are-held-twice-in-ram-and-on-the-gpu, 유저 2026-11-21 on
/// Q6 「사본이나 ram에있는걸 최대한 없애고싶어서」): the tiles no screen
/// stored are stored there, so the shell holds no byte of the cel here.
/// When a rest lays is the store's
/// (a_hot_cel_that_is_kept_lets_its_bytes_go_at_a_rest_test.dart).
void main() {
  // Cels by the name a painter gives one.
  const a = (2, 1);
  const b = (2, 2);
  final canvasSize = CanvasSize(width: 2 * gpuTileSide, height: gpuTileSide);
  final left = TileCoord(x: 0, y: 0);
  final right = TileCoord(x: 1, y: 0);

  BitmapSurface aCelOf(Map<TileCoord, BitmapTile> tiles) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: gpuTileSide,
    tiles: tiles,
  );

  BitmapSurface neverReadAgain() =>
      fail('a shell whose slots stand reads nothing again');

  /// Fills the page [ledger] stores on and stores one tile more: the two
  /// slots stored longest ago go — of a ledger of one page that lets go
  /// two at a time (`byteBudget: 0, roomBatch: 2`) and has stored two.
  void theTwoOldestSlotsGo(EngineTileLedger ledger) {
    final slots = ledger.pool.bytes ~/ gpuTileBytes;
    final rest = [for (var n = 2; n < slots; n++) aTileOfItsOwn()];
    ledger.held((hold) => hold.slotsOf(a, rest));
    ledger.held((hold) => hold.slotsOf(b, [aTileOfItsOwn()]));
  }

  test('🚨a tile with a slot gives it to its shell — the same slot, the '
      'tile none, and no slot more', () {
    final ledger = EngineTileLedger(appGpuEngine);
    final tile = aTileOfItsOwn();
    final [slot] = ledger.held((hold) => hold.slotsOf(a, [tile]));
    final count = ledger.slotCount;
    final ink = tile.inkBounds;

    final shell = ledger.shellOf(
      aCelOf({left: tile}),
      readAgain: neverReadAgain,
    )!;
    final kept = shell.tiles[left]!;

    expect(ledger.slotOf(kept), slot);
    expect(ledger.slotOf(tile), isNull, reason: 'its slot is the shell\'s');
    expect(ledger.slotCount, count);
    expect(kept.isOnEngine, isTrue);
    expect(
      kept.isOnlyOnEngine,
      isFalse,
      reason: 'kept besides: a full pool lets it go',
    );
    expect(ledger.isWhole(shell), isTrue);
    final reads = ledger.debugTileReads;
    expect(kept.inkBounds, ink);
    expect(
      ledger.debugTileReads,
      reads,
      reason: 'what was known of its ink goes with it — nothing read back',
    );
  });

  test('a shell\'s tile reads its pixels from its slot — and nothing from '
      'the cel\'s kept bytes', () async {
    final ledger = EngineTileLedger(appGpuEngine);
    final tile = aTileOfItsOwn();
    ledger.held((hold) => hold.slotsOf(a, [tile]));
    await appGpuEngine.done();

    final shell = ledger.shellOf(
      aCelOf({left: tile}),
      readAgain: neverReadAgain,
    )!;

    expect(shell.tiles[left]!.pixels, tile.pixels);
  });

  test('a tile of a colour, and one with no slot, stay as they are — and a '
      'cel with no tile of its own on the engine keeps no shell', () {
    final ledger = EngineTileLedger(appGpuEngine);
    final colour = BitmapTile.ofOneColour(
      size: gpuTileSide,
      word: 0xFF0000FF,
    );
    final unasked = aTileOfItsOwn();
    ledger.held((hold) => hold.slotsOf(a, [colour]));

    expect(
      ledger.shellOf(
        aCelOf({left: colour, right: unasked}),
        readAgain: neverReadAgain,
      ),
      isNull,
    );

    final asked = aTileOfItsOwn();
    ledger.held((hold) => hold.slotsOf(a, [asked]));
    final shell = ledger.shellOf(
      aCelOf({left: colour, right: asked}),
      readAgain: neverReadAgain,
    )!;
    expect(shell.tiles[left], same(colour));
    expect(shell.tiles[right], isNot(same(asked)));

    final another = aTileOfItsOwn();
    ledger.held((hold) => hold.slotsOf(a, [another]));
    expect(
      ledger.isWhole(
        ledger.shellOf(
          aCelOf({left: unasked, right: another}),
          readAgain: neverReadAgain,
        )!,
      ),
      isTrue,
      reason: 'a tile whose bytes are here wants no slot',
    );
  });

  test('a shell looked at and let go again is the same shell', () {
    final ledger = EngineTileLedger(appGpuEngine);
    final tile = aTileOfItsOwn();
    ledger.held((hold) => hold.slotsOf(a, [tile]));
    final shell = ledger.shellOf(
      aCelOf({left: tile}),
      readAgain: neverReadAgain,
    )!;

    expect(
      ledger.shellOf(shell, readAgain: neverReadAgain),
      same(shell),
    );
  });

  test('🚨a shell whose slots a full pool let go is whole no more, and reads '
      'the cel\'s kept bytes again — once for every tile a turn reads', () {
    // A batch of two: the two oldest slots no hold has go, the rest of the
    // page standing.
    final ledger = EngineTileLedger(
      appGpuEngine,
      byteBudget: 0,
      roomBatch: 2,
    );
    final first = aTileOfItsOwn();
    final second = aTileOfItsOwn();
    ledger.held((hold) => hold.slotsOf(a, [first, second]));
    final cel = aCelOf({left: first, right: second});
    var readsAgain = 0;
    final shell = ledger.shellOf(
      cel,
      readAgain: () {
        readsAgain += 1;
        return cel;
      },
    )!;
    // The rest of its page, so the next cel finds the pool full.
    final slots = ledger.pool.bytes ~/ gpuTileBytes;
    final rest = [for (var n = 2; n < slots; n++) aTileOfItsOwn()];
    ledger.held((hold) => hold.slotsOf(a, rest));
    expect(ledger.isWhole(shell), isTrue, reason: '⛔premise');

    ledger.held((hold) => hold.slotsOf(b, [aTileOfItsOwn()]));

    expect(ledger.slotOf(shell.tiles[left]!), isNull, reason: '⛔premise');
    expect(ledger.isWhole(shell), isFalse);
    expect(shell.tiles[left]!.pixels, first.pixels);
    expect(shell.tiles[right]!.pixels, second.pixels);
    expect(readsAgain, 1);
  });

  // A tile's block holds whatever the allocator left in it (TileBlocks) —
  // here every byte set, said aloud.
  test('a tile of a shell whose cel keeps no bytes of it reads as nothing, '
      'whatever its block held before', () {
    TileBlocks.debugComesFullOf = 0xFF;
    addTearDown(() => TileBlocks.debugComesFullOf = null);
    final ledger = EngineTileLedger(
      appGpuEngine,
      byteBudget: 0,
      roomBatch: 2,
    );
    final first = aTileOfItsOwn();
    final second = aTileOfItsOwn();
    ledger.held((hold) => hold.slotsOf(a, [first, second]));
    final shell = ledger.shellOf(
      aCelOf({left: first, right: second}),
      readAgain: () => aCelOf({right: second}),
    )!;
    theTwoOldestSlotsGo(ledger);
    expect(ledger.slotOf(shell.tiles[left]!), isNull, reason: '⛔premise');

    expect(shell.tiles[left]!.pixels.every((byte) => byte == 0), isTrue);
  });

  // One law for every store: one made with no keeper of its own keeps
  // its shells through the app's ledger (DrawingEngines.celShells).
  test('🚨a store given no keeper keeps a shell through the app\'s ledger',
      () async {
    final store = BrushFrameStore();
    const key = BrushFrameKey(
      projectId: ProjectId('p'),
      trackId: TrackId('t'),
      cutId: CutId('c'),
      layerId: LayerId('l'),
      frameId: FrameId('f'),
    );
    parkCold(store, {key: aCelOf({left: aTileOfItsOwn()})});
    final looked = (await store.lookAhead(key, canvasSize: canvasSize))!;
    EngineTileLedger.instance.held(
      (hold) => hold.slotsOf(a, looked.tiles.values.toList()),
    );

    store.keepShellOf(
      key,
      looked,
      canvasSize: canvasSize,
      revision: store.sourceRevisionOf(key),
    );

    expect(store.shells, hasLength(1));
  });

  // A thaw stores nothing on the engine, which is what else brings its
  // tiles to rest (the_ledger_folds_its_tiles_once_the_hand_rests_test.dart).
  test('🚨a store given no keeper asks the app\'s ledger for the rest a '
      'kept cel thawed is let go at', () async {
    EngineTileLedger.foldsAtRest = true;
    addTearDown(() => EngineTileLedger.foldsAtRest = false);
    EngineTileLedger.instance;
    final store = BrushFrameStore();
    const key = BrushFrameKey(
      projectId: ProjectId('p'),
      trackId: TrackId('t'),
      cutId: CutId('c'),
      layerId: LayerId('l'),
      frameId: FrameId('f'),
    );
    parkCold(store, {key: aCelOf({left: aTileOfItsOwn()})});
    var rests = 0;
    final told = Object();
    TilesAtRest.app.tells(told, () => rests += 1);
    addTearDown(() => TilesAtRest.app.forgets(told));

    final thawed = store.bakedSurfaceOrNull(key)!;
    expect(
      thawed.tiles[left]!.hasItsBytesHere,
      isTrue,
      reason: '⛔premise: thawed, its bytes here',
    );

    expect(await pollUntil(() => rests > 0), isTrue);
  });

  test('a shell kept from the ledger of an engine let go is whole no more '
      'on the next', () {
    final kept = EngineTileLedger(appGpuEngine);
    final tile = aTileOfItsOwn();
    kept.held((hold) => hold.slotsOf(a, [tile]));
    final shell = kept.shellOf(
      aCelOf({left: tile}),
      readAgain: neverReadAgain,
    )!;

    expect(EngineTileLedger(appGpuEngine).isWhole(shell), isFalse);
  });

  // ②(2) of card cel-originals-are-held-twice-in-ram-and-on-the-gpu
  // (2026-11-20): a reader of a shell's tile is lent its bytes for its
  // call (BitmapTile.readPixels) — the RAM its cel let go stays let go.

  /// A tile of bytes of its own, told from another by its [mark].
  BitmapTile aTileMarked(int mark) => BitmapTile.written(
    size: gpuTileSide,
    write: (pixels) => pixels
      ..fillRange(0, pixels.length, 0)
      ..[BitmapTile.bytesPerPixel - 1] = mark,
  );

  test('🚨a read of a shell\'s tile keeps nothing here — the next reader '
      'reads its slot again', () async {
    final ledger = EngineTileLedger(appGpuEngine);
    final tile = aTileMarked(1);
    ledger.held((hold) => hold.slotsOf(a, [tile]));
    await appGpuEngine.done();
    final kept = ledger
        .shellOf(aCelOf({left: tile}), readAgain: neverReadAgain)!
        .tiles[left]!;
    final came = BitmapTile.timesBytesCameHere;
    final reads = ledger.debugTileReads;

    expect(kept.pixels, tile.pixels);
    expect(kept.pixels, tile.pixels);

    expect(ledger.debugTileReads, reads + 2);
    expect(kept.hasItsBytesHere, isFalse);
    expect(kept.ownBytes, 0);
    expect(BitmapTile.timesBytesCameHere, came, reason: 'no weight moved');
  });

  test('🚨a read of many asks the engine for a shell\'s tile with the '
      'engine\'s own, in the one read — and the shell\'s keeps nothing',
      () async {
    addTearDown(() => EngineTileLedger.debugBeforeRead = null);
    final ledger = EngineTileLedger(appGpuEngine);
    final under = aTileMarked(1);
    ledger.held((hold) => hold.slotsOf(a, [under]));
    final kept = ledger
        .shellOf(aCelOf({left: under}), readAgain: neverReadAgain)!
        .tiles[left]!;
    final alone = ledger.debugOnEngine(aTileMarked(2));
    final here = aTileMarked(3);
    await appGpuEngine.done();
    final asked = <int>[];
    EngineTileLedger.debugBeforeRead = (tiles) => asked.add(tiles.length);
    final into = malloc<Uint8>(3 * gpuTileBytes);
    addTearDown(() => malloc.free(into));

    ledger.read(a, [kept, alone, here], into);

    expect(into.asTypedList(3 * gpuTileBytes), [
      ...under.pixels,
      ...aTileMarked(2).pixels,
      ...here.pixels,
    ]);
    expect(asked, [2], reason: 'the shell\'s with the engine\'s own');
    expect(kept.hasItsBytesHere, isFalse);
    expect(kept.ownBytes, 0);
  });

  test('a read of many gives a shell\'s tile whose slot went its cel\'s '
      'kept bytes, and stores nothing for it', () {
    addTearDown(() => EngineTileLedger.debugBeforeRead = null);
    final ledger = EngineTileLedger(
      appGpuEngine,
      byteBudget: 0,
      roomBatch: 2,
    );
    final first = aTileMarked(1);
    final second = aTileMarked(2);
    ledger.held((hold) => hold.slotsOf(a, [first, second]));
    final cel = aCelOf({left: first, right: second});
    final kept = ledger.shellOf(cel, readAgain: () => cel)!.tiles[left]!;
    theTwoOldestSlotsGo(ledger);
    expect(ledger.slotOf(kept), isNull, reason: '⛔premise');
    final asked = <int>[];
    EngineTileLedger.debugBeforeRead = (tiles) => asked.add(tiles.length);
    final into = malloc<Uint8>(gpuTileBytes);
    addTearDown(() => malloc.free(into));

    ledger.read(a, [kept], into);

    expect(into.asTypedList(gpuTileBytes), first.pixels);
    expect(asked, isEmpty, reason: 'it has no slot to be read from');
    expect(ledger.slotOf(kept), isNull, reason: 'a read stores nothing');
    expect(kept.hasItsBytesHere, isFalse);
  });

  // A store's copy is the engine's thread's, later, of bytes the store
  // holds a tile for (a_store_handed_over_holds_its_tiles_till_their_copy_
  // reads_them_test.dart) — and a shell's tile holds none: what a read of
  // it is lent goes back as the read returns, the allocator's for the next
  // tile made.
  test('🚨a shell\'s tile whose slot went is stored again from its cel\'s '
      'kept bytes and keeps none — bytes the store has till its copy read '
      'them', () async {
    final ledger = EngineTileLedger(
      appGpuEngine,
      byteBudget: 0,
      roomBatch: 2,
    );
    final first = aTileMarked(1);
    final second = aTileMarked(2);
    ledger.held((hold) => hold.slotsOf(a, [first, second]));
    final cel = aCelOf({left: first, right: second});
    var keepsItsBytes = true;
    final shell = ledger.shellOf(
      cel,
      readAgain: () =>
          keepsItsBytes ? cel : fail('its slot stands: nothing read again'),
    )!;
    theTwoOldestSlotsGo(ledger);
    final kept = shell.tiles[left]!;
    expect(ledger.slotOf(kept), isNull, reason: '⛔premise');
    await appGpuEngine.done();
    final came = BitmapTile.timesBytesCameHere;

    appGpuEngine.debugStandStill(const Duration(milliseconds: 300));
    ledger.held((hold) => hold.slotsOf(a, [kept]));
    // Blocks handed back go to the next tiles made.
    final churned = [
      for (var made = 0; made < 8; made++)
        BitmapTile.written(
          size: gpuTileSide,
          write: (pixels) => pixels
            ..fillRange(0, pixels.length, 0xEE)
            ..[0] = made,
        ),
    ];

    expect(ledger.slotOf(kept), isNotNull);
    expect(kept.hasItsBytesHere, isFalse);
    expect(kept.ownBytes, 0);
    expect(BitmapTile.timesBytesCameHere, came, reason: 'no weight moved');
    await appGpuEngine.done();
    keepsItsBytes = false;
    expect(kept.pixels, first.pixels, reason: 'its slot holds its bytes');
    expect(churned, hasLength(8));
  });

  // What kept a shell's bytes besides is about to go: the store hands
  // each tile its bytes (`BrushFrameStore._letTheFileRefGo`).
  test('🚨a tile of a shell handed its bytes keeps its slot — and, that '
      'slot gone, is stored again from them: nothing is read again', () {
    final ledger = EngineTileLedger(
      appGpuEngine,
      byteBudget: 0,
      roomBatch: 2,
    );
    final first = aTileMarked(1);
    final second = aTileMarked(2);
    ledger.held((hold) => hold.slotsOf(a, [first, second]));
    final shell = ledger.shellOf(
      aCelOf({left: first, right: second}),
      readAgain: neverReadAgain,
    )!;
    final kept = shell.tiles[left]!;
    final slot = ledger.slotOf(kept);
    final reads = ledger.debugTileReads;

    first.readPixels((_, pixels) => kept.keepBytesHere(pixels));

    expect(ledger.slotOf(kept), slot, reason: 'its slot stays its');
    expect(kept.hasItsBytesHere, isTrue);
    expect(kept.isOnlyOnEngine, isFalse);
    expect(kept.pixels, first.pixels);
    expect(ledger.debugTileReads, reads, reason: 'read here, not back');

    theTwoOldestSlotsGo(ledger);
    expect(ledger.slotOf(kept), isNull, reason: '⛔premise');
    ledger.held((hold) => hold.slotsOf(a, [kept]));

    expect(ledger.slotOf(kept), isNotNull);
  });

  group('what a rest lays —', () {
    test('🚨a tile with bytes of its own and no slot is stored, and the '
        'shell made next holds no byte of the cel here: each reads its '
        'pixels from its slot', () async {
      final ledger = EngineTileLedger(appGpuEngine);
      final first = aTileMarked(1);
      final second = aTileMarked(2);
      final cel = aCelOf({left: first, right: second});
      final count = ledger.slotCount;

      ledger.lay(cel, cel: a);

      expect(ledger.slotCount, count + 2);
      await appGpuEngine.done();
      final shell = ledger.shellOf(cel, readAgain: neverReadAgain)!;
      expect(shell.keptTileBytes, 0);
      expect(ledger.isWhole(shell), isTrue);
      expect(shell.tiles[left]!.pixels, first.pixels);
      expect(shell.tiles[right]!.pixels, second.pixels);
    });

    test('a tile of a colour and one with a slot stay as they are: no '
        'slot more', () {
      final ledger = EngineTileLedger(appGpuEngine);
      final colour = BitmapTile.ofOneColour(
        size: gpuTileSide,
        word: 0xFF0000FF,
      );
      final stored = aTileOfItsOwn();
      final [slot] = ledger.held((hold) => hold.slotsOf(a, [stored]));
      final count = ledger.slotCount;

      ledger.lay(aCelOf({left: colour, right: stored}), cel: a);

      expect(ledger.slotCount, count);
      expect(ledger.slotOf(colour), isNull);
      expect(ledger.slotOf(stored), slot);
    });

    test('a shell\'s tile whose slot went is not stored again — it holds '
        'no bytes here to lay, and nothing is read again for it', () {
      final ledger = EngineTileLedger(
        appGpuEngine,
        byteBudget: 0,
        roomBatch: 2,
      );
      final first = aTileOfItsOwn();
      final second = aTileOfItsOwn();
      ledger.held((hold) => hold.slotsOf(a, [first, second]));
      final shell = ledger.shellOf(
        aCelOf({left: first, right: second}),
        readAgain: neverReadAgain,
      )!;
      theTwoOldestSlotsGo(ledger);
      expect(ledger.isWhole(shell), isFalse, reason: '⛔premise');
      final count = ledger.slotCount;

      ledger.lay(shell, cel: a);

      expect(ledger.slotCount, count);
      expect(ledger.isWhole(shell), isFalse);
    });

    test('🚨within the budget as it stands: a full pool takes none of it, '
        'lets go of no slot for it and makes no page', () {
      final ledger = EngineTileLedger(
        appGpuEngine,
        byteBudget: 0,
        roomBatch: 2,
      );
      final stored = aTileOfItsOwn();
      ledger.held((hold) => hold.slotsOf(a, [stored]));
      final slots = ledger.pool.bytes ~/ gpuTileBytes;
      final rest = [for (var n = 1; n < slots; n++) aTileOfItsOwn()];
      ledger.held((hold) => hold.slotsOf(a, rest));
      final bytes = ledger.pool.bytes;
      final count = ledger.slotCount;
      final loose = aTileOfItsOwn();

      ledger.lay(aCelOf({left: loose}), cel: b);

      expect(ledger.slotOf(loose), isNull);
      expect(ledger.slotCount, count);
      expect(ledger.slotOf(stored), isNotNull, reason: 'none let go for it');
      expect(ledger.pool.bytes, bytes);
      expect(loose.hasItsBytesHere, isTrue);
    });

    test('a cel of tiles of another side than the engine\'s is not its '
        'to lay', () {
      final ledger = EngineTileLedger(appGpuEngine);
      final small = aTileOfItsOwn(size: gpuTileSide ~/ 2);
      final count = ledger.slotCount;

      ledger.lay(
        BitmapSurface(
          canvasSize: canvasSize,
          tileSize: gpuTileSide ~/ 2,
          tiles: {left: small},
        ),
        cel: a,
      );

      expect(ledger.slotCount, count);
    });
  });
}
