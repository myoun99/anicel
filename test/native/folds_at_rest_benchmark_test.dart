@Tags(['benchmark'])
library;

// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';

/// What the folds at rest cost the isolate that asks for them
/// (`EngineTileLedger.foldABatch`), timed: FOLDS tiles (512) of a drawn
/// line each — a few colours a block, as a cel's are — folded a batch
/// behind another as a rest does. 🗣️관제 2026-11-12
/// (a-lost-gpu-device-keeps-the-unsaved-tiles), of work at rest: 「「어느
/// 스레드가 몇 ms 를 기다리는가」로 재서 … 착지 줄에 적는다」.
///
/// Prints FOLDREST lines, each time a median (and the most):
///
/// - `batches`: what a batch's call held this isolate for before its wait
///   (`ask`) and how long the batch took to be folded and settled
///   (`wall`); the pool's bytes before and after (`pool`); and this
///   isolate's turns while the batches went (`turns`) beside as long with
///   nothing going (`idle`) — a turn is what a frame and a press wait for.
/// - `read`: the same tiles read back a batch at a time, as they lay
///   before the folds (`as it is`) and folded (`folded`): what a read by
///   name pays for the unfold.
void main() {
  test('folds at rest: what this isolate is held for', () async {
    // A page with a slot free is the pool's room, none of whose tiles is
    // a fold's (rust/src/kernels/pool/folded.rs): FOLDS fills its pages,
    // of 2,048 tiles where a binding of the device holds 128 MiB.
    final count = int.parse(Platform.environment['FOLDS'] ?? '2048');
    final engine = GpuEngine.onFirstAdapter();
    addTearDown(engine.close);
    final kernels = GpuFold(engine);
    addTearDown(kernels.free);
    final ledger = EngineTileLedger(engine, foldKernels: () => kernels);
    const batch = EngineTileLedger.foldBatch;

    /// A tile of a line drawn across it, [seed]'s: two colours where the
    /// line goes through a block, none elsewhere.
    BitmapTile drawn(int seed) => BitmapTile.written(
      size: gpuTileSide,
      write: (pixels) {
        for (var y = 0; y < gpuTileSide; y++) {
          final x = (y * (3 + seed % 5) ~/ 4 + seed * 7) % gpuTileSide;
          for (var wide = 0; wide < 3 && x + wide < gpuTileSide; wide++) {
            final at = (y * gpuTileSide + x + wide) * 4;
            pixels[at] = 20 + seed % 200;
            pixels[at + 3] = wide == 1 ? 255 : 128;
          }
        }
      },
    );

    final tiles = [for (var seed = 0; seed < count; seed++) drawn(seed)];
    for (final some in tiles.slices(64)) {
      ledger.held((hold) => hold.slotsOf(EngineTileLedger.landedCel, some));
    }
    await engine.done();
    expect(
      ledger.pool.bytes,
      count * gpuTileBytes,
      reason: '⛔premise: FOLDS fills the pool\'s pages, each full',
    );

    String ms(int micros) => (micros / 1000).toStringAsFixed(2);
    String of(List<int> micros) {
      final sorted = micros.sorted((a, b) => a.compareTo(b));
      return '${ms(sorted[sorted.length ~/ 2])}ms(max ${ms(sorted.last)})';
    }

    /// Each gap between two turns of this isolate till [done].
    Future<List<int>> turnsTill(Future<void> done) async {
      var going = true;
      unawaited(done.whenComplete(() => going = false));
      final turns = <int>[];
      final watch = Stopwatch()..start();
      while (going) {
        final from = watch.elapsedMicroseconds;
        await Future<void>.delayed(Duration.zero);
        turns.add(watch.elapsedMicroseconds - from);
      }
      return turns;
    }

    String turnsOf(List<int> turns) =>
        '${of(turns)} '
        'over8ms=${turns.where((turn) => turn > 8000).length}/${turns.length}';

    /// The tiles read back by their names, a batch a read.
    List<int> readBack() {
      final reads = <int>[];
      for (final asked in tiles.slices(batch)) {
        final watch = Stopwatch()..start();
        ledger.held(
          (hold) => ledger.pool.readout(
            hold.slotsOf(EngineTileLedger.landedCel, asked),
          )
            ..map()
            ..free(),
        );
        reads.add(watch.elapsedMicroseconds);
      }
      return reads;
    }

    final asItIs = readBack();
    final before = ledger.pool.bytes;
    final asks = <int>[];
    final walls = <int>[];
    Future<void> batches() async {
      var more = true;
      while (more) {
        final watch = Stopwatch()..start();
        final onItsWay = ledger.foldABatch();
        asks.add(watch.elapsedMicroseconds);
        more = await onItsWay;
        walls.add(watch.elapsedMicroseconds);
      }
    }

    final all = Stopwatch()..start();
    final turns = await turnsTill(batches());
    all.stop();
    await engine.done();
    final idle = await turnsTill(Future<void>.delayed(all.elapsed));
    const mb = 1024 * 1024;
    print(
      'FOLDREST batches tiles=${tiles.length} batch=$batch n=${walls.length} '
      'ask=${of(asks)} wall=${of(walls)} all=${all.elapsedMilliseconds}ms '
      'pool=${before ~/ mb}→${ledger.pool.bytes ~/ mb}MiB',
    );
    print('FOLDREST batches turns=${turnsOf(turns)}');
    print('FOLDREST batches idle=${turnsOf(idle)}');
    expect(ledger.pool.bytes, lessThan(before), reason: 'none folded');

    final folded = readBack();
    print(
      'FOLDREST read batch=$batch n=${folded.length} '
      'as it is=${of(asItIs)} folded=${of(folded)}',
    );
  });
}
