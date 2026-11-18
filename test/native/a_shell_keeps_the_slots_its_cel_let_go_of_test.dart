import 'dart:ffi';

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
import 'package:anicel/src/services/brush_frame_store.dart';

import '../helpers/cels_parked_cold.dart';
import '../helpers/tiles_on_the_engine.dart';

/// 🚨Card let-go-cels-keep-their-gpu-tiles (유저 2026-11-16 03:10: 「지금
/// 착지하고, GPU 타일을 남기는 일을 바로 다음으로」): a cel a look lets go
/// of keeps what the engine holds of it — each tile's slot given to a
/// shell's tile that holds no bytes here ([EngineTileLedger.shellOf]) —
/// and a shell's tile whose slot a full pool let go reads the cel's kept
/// bytes again. When the store keeps a shell and hands it is the store's
/// (a_cel_a_look_let_go_is_looked_at_again_as_its_shell_test.dart).
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

  // A tile's block comes from the engine's lists, where a freed one parks
  // by its size for the next ask (TileBlocks): what it held is still there.
  test('a tile of a shell whose cel keeps no bytes of it reads as nothing, '
      'whatever its block held before', () {
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
    final slots = ledger.pool.bytes ~/ gpuTileBytes;
    final rest = [for (var n = 2; n < slots; n++) aTileOfItsOwn()];
    ledger.held((hold) => hold.slotsOf(a, rest));
    ledger.held((hold) => hold.slotsOf(b, [aTileOfItsOwn()]));
    expect(ledger.slotOf(shell.tiles[left]!), isNull, reason: '⛔premise');
    final parked = TileBlocks.alloc(gpuTileBytes);
    parked.asTypedList(gpuTileBytes).fillRange(0, gpuTileBytes, 0xFF);
    TileBlocks.free(parked);

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
}
