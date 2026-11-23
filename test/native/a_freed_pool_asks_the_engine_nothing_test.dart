import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';

/// A FREED POOL ASKS THE ENGINE NOTHING (card
/// a-pool-release-aborts-on-an-empty-book): a tile a ledger stored and
/// collected once a test had freed that ledger's pool let its slot go
/// there, the engine read a slot of no book, and the process ended. Each
/// of the pool's verbs, asked after the pool is freed, is refused here
/// before it reaches the engine — the let-go answered as for a slot none
/// holds — and the engine is told of none of them (`GpuPool.debugAsked`).
/// ⚠️A read of freed memory need not crash, so a red here is the ask
/// counted, not the process ended.
void main() {
  late int asked;
  setUp(() {
    asked = 0;
    GpuPool.debugAsked = () => asked += 1;
  });
  tearDown(() => GpuPool.debugAsked = null);

  /// A pool with one tile stored in it, then freed: the tile it held.
  GpuTile storedThenFreed(GpuPool pool) {
    final bytes = calloc<Uint8>(gpuTileBytes);
    addTearDown(() => calloc.free(bytes));
    final tile = pool.store(pool.cel(), [bytes], (at) => at).single;
    pool.free();
    return tile;
  }

  test('a tile let go after its pool was freed lets go of nothing, and '
      'the engine is not asked', () {
    final pool = GpuPool(appGpuEngine, 1 << 30);
    final tile = storedThenFreed(pool);
    asked = 0;

    expect(pool.release(tile), isFalse);
    expect(asked, 0);
  });

  test('every other ask of a freed pool is refused by name, the engine '
      'asked none of them', () async {
    final pool = GpuPool(appGpuEngine, 1 << 30);
    final tile = storedThenFreed(pool);
    final into = calloc<Uint8>(gpuTileBytes);
    addTearDown(() => calloc.free(into));
    asked = 0;
    final refused = throwsA(isA<GpuRefused>());

    final asks = <String, Object? Function()>{
      'cel': pool.cel,
      'store': () => pool.store(0, [into], (at) => at),
      'read': () => pool.read([tile], into),
      'readout': () => pool.readout([tile]),
      'makeNoPagePast': () => pool.makeNoPagePast(0),
      'keepToInsteadOfTheOs': () => pool.keepToInsteadOfTheOs(0),
      'giveBackPast': () => pool.giveBackPast(0),
      'bytes': () => pool.bytes,
      'aheadBytes': () => pool.aheadBytes,
      'free': pool.free,
    };
    for (final MapEntry(key: verb, value: ask) in asks.entries) {
      expect(ask, refused, reason: verb);
    }
    final fold = GpuFold(appGpuEngine);
    addTearDown(fold.free);
    await expectLater(pool.fold(fold, 1), refused);
    expect(asked, 0);
  });

  test('a live pool tells the seam of each ask — ⛔CONTROL: the count '
      'above is of asks that would have gone', () {
    final pool = GpuPool(appGpuEngine, 1 << 30);
    addTearDown(pool.free);
    asked = 0;

    pool.bytes;
    expect(asked, 1);
  });

  test('nothing but the pool itself reads the pointer it lets go of', () {
    final source = File(
      'packages/gpu_engine/lib/gpu_engine.dart',
    ).readAsLinesSync();
    final start = source.indexWhere(
      (line) => line.startsWith('class GpuPool '),
    );
    final end = source.indexWhere((line) => line == '}', start);
    final outside = [
      for (final (at, line) in source.indexed)
        if ((at < start || at > end) && line.contains('_livePool')) at + 1,
    ];
    expect(start, isNonNegative);
    expect(outside, isEmpty);
  });
}
