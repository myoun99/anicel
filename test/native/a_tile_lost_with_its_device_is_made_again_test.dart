import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';

import '../helpers/the_apps_engine_let_go.dart';
import '../helpers/tiles_on_the_engine.dart';

// A cel, by the name a painter gives one.
const _cel = (1, 1);

/// A landing that lays, over each tile asked, a tile of [add] more than the
/// byte under it — on [on]'s ledger, asked at each making: the one of the
/// engine that stands then — and keeps what it was asked to make again.
final class _Adds implements LandsAgain {
  _Adds(this.add, this.on);

  final int add;
  final EngineTileLedger Function() on;
  final List<List<TileAsk>> asked = [];

  /// Every tile made again, kept: its slot stays while the test counts.
  final List<BitmapTile> made = [];

  @override
  List<LandedTile> again(List<TileAsk> asks) {
    asked.add(asks);
    final tiles = [
      for (final ask in asks)
        landedOn(on(), _cel, [
          ask.under,
        ], (ask.under?.pixels.first ?? 0) + add).single,
    ];
    made.addAll(tiles);
    return [for (final tile in tiles) (change: GpuChange.inked, tile: tile)];
  }
}

/// A landing made again on an engine whose device is gone in its turn.
final class _Refused implements LandsAgain {
  int asked = 0;

  @override
  List<LandedTile> again(List<TileAsk> asks) {
    asked += 1;
    throw GpuRefused('the device is gone');
  }
}

/// A landing that, made again, leaves each tile as the one under it.
final class _LeavesAsItWas implements LandsAgain {
  @override
  List<LandedTile> again(List<TileAsk> asks) => [
    for (final _ in asks) (change: GpuChange.same, tile: null),
  ];
}

