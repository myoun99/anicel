@Tags(['gc'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';

import '../helpers/collect_garbage.dart';
import '../helpers/tiles_on_the_engine.dart';

/// A tile the engine alone holds keeps the tile it landed on — what it
/// reads as where a device goes with its pixels (🗣️gpu-canonical-store-Q11,
/// 유저 2026-11-10: 「RAM 에 사본을 두고 앱을 유지한다」) — and no longer
/// than that: once its copy is here, or its slot is let go, the tile under
/// it is whoever else's to keep. A stroke lands a tile at every frame, on
/// the cel's own; one kept past its use would be a cel's old picture held
/// for as long as the ledger stands.
void main() {
  // A cel, by the name a painter gives one.
  const cel = (1, 1);

  late GpuEngine engine;
  late EngineTileLedger ledger;

  setUp(() {
    engine = GpuEngine.onFirstAdapter();
    ledger = EngineTileLedger(engine);
  });
  // ⚠️The ledger's pool is not freed with its test: a tile collected after
  // it lets its slot go there (the ledger's finalizer), in a later test.
  tearDown(() => engine.close());

  /// A tile landed on one of its own making, and that one held weakly. In
  /// a call of its own: a tile is Finalizable, and a method called on it
  /// in a test would keep it alive to the end of that test.
  (BitmapTile, WeakReference<BitmapTile>) landedOnOne() {
    final under = BitmapTile.blank(size: gpuTileSide);
    return (landedOn(ledger, cel, [under], 9).single, WeakReference(under));
  }

  test('the tile under one the engine alone holds is kept', () async {
    final (landed, under) = landedOnOne();

    await collectGarbage();

    expect(landed.isOnlyOnEngine, isTrue, reason: '⛔premise');
    expect(under.target, isNotNull);
  });

  test('it is let go once the copy of what landed on it is here', () async {
    final (landed, under) = landedOnOne();

    await ledger.copyHereABatch();
    await collectGarbageUntil(() => under.target == null);

    expect(landed.isOnlyOnEngine, isFalse, reason: '⛔premise');
    expect(under.target, isNull);
  });

  test('it is let go once what landed on it is read here', () async {
    final (landed, under) = landedOnOne();

    expect(landed.pixels, everyElement(9));
    await collectGarbageUntil(() => under.target == null);

    expect(under.target, isNull);
  });

  test('it is let go with the slot of what landed on it', () async {
    final (landed, under) = landedOnOne();

    ledger.retire(landed);
    await collectGarbageUntil(() => under.target == null);

    expect(under.target, isNull);
  });
}
