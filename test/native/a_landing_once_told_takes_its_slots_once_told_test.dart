// The first landing compiles the stamp's kernels and the pool's: tens of
// seconds on a machine this busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';

import '../helpers/poll_until.dart';
import '../helpers/settle_async.dart';

/// 🚨A LANDING FINISHED WITH NO WAIT TAKES ITS SLOTS ONCE IT IS TOLD (card
/// opening-a-transform-box-holds-the-ui-over-half-a-second, 2026-11-20):
/// [EngineTileLedger.landOnceTold] asks the engine what a landing makes of
/// its tiles, and gives the inked their slots when the GPU has said which
/// they are — as a waited landing leaves them ([EngineTileLedger.land]), a
/// full pool's room made as a store's is, and the caller told where the
/// tiles were not put after all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final side = gpuTileSide;
  const tall = 4;

  /// A picture [columns] tiles wide and [tall] pixels high, opaque, each
  /// tile's width of it a red of its own ([redOf]).
  GpuStampPicture strip(int columns, int seed) {
    final width = columns * side;
    final rgba = Uint8List(width * tall * 4);
    for (var at = 0; at < width * tall; at++) {
      rgba
        ..[at * 4] = redOf(at % width ~/ side, seed)
        ..[at * 4 + 3] = 255;
    }
    return GpuStampPicture(appGpuEngine, rgba, width, tall);
  }

  /// [columns] tiles of [row] asked, over nothing.
  List<TileAsk> rowOf(int row, int columns) => [
    for (var column = 0; column < columns; column++)
      (column: column, row: row, under: null),
  ];

  /// Where a strip [columns] tiles wide lies on [row].
  (int, int, int, int) lieOf(int row, int columns) =>
      (0, row * side, columns * side, row * side + tall);

  /// [picture], [columns] tiles wide, finished on [row] with no wait.
  FinishedBy finishes(GpuStampPicture picture, int row, int columns) =>
      (pool, asked) => appGpuStampLanding.finished(
        appGpuComposite,
        pool,
        picture,
        left: 0,
        top: row * side,
        within: lieOf(row, columns),
        asks: asked,
        mode: GpuBlend.normal,
      );

  /// [picture], [columns] tiles wide, landed on [row], waited for.
  LandedBy lands(GpuStampPicture picture, int row, int columns) =>
      (pool, cel, asked) => appGpuStampLanding.land(
        appGpuComposite,
        pool,
        cel,
        picture,
        left: 0,
        top: row * side,
        within: lieOf(row, columns),
        asks: asked,
        mode: GpuBlend.normal,
      );

  /// The red of [tile]'s first pixel: which tile's width of a strip it is.
  int? firstRedOf(BitmapTile? tile) =>
      tile?.readPixels((_, pixels) => pixels[0]);

  test('what it is told lands as a waited landing leaves it: a tile of its '
      'own for each inked, none for the rest, their ink known', () async {
    final ledger = EngineTileLedger(appGpuEngine);
    final picture = strip(2, 1);
    final kept = GpuFinished.debugKept;
    var unput = 0;

    // Three tiles asked, the picture over two of them.
    final told = await patiently(
      ledger.landOnceTold(
        rowOf(0, 3),
        by: finishes(picture, 0, 2),
        unput: () => unput += 1,
      ),
    );
    final slots = ledger.slotCount;
    final waited = ledger.land(
      rowOf(1, 3),
      by: lands(picture, 1, 2),
      ofTheHand: true,
      compared: true,
    );

    expect([for (final one in told) one.change], [
      GpuChange.inked,
      GpuChange.inked,
      GpuChange.same,
    ]);
    expect(
      [for (final one in told) one.change],
      [for (final one in waited) one.change],
      reason: '⛔premise: what a waited landing says of the same',
    );
    expect(slots, 2, reason: 'a slot for each inked, and for no other');
    expect(
      GpuFinished.debugKept,
      kept,
      reason: 'what was finished is freed once its tiles are on their way',
    );
    expect(told.last.tile, isNull);
    final reads = ledger.debugTileReads;
    for (final (change: _, :tile) in told.take(2)) {
      expect(tile!.isOnlyOnEngine, isTrue, reason: 'the engine\'s alone');
      expect(tile.hasInk, isTrue, reason: 'its ink known');
    }
    expect(ledger.debugTileReads, reads, reason: 'and no byte read for it');
    for (final (at, (change: _, :tile)) in told.take(2).indexed) {
      expect(firstRedOf(tile), redOf(at, 1));
      expect(firstRedOf(tile), firstRedOf(waited[at].tile));
    }
    await patiently(appGpuEngine.done());
    expect(unput, 0, reason: 'every tile told was put');
  });

  test('🚨told with the pool full at the next slot, it has room made as a '
      'store has and lands the rest from where it stopped', () async {
    final ledger = EngineTileLedger(
      appGpuEngine,
      byteBudget: 0,
      roomBatch: 1,
      debugTilesAPage: 4,
    );
    // Three of the four slots of what lands' one page taken.
    final before = ledger.land(
      rowOf(1, 3),
      by: lands(strip(3, 2), 1, 3),
      ofTheHand: true,
      compared: true,
    );
    expect(
      ledger.pool.bytes,
      4 * gpuTileBytes,
      reason: '⛔premise: a page of four, one slot free',
    );

    final told = await patiently(
      ledger.landOnceTold(
        rowOf(0, 3),
        by: finishes(strip(3, 1), 0, 3),
        unput: () => fail('put, every one'),
      ),
    );

    expect(
      ledger.pool.bytes,
      8 * gpuTileBytes,
      reason: 'a page past the budget for what a call lands',
    );
    expect(ledger.slotCount, 6);
    expect(
      [for (final one in told) firstRedOf(one.tile)],
      [for (var at = 0; at < 3; at++) redOf(at, 1)],
      reason: 'each tile its own width of the strip, in the order asked',
    );
    expect(
      [for (final one in before) firstRedOf(one.tile)],
      [for (var at = 0; at < 3; at++) redOf(at, 2)],
      reason: 'and no slot of the ones before it written over',
    );
  });

  testWidgets('a landing once told asks for the copies once the hand has '
      'rested, as a waited one does', (tester) async {
    EngineTileLedger.copiesAtRest = true;
    addTearDown(() => EngineTileLedger.copiesAtRest = false);
    final ledger = EngineTileLedger.instance;

    final told = await tester.runAsync(
      () => patiently(
        ledger.landOnceTold(
          rowOf(0, 1),
          by: finishes(strip(1, 1), 0, 1),
          unput: () {},
        ),
      ),
    );
    final tile = told!.single.tile!;

    expect(tile.isOnlyOnEngine, isTrue, reason: '⛔premise: not copied yet');
    expect(
      await settleAsync(tester, () => !tile.isOnlyOnEngine),
      isTrue,
      reason: 'its copy came once the hand had rested',
    );
  });

  testWidgets('🚨a landing once told is no hand\'s: it puts no fold off, '
      'and the folds are asked for a rest after the first', (tester) async {
    EngineTileLedger.foldsAtRest = true;
    addTearDown(() => EngineTileLedger.foldsAtRest = false);
    final answered = _Answered(appGpuEngine);
    final beat = EngineTileLedger.rest ~/ 5;
    final picture = strip(1, 1);
    final kept = <LandedTile>[];

    /// A landing told on [row] — asked on the pumped clock, which stands
    /// while the GPU says what it made: the rest it asks for is counted
    /// from where the clock stood.
    Future<void> aLandingTold(int row) async {
      var told = false;
      unawaited(
        answered
            .landOnceTold(
              rowOf(row, 1),
              by: finishes(picture, row, 1),
              unput: () {},
            )
            .then((landed) {
              kept.addAll(landed);
              told = true;
            }),
      );
      expect(await settleAsync(tester, () => told), isTrue);
    }

    for (var row = 0; row < 4; row++) {
      await aLandingTold(row);
      await tester.pump(beat);
    }
    expect(answered.asked, isEmpty, reason: 'a rest is five beats');

    await aLandingTold(4);
    await tester.pump(beat);

    expect(answered.asked, hasLength(1));
    // No timer is left behind: what is asked is told there is none left.
    EngineTileLedger.foldsAtRest = false;
    for (final batch in answered.asked) {
      batch.complete(false);
    }
    await tester.pump(EngineTileLedger.rest * 2);
    expect(kept, hasLength(5));
  });

  test('a landing that was not finished fails as the engine refuses it, and '
      'takes no slot', () async {
    final ledger = EngineTileLedger(appGpuEngine);

    await expectLater(
      ledger.landOnceTold(
        rowOf(0, 1),
        by: (pool, asked) => Future.error(GpuRefused('not finished')),
        unput: () => fail('nothing was put'),
      ),
      throwsA(isA<GpuRefused>()),
    );
    expect(ledger.slotCount, 0);
  });

  // ⚠️Last: a device that is gone is gone for its process.
  test('🚨tiles the engine did not put after all are told unput', () async {
    final ledger = EngineTileLedger(appGpuEngine);
    final finish = finishes(strip(1, 1), 0, 1);
    var unput = 0;

    final told = await patiently(
      ledger.landOnceTold(
        rowOf(0, 1),
        by: (pool, asked) async {
          final finished = await finish(pool, asked);
          // Gone once the landing is told, before its tiles are put — at
          // once, as wgpu says it of a device it gave up for want of
          // memory.
          appGpuEngine.debugLose(forMemory: true);
          return finished;
        },
        unput: () => unput += 1,
      ),
    );

    expect(
      told.single.change,
      GpuChange.inked,
      reason: '⛔premise: told before the device went',
    );
    expect(
      await pollUntil(() => unput > 0),
      isTrue,
      reason: 'the engine tells what it did not put',
    );
    expect(unput, 1);
  });
}

/// The red of the [column]th tile's width of a strip made by [seed].
int redOf(int column, int seed) => 40 + 50 * column + seed;

/// A ledger whose folds a test answers: each batch a rest asks for waits
/// for its word, and folds nothing.
class _Answered extends EngineTileLedger {
  _Answered(super.engine);

  final asked = <Completer<bool>>[];

  @override
  Future<bool> foldABatch() {
    final batch = Completer<bool>();
    asked.add(batch);
    return batch.future;
  }
}
