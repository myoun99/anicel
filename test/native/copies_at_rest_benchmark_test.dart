@Tags(['benchmark'])
library;

// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';

import '../helpers/tiles_on_the_engine.dart';

/// What the copies at rest cost the isolate that asks for them
/// (`EngineTileLedger.copyHereABatch`), timed: COPIES tiles (512) the
/// engine alone holds, copied a batch behind another as a rest does —
/// 🗣️관제 2026-11-12 (a-lost-gpu-device-keeps-the-unsaved-tiles): 「「어느
/// 스레드가 몇 ms 를 기다리는가」로 재서 (B) 착지 줄에 적는다」.
///
/// Prints COPYREST lines, each time a median (and the most):
///
/// - `batches`: what a batch's call held this isolate for before its wait
///   (`ask`) and how long the batch took to come (`wall`); and this
///   isolate's turns while the batches went (`turns`) beside as long with
///   nothing going (`idle`) — a turn is what a frame and a press wait for.
/// - `pieces`: a batch's parts, each alone on this isolate — its tiles
///   submitted (`submit`), the GPU waited for (`wait`: the part the
///   engine's thread takes), their rows copied out (`rows`) and kept by
///   their tiles (`keep`).
/// - `here`: the same tiles read on this isolate, a batch a read — what a
///   rest's copy was till 2026-11-12.
void main() {
  test('copies at rest: what this isolate is held for', () async {
    final count = int.parse(Platform.environment['COPIES'] ?? '512');
    final engine = GpuEngine.onFirstAdapter();
    addTearDown(engine.close);
    final ledger = EngineTileLedger(engine);
    const cel = (1, 1);
    const batch = EngineTileLedger.copyBatch;
    final block = malloc<Uint8>(batch * gpuTileBytes);
    addTearDown(() => malloc.free(block));

    List<BitmapTile> landed() => [
      for (var at = 0; at < count; at += 64)
        ...landedOn(ledger, cel, List.filled(64, null), 9),
    ];

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

    for (final round in ['first', 'again']) {
      final tiles = landed();
      final asks = <int>[];
      final walls = <int>[];
      Future<void> batches() async {
        var more = true;
        while (more) {
          final watch = Stopwatch()..start();
          final onItsWay = ledger.copyHereABatch();
          asks.add(watch.elapsedMicroseconds);
          more = await onItsWay;
          walls.add(watch.elapsedMicroseconds);
        }
      }

      final all = Stopwatch()..start();
      final turns = await turnsTill(batches());
      all.stop();
      expect(tiles.where((tile) => tile.isOnlyOnEngine), isEmpty);
      final idle = await turnsTill(Future<void>.delayed(all.elapsed));
      print(
        'COPYREST batches $round tiles=${tiles.length} batch=$batch '
        'n=${walls.length} ask=${of(asks)} wall=${of(walls)} '
        'all=${all.elapsedMilliseconds}ms',
      );
      print('COPYREST batches $round turns=${turnsOf(turns)}');
      print('COPYREST batches $round idle=${turnsOf(idle)}');
    }

    final submits = <int>[];
    final waits = <int>[];
    final rows = <int>[];
    final keeps = <int>[];
    for (final asked in landed().slices(batch)) {
      final watch = Stopwatch()..start();
      final readout = ledger.held(
        (hold) => ledger.pool.readout(
          hold.slotsOf(EngineTileLedger.landedCel, asked),
        ),
      );
      submits.add(watch.elapsedMicroseconds);
      watch.reset();
      readout.map();
      waits.add(watch.elapsedMicroseconds);
      watch.reset();
      readout.rows(
        block,
        offset: 0,
        stride: gpuTileBytes,
        rowBytes: gpuTileBytes,
        rows: asked.length,
        dstStride: gpuTileBytes,
      );
      rows.add(watch.elapsedMicroseconds);
      readout.free();
      final bytes = block.asTypedList(asked.length * gpuTileBytes);
      watch.reset();
      for (final (at, tile) in asked.indexed) {
        final from = at * gpuTileBytes;
        tile.keepBytesHere(
          Uint8List.sublistView(bytes, from, from + gpuTileBytes),
        );
      }
      keeps.add(watch.elapsedMicroseconds);
    }
    print(
      'COPYREST pieces batch=$batch n=${submits.length} '
      'submit=${of(submits)} wait=${of(waits)} rows=${of(rows)} '
      'keep=${of(keeps)}',
    );

    final here = <int>[];
    for (final asked in landed().slices(batch)) {
      final watch = Stopwatch()..start();
      ledger.read(cel, asked, block);
      here.add(watch.elapsedMicroseconds);
    }
    print('COPYREST here batch=$batch n=${here.length} read=${of(here)}');
  });
}