/// 🗣️유저 2026-11-19 (cel-originals-are-held-twice-in-ram-and-on-the-gpu-Q2):
/// 「픽셀 대신 「한 일의 기록」을 들고, 잃으면 다시 그린다」 — a tile whose
/// device went before its copy came, and whose landing said how it is made
/// (`LandsAgain`), reads as itself: that landing made once more, over the
/// tile it landed on, on the engine that stands then (`EngineTileLedger`).
/// With no such word it reads as the tile it landed on
/// (a_tile_lost_with_its_device_reads_as_what_it_landed_on_test.dart).
///
/// On engines and ledgers of the test's own — the one that goes, and the
/// one a landing is made again on — but where the law reads which ledger
/// is the app's: those are the last, and each loses the app's engine.
void main() {
  late GpuEngine engine;
  late EngineTileLedger ledger;
  late GpuEngine nextEngine;
  late EngineTileLedger next;

  setUp(() {
    engine = GpuEngine.onFirstAdapter();
    ledger = EngineTileLedger(engine);
    nextEngine = GpuEngine.onFirstAdapter();
    next = EngineTileLedger(nextEngine);
  });
  // ⚠️The ledgers' pools are not freed with their test: a tile collected
  // after it lets its slot go there (the ledger's finalizer), in a later
  // test.
  tearDown(() {
    engine.close();
    nextEngine.close();
  });

  /// A tile of [value] at every byte, its bytes here.
  BitmapTile tileOf(int value) => BitmapTile(
    size: gpuTileSide,
    pixels: Uint8List(gpuTileBytes)..fillRange(0, gpuTileBytes, value),
  );

  test('its device gone before its copy came, a tile whose landing said how '
      'it is made reads as itself — that landing made again, of its place '
      'in it and over the tile it landed on — and keeps what its maker '
      'said of its ink', () {
    final adds = _Adds(2, () => next);
    final under = tileOf(7);
    final [first, second] = landedOn(ledger, _cel, [
      under,
      under,
    ], 9, again: adds);
    expect(second.isOnlyOnEngine, isTrue, reason: '⛔premise: no copy here');
    const said = (left: 1, top: 2, rightExclusive: 3, bottomExclusive: 4);
    second.rememberInkBounds(said);

    engine.debugLose();

    expect(second.pixels, everyElement(9));
    expect(adds.asked, hasLength(1));
    final (:column, :row, under: over) = adds.asked.single.single;
    expect((column, row), (1, 0));
    expect(over, same(under));
    expect(second.hasInk, isTrue);
    expect(second.inkBounds, said);
    expect(first.pixels, everyElement(9));
    expect(adds.asked, hasLength(2));
    expect(adds.asked.last.single.column, 0);
  });

  test('a tile that landed on none is made again over none', () {
    final adds = _Adds(2, () => next);
    final tile = landedOn(ledger, _cel, [null], 2, again: adds).single;

    engine.debugLose();

    expect(tile.pixels, everyElement(2));
    expect(adds.asked.single.single.under, isNull);
  });

  test('a tile that landed on one whose own copy had not come is made '
      'again over that one, made again', () {
    final adds = _Adds(2, () => next);
    final first = landedOn(ledger, _cel, [tileOf(7)], 9, again: adds).single;
    final second = landedOn(ledger, _cel, [first], 11, again: adds).single;

    engine.debugLose();

    expect(second.pixels, everyElement(11));
    expect(first.pixels, everyElement(9));
  });

  // 🔬Found by reading, before any run (2026-11-19): a tile made again
  // INSIDE the store that asked for its bytes lands on the ledger that is
  // storing — which stores the tile it lands on then and there —, and the
  // store around it, which had listed that tile as one with no slot, gave
  // it a second.
  for (final (order, named) in [
    ((int a, int b) => [a, b], 'the one it landed on first'),
    ((int a, int b) => [b, a], 'the one it landed on last'),
  ]) {
    test('asked their slots together by the ledger of the next engine — '
        '$named — a lost tile and the lost tile it landed on are each '
        'stored once', () {
      final adds = _Adds(2, () => next);
      final under = tileOf(7);
      final first = landedOn(ledger, _cel, [under], 9, again: adds).single;
      final second = landedOn(ledger, _cel, [first], 11, again: adds).single;
      final both = [first, second];

      engine.debugLose();
      final slots = next.held(
        (hold) => hold.slotsOf(_cel, [for (final at in order(0, 1)) both[at]]),
      );

      expect(slots.toSet(), hasLength(2));
      expect(second.pixels, everyElement(11));
      expect(first.pixels, everyElement(9));
      expect(adds.made, hasLength(2), reason: '⛔premise: both made again');
      // The tile under both, the two, and the two made to read them.
      expect(next.slotCount, 5);
    });
  }

  test('a landing that leaves a tile as it was, made again, gives the bytes '
      'of the tile under it', () {
    final tile = landedOn(ledger, _cel, [
      tileOf(7),
    ], 7, again: _LeavesAsItWas()).single;
    const said = (left: 1, top: 2, rightExclusive: 3, bottomExclusive: 4);
    tile.rememberInkBounds(said);

    engine.debugLose();

    expect(tile.pixels, everyElement(7));
    expect(tile.inkBounds, said, reason: 'made again: nothing is forgotten');
  });

  test('a tile whose copy came keeps how it was made no longer, and is not '
      'made again', () async {
    final adds = _Adds(2, () => next);
    final tile = landedOn(ledger, _cel, [tileOf(7)], 9, again: adds).single;
    expect(ledger.madeBy(tile), same(adds), reason: '⛔premise: kept');

    await ledger.copyHereABatch();
    expect(ledger.madeBy(tile), isNull);
    engine.debugLose();

    expect(tile.pixels, everyElement(9));
    expect(adds.asked, isEmpty);
  });

  test('a tile read here keeps how it was made no longer', () {
    final adds = _Adds(2, () => next);
    final tile = landedOn(ledger, _cel, [tileOf(7)], 9, again: adds).single;

    expect(tile.pixels, everyElement(9));

    expect(ledger.madeBy(tile), isNull);
    expect(adds.asked, isEmpty);
  });

  test('made again on an engine that refuses in its turn, a tile reads as '
      'the tile it landed on, and forgets what its maker said of its ink', () {
    final refused = _Refused();
    final tile = landedOn(ledger, _cel, [tileOf(7)], 9, again: refused).single;
    const said = (left: 1, top: 2, rightExclusive: 3, bottomExclusive: 4);
    tile.rememberInkBounds(said);

    engine.debugLose();

    expect(tile.pixels, everyElement(7));
    expect(refused.asked, 1);
    expect(tile.inkBounds, tileOf(7).inkBounds);
  });

  // ⚠️Last, the two of the app's own engine: a device that is gone is gone
  // for its process, and the test after finds the next engine.
  test('while the app still stands on the engine that is gone there is '
      'nothing to make a tile on: it reads as the tile it landed on', () {
    final adds = _Adds(2, () => fail('made again on the engine that is gone'));
    final tile = landedOn(EngineTileLedger.instance, _cel, [
      tileOf(7),
    ], 9, again: adds).single;

    theAppsEngineLost();
    addTearDown(letTheGoneAppGpuEngineGo);

    expect(tile.pixels, everyElement(7));
    expect(adds.asked, isEmpty);
  });

  test('once the app stands on another engine, a tile of the one it let go '
      'is made again there', () {
    final adds = _Adds(2, () => EngineTileLedger.instance);
    final gone = EngineTileLedger.instance;
    final tile = landedOn(gone, _cel, [tileOf(7)], 9, again: adds).single;

    theAppsEngineLostAndLetGo();

    expect(tile.pixels, everyElement(9));
    expect(adds.asked, hasLength(1));
    expect(EngineTileLedger.instance, isNot(same(gone)));
  });
}
