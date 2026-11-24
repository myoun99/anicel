// The first told compiles the compare kernel: tens of seconds on a machine
// this busy.
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';

import '../helpers/poll_until.dart';
import '../helpers/tiles_on_the_engine.dart';

/// 🚨A TILE HANDED OVER IS TOLD ITS INK, WITH NO WAIT (관제 2026-11-24, card
/// the-start-of-every-stroke-stalls-on-the-galaxy-tab ③-2): pen-up hands the
/// cel the tiles a stroke's steps landed on their way, uncompared, and
/// [EngineTileLedger.toldOf] asks the GPU what each is beside the tile it
/// landed on. Till it is told, a tile shows what its stroke showed its cel
/// under the pen ([BitmapTile.showsInkNow]) — a painting stroke's ink, an
/// erasing stroke's what the tile under it showed (F-482) —, and says it
/// does not know ([BitmapTile.inkWithNoWait]); once told it knows — and
/// nothing of it was read here for either.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A tile of [value] at every byte, its bytes here.
  BitmapTile drawn(int value) => BitmapTile.written(
    size: gpuTileSide,
    write: (pixels) => pixels.fillRange(0, gpuTileBytes, value),
  );

  /// A tile of [value] landed by [ledger] on each of [unders], uncompared —
  /// as a stroke's step lands it on its way —, from column [from].
  List<({BitmapTile tile, int column, int row})> onItsWay(
    EngineTileLedger ledger,
    List<BitmapTile?> unders,
    int value, {
    int from = 0,
  }) {
    final landed = ledger.land(
      [
        for (final (at, under) in unders.indexed)
          (column: from + at, row: 0, under: under),
      ],
      by: tilesOf(value),
      ofTheHand: true,
    );
    return [
      for (final (at, one) in landed.indexed)
        (tile: one.tile!, column: from + at, row: 0),
    ];
  }

  test('each tile is told what the GPU says of it beside the tile it landed '
      'on, and shows ink till then — nothing read here', () async {
    final ledger = EngineTileLedger(appGpuEngine);
    final stroke = GpuStroke(appGpuEngine);
    addTearDown(stroke.free);
    final under = drawn(200);
    // Ink over ink the same, ink over nothing, nothing over ink, nothing
    // over nothing.
    final tiles = [
      ...onItsWay(ledger, [under, null], 200),
      ...onItsWay(ledger, [under, null], 0, from: 2),
    ];
    final reads = ledger.debugTileReads;
    expect(
      [for (final (:tile, column: _, row: _) in tiles) tile.inkWithNoWait],
      everyElement(isNull),
      reason: '⛔premise: landed on its way, its ink is not known',
    );

    final told = ledger.toldOf(tiles, by: stroke.toldOf, erases: false);
    expect(
      [for (final (:tile, column: _, row: _) in tiles) tile.showsInkNow],
      everyElement(isTrue),
      reason: 'till told, each shows ink, as the stroke showed its cel drawn',
    );
    expect(
      [for (final (:tile, column: _, row: _) in tiles) tile.inkWithNoWait],
      everyElement(isNull),
      reason: 'and says it does not know',
    );
    expect(
      [for (final (:tile, column: _, row: _) in tiles) tile.inkTold],
      everyElement(isNotNull),
      reason: 'what it waits on is there to wait on',
    );

    await patiently(told);
    expect(
      [for (final (:tile, column: _, row: _) in tiles) tile.inkWithNoWait],
      [true, true, false, false],
      reason: 'once told, each knows its ink',
    );
    expect(
      [for (final (:tile, column: _, row: _) in tiles) tile.inkTold],
      everyElement(isNull),
    );
    expect(ledger.debugTileReads, reads, reason: 'no byte read for any');
    expect(
      [
        for (final (:tile, column: _, row: _) in tiles)
          tile.readPixels((_, pixels) => pixels.any((byte) => byte != 0)),
      ],
      [true, true, false, false],
      reason: '⛔what it was told is what its pixels hold',
    );
  });

  test("an erasing stroke's tile shows, till told, what the tile it landed "
      'on showed — an eraser adds no ink (F-482) — and is told as any is',
      () async {
    final ledger = EngineTileLedger(appGpuEngine);
    final stroke = GpuStroke(appGpuEngine);
    addTearDown(stroke.free);
    // Over ink, over nothing, over a tile with none; and over one still to
    // be told, of a painting stroke.
    final [painted] = onItsWay(ledger, [null], 200, from: 3);
    final paintedTold = ledger.toldOf(
      [painted],
      by: stroke.toldOf,
      erases: false,
    );
    final tiles = onItsWay(ledger, [
      drawn(200),
      null,
      drawn(0),
      painted.tile,
    ], 0);
    expect(
      [for (final (:tile, column: _, row: _) in tiles) tile.inkWithNoWait],
      everyElement(isNull),
      reason: '⛔premise: landed on its way, its ink is not known',
    );

    final told = ledger.toldOf(tiles, by: stroke.toldOf, erases: true);
    expect(
      [for (final (:tile, column: _, row: _) in tiles) tile.showsInkNow],
      [true, false, false, true],
      reason: 'till told, each shows what the tile under it showed',
    );
    expect(
      [for (final (:tile, column: _, row: _) in tiles) tile.inkTold],
      everyElement(isNotNull),
      reason: 'and is told all the same',
    );

    await patiently(Future.wait([told, paintedTold]));
    expect(
      [for (final (:tile, column: _, row: _) in tiles) tile.inkWithNoWait],
      everyElement(isFalse),
      reason: 'once told, each knows it holds none',
    );
  });

  test('a told the GPU refuses leaves the ink not known, and a tile whose '
      'bytes are here is not asked', () async {
    final ledger = EngineTileLedger(appGpuEngine);
    final [handed] = onItsWay(ledger, [null], 200);
    final here = drawn(200);
    var asked = 0;

    await patiently(
      ledger.toldOf(
        [handed, (tile: here, column: 1, row: 0)],
        by: (pool, tiles) {
          asked = tiles.length;
          throw GpuRefused('the device went');
        },
        erases: false,
      ),
    );

    expect(asked, 1, reason: 'the tile whose bytes are here is not asked');
    expect(handed.tile.inkWithNoWait, isNull, reason: 'refused, not known');
    expect(handed.tile.inkTold, isNull, reason: 'and nothing waits on it');
    expect(
      handed.tile.showsInkNow,
      isTrue,
      reason: 'a tile whose ink is not known asks its pixels',
    );
  });

  test('a tile told already is not to be told again — nothing waits on it '
      '— and one whose ink is forgotten shows what its pixels hold, not '
      "its stroke's word", () async {
    final ledger = EngineTileLedger(appGpuEngine);
    final stroke = GpuStroke(appGpuEngine);
    addTearDown(stroke.free);
    final [told] = onItsWay(ledger, [null], 200);
    await patiently(ledger.toldOf([told], by: stroke.toldOf, erases: false));
    expect(told.tile.inkWithNoWait, isTrue, reason: '⛔premise: told');

    final again = ledger.toldOf([told], by: stroke.toldOf, erases: true);
    expect(told.tile.inkTold, isNull, reason: 'known, it waits on nothing');
    expect(told.tile.showsInkNow, isTrue, reason: 'and shows what it knows');
    await patiently(again);

    // Painted, with no ink left: its stroke's word is ink till told.
    final [forgotten] = onItsWay(ledger, [null], 0, from: 1);
    final pending = ledger.toldOf(
      [forgotten],
      by: stroke.toldOf,
      erases: false,
    );
    expect(forgotten.tile.showsInkNow, isTrue, reason: '⛔premise: the word');
    forgotten.tile.forgetInk();
    expect(forgotten.tile.inkTold, isNull, reason: 'forgotten with the rest');
    expect(
      forgotten.tile.showsInkNow,
      isFalse,
      reason: 'what was said of it was said of the pixels that went',
    );
    await patiently(pending);
  });
}
