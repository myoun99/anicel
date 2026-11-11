import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';

import '../helpers/tiles_on_the_engine.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에 사본을 두고 앱을
/// 유지한다」 — a device the driver takes away takes every tile on it, and
/// what is lost with it is what landed since the last copy came here: a
/// tile whose copy is here reads as itself, and one whose copy had not come
/// reads as the tile it landed on (`EngineTileLedger`).
///
/// On an engine and a ledger of the test's own: a device that is gone is
/// gone for its process, and the app has one.
void main() {
  late GpuEngine engine;
  late EngineTileLedger ledger;

  setUp(() {
    engine = GpuEngine.onFirstAdapter();
    ledger = EngineTileLedger(engine);
  });
  // ⚠️The ledger's pool is not freed with its test: a tile collected after
  // it lets its slot go there (the ledger's finalizer), in a later test.
  tearDown(() => engine.close());

  // A cel, by the name a painter gives one.
  const cel = (1, 1);

  /// A tile of [value] at every byte, its bytes here.
  BitmapTile tileOf(int value) => BitmapTile(
    size: gpuTileSide,
    pixels: Uint8List(gpuTileBytes)..fillRange(0, gpuTileBytes, value),
  );

  List<BitmapTile> landed(List<BitmapTile?> unders, int value) =>
      landedOn(ledger, cel, unders, value);

  test('its device gone before its copy came, a tile reads as the tile it '
      'landed on — as nothing where it landed on none — and forgets what '
      'its maker said of its ink', () {
    final [onATile, onNone, read] = landed([tileOf(7), null, null], 9);
    expect(read.pixels, everyElement(9), reason: '⛔premise: what landed');
    expect(onATile.isOnlyOnEngine, isTrue, reason: '⛔premise: no copy here');
    expect(onNone.hasInk, isTrue, reason: '⛔premise: as its maker said');
    const said = (left: 1, top: 2, rightExclusive: 3, bottomExclusive: 4);
    onATile.rememberInkBounds(said);
    expect(onATile.inkBounds, said, reason: '⛔premise: as its maker said');

    engine.debugLose();

    expect(onATile.pixels, everyElement(7));
    expect(onNone.pixels, everyElement(0));
    expect(onNone.hasInk, isFalse);
    expect(onATile.hasInk, isTrue);
    expect(onATile.inkBounds, tileOf(7).inkBounds);
    expect(read.pixels, everyElement(9), reason: 'its bytes were here');
  });

  test('a tile that landed on one whose own copy had not come reads as the '
      'last picture under it that is here', () {
    final first = landed([tileOf(7)], 8).single;
    final second = landed([first], 9).single;

    engine.debugLose();

    expect(second.pixels, everyElement(7));
    expect(first.pixels, everyElement(7));
  });

  test('a copy is a batch of the oldest tiles the engine alone holds, '
      'their slots kept — and a tile whose copy is here reads as itself '
      'once the device is gone', () {
    const batch = EngineTileLedger.copyBatch;
    final tiles = landed(List.filled(batch + 1, null), 9);
    final slots = [for (final tile in tiles) ledger.slotOf(tile)];

    expect(ledger.copyHereABatch(), isTrue, reason: 'one is left');
    expect(
      [for (final tile in tiles) tile.isOnlyOnEngine],
      [...List.filled(batch, false), true],
      reason: 'the oldest, a batch of them',
    );
    expect(ledger.copyHereABatch(), isFalse, reason: 'none is left');
    expect(tiles.last.isOnlyOnEngine, isFalse);
    expect([for (final tile in tiles) ledger.slotOf(tile)], slots);
    expect(ledger.copyHereABatch(), isFalse, reason: 'nothing to copy');

    engine.debugLose();

    expect(tiles.first.pixels, everyElement(9));
    expect(tiles.last.pixels, everyElement(9));
  });

  test('a copy asked for once the device is gone gives each tile the '
      'picture it landed on', () {
    final tile = landed([tileOf(7)], 9).single;

    engine.debugLose();
    expect(ledger.copyHereABatch(), isFalse);

    expect(tile.isOnlyOnEngine, isFalse);
    expect(tile.pixels, everyElement(7));
  });

  // What a save, a cel cooled and an undo record parked ask.
  test('a read of many gives each tile its bytes in order once the device '
      'is gone: its own where they are here, else the picture under it', () {
    final copied = landed([tileOf(1)], 2).single;
    ledger.copyHereABatch();
    final lost = landed([tileOf(3)], 4).single;
    final here = tileOf(5);
    final asked = [lost, here, copied];
    final into = calloc<Uint8>(asked.length * gpuTileBytes);
    addTearDown(() => calloc.free(into));

    engine.debugLose();
    ledger.read(cel, asked, into);

    final bytes = into.asTypedList(asked.length * gpuTileBytes);
    expect(
      [for (var at = 0; at < asked.length; at++) bytes[at * gpuTileBytes]],
      [3, 5, 2],
    );
    expect(bytes.toSet(), {3, 5, 2});
  });

  // ⛔What the engine refuses with its device still there is no loss: it
  // is thrown on, as it was (a_read_the_engine_refuses_changes_no_file).
  test('a read refused by a device that is not gone is still refused — of '
      'one tile and of many', () {
    final tile = landed([tileOf(7)], 9).single;
    // Let go behind the ledger: the pool refuses a read of a slot not held.
    expect(ledger.pool.release(ledger.slotOf(tile)!), isTrue);
    final into = calloc<Uint8>(gpuTileBytes);
    addTearDown(() => calloc.free(into));

    expect(() => tile.pixels, throwsA(isA<GpuReadFailed>()));
    expect(
      () => ledger.read(cel, [tile], into),
      throwsA(isA<GpuReadFailed>()),
    );
    expect(tile.isOnlyOnEngine, isTrue);
  });

  testWidgets('a landing asks for the copies once the hand has rested, and '
      'a landing meanwhile puts them off', (tester) async {
    EngineTileLedger.copiesAtRest = true;
    addTearDown(() => EngineTileLedger.copiesAtRest = false);
    const rest = EngineTileLedger.rest;
    const tick = Duration(milliseconds: 1);
    const batch = EngineTileLedger.copyBatch;

    final first = landed(List.filled(batch + 1, null), 9);
    await tester.pump(rest - tick);
    expect(first.first.isOnlyOnEngine, isTrue, reason: 'not rested yet');

    final second = landed([null], 9).single;
    await tester.pump(rest - tick);
    expect(first.first.isOnlyOnEngine, isTrue, reason: 'put off');

    await tester.pump(tick);
    expect(
      [...first, second].where((tile) => tile.isOnlyOnEngine),
      isEmpty,
      reason: 'every batch, a turn after the last',
    );
  });

  testWidgets('no landing asks for copies where no launch said so', (
    tester,
  ) async {
    final tile = landed([null], 9).single;
    await tester.pump(EngineTileLedger.rest);
    expect(tile.isOnlyOnEngine, isTrue);
  });

  test('a launch says so before its first frame', () {
    final launch = File('lib/main.dart').readAsStringSync();
    final said = launch.indexOf('EngineTileLedger.copiesAtRest = true;');
    expect(said, isNonNegative);
    expect(said, lessThan(launch.indexOf('runApp(')));
  });
}
