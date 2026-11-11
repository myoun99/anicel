import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';

import '../helpers/tiles_on_the_engine.dart';

/// The copies the app keeps of what the engine alone holds
/// (🗣️gpu-canonical-store-Q11, 유저 2026-11-10: 「RAM 에 사본을 두고 앱을
/// 유지한다」) are submitted on the isolate that asks and waited for on
/// the engine's thread (`EngineTileLedger.copyHereABatch`) — 🗣️관제 2026-11-12
/// (a-lost-gpu-device-keeps-the-unsaved-tiles): 「UI(또는 래스터) 스레드를
/// 붙잡는가? 붙잡으면 (B) 안에서 엔진 스레드 비동기로 옮긴 뒤 착지한다」 ·
/// 「받은 바이트를 넣을 때의 「그 사이 수거되지 않았고 아직 엔진만 가진
/// 타일에만」 검사가 이 갈래의 핵심이다 … 받기 도중 장치를 잃는 장면도
/// 같이」. So between the two a hand is on the canvas again, and what comes
/// back is kept by the tile it was asked of, where that tile still waits
/// for it.
///
/// Each test asks for a batch, does what comes between before its bytes
/// can — the call returns at its wait —, and then lets them come.
///
/// On an engine and a ledger of the test's own: a device that is gone is
/// gone for its process, and the app has one.
void main() {
  late GpuEngine engine;
  late EngineTileLedger ledger;

  setUp(() {
    engine = GpuEngine.onFirstAdapter();
    ledger = EngineTileLedger(engine);
    // No batch is read on this isolate: one that was would ask here.
    EngineTileLedger.debugBeforeRead = (tiles) =>
        fail('${tiles.length} tile(s) read on the isolate that asked');
  });
  // ⚠️The ledger's pool is not freed with its test: a tile collected after
  // it lets its slot go there (the ledger's finalizer), in a later test.
  tearDown(() {
    EngineTileLedger.debugBeforeRead = null;
    GpuReadout.debugBeforeMapping = null;
    engine.close();
  });

  // A cel, by the name a painter gives one.
  const cel = (1, 1);

  /// A tile of [value] at every byte, its bytes here.
  BitmapTile tileOf(int value) => BitmapTile(
    size: gpuTileSide,
    pixels: Uint8List(gpuTileBytes)..fillRange(0, gpuTileBytes, value),
  );

  List<BitmapTile> landed(List<BitmapTile?> unders, int value) =>
      landedOn(ledger, cel, unders, value);

  test('the isolate that asks waits for no GPU: a batch is on its way as '
      'the call returns, and each tile\'s own bytes are here once it has '
      'ended', () async {
    final tiles = [
      for (final value in [1, 2, 3]) landed([null], value).single,
    ];

    final waits = debugWaitsHere;
    final onItsWay = ledger.copyHereABatch();
    expect(
      tiles.every((tile) => tile.isOnlyOnEngine),
      isTrue,
      reason: 'nothing was waited for',
    );
    expect(await onItsWay, isFalse, reason: 'none is left');
    expect(debugWaitsHere, waits, reason: 'no wait for the GPU here');

    expect(tiles.where((tile) => tile.isOnlyOnEngine), isEmpty);
    engine.debugLose();
    expect(
      [for (final tile in tiles) tile.pixels.toSet()],
      [
        {1},
        {2},
        {3},
      ],
    );
  });

  test('a batch asked for while one is on its way takes the tiles after '
      'it: no tile is asked for twice', () async {
    const batch = EngineTileLedger.copyBatch;
    final tiles = landed(List.filled(batch + 1, null), 9);

    final first = ledger.copyHereABatch();
    final second = ledger.copyHereABatch();
    expect(await first, isTrue);
    expect(await second, isFalse, reason: 'the one left, and no more');

    expect(tiles.where((tile) => tile.isOnlyOnEngine), isEmpty);
    expect(await ledger.copyHereABatch(), isFalse, reason: 'none to ask');
  });

  test('a tile read here while its copy was on its way keeps what it '
      'read', () async {
    final tile = landed([tileOf(7)], 9).single;

    final onItsWay = ledger.copyHereABatch();
    expect(tile.pixels, everyElement(9));
    expect(tile.isOnlyOnEngine, isFalse, reason: '⛔premise: they are here');
    await onItsWay;

    expect(tile.pixels, everyElement(9));
  });

  test('a tile retired while its copy was on its way is given none', () async {
    final tile = landed([null], 9).single;

    final onItsWay = ledger.copyHereABatch();
    ledger.retire(tile);
    await onItsWay;

    expect(tile.isOnlyOnEngine, isTrue, reason: 'no bytes for a tile let go');
    expect(() => tile.pixels, throwsStateError);
  });

  test('a stroke over a tile whose copy is on its way lands on a tile of '
      'its own: the copy that comes is the picture under it', () async {
    final under = landed([null], 7).single;

    final onItsWay = ledger.copyHereABatch();
    final over = landed([under], 9).single;
    await onItsWay;

    expect(under.isOnlyOnEngine, isFalse);
    expect(over.isOnlyOnEngine, isTrue, reason: 'landed since: asked next');
    engine.debugLose();
    expect(under.pixels, everyElement(7));
    expect(over.pixels, everyElement(7), reason: 'the picture it landed on');
  });

  test('a device that goes while a copy is on its way takes its tiles: each '
      'reads as the picture it landed on, and none is asked again', () async {
    final tile = landed([tileOf(7)], 9).single;

    // Gone between the copy's submit and the wait for it.
    GpuReadout.debugBeforeMapping = engine.debugLose;
    // What the device took is laid by a read here, which asks it nothing.
    EngineTileLedger.debugBeforeRead = null;
    expect(await ledger.copyHereABatch(), isFalse);

    expect(tile.isOnlyOnEngine, isFalse);
    expect(tile.pixels, everyElement(7));
    expect(await ledger.copyHereABatch(), isFalse, reason: 'none to ask');
  });

  // ⛔What the engine refuses with its device still there is no loss: it
  // is thrown on, and no tile is given another picture for it.
  test('a copy refused by a device that is not gone is refused — read no '
      'other way, and asked for again by the next batch', () async {
    final tile = landed([tileOf(7)], 9).single;
    // Let go behind the ledger: the pool refuses a read of a slot not held.
    expect(ledger.pool.release(ledger.slotOf(tile)!), isTrue);

    await expectLater(
      ledger.copyHereABatch(),
      throwsA(isA<GpuReadFailed>()),
    );

    expect(tile.isOnlyOnEngine, isTrue);
    await expectLater(
      ledger.copyHereABatch(),
      throwsA(isA<GpuReadFailed>()),
      reason: 'not left on its way',
    );
  });
}
