import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';

import '../helpers/a_shown_surface.dart';

/// 🗣️유저 2026-11-20 23:20 (a-transform-drag-over-folder-rows-draws-a-
/// frame-in-a-third-of-a-second-Q1 = b): 「손을 떼면 바로 놓는다」 — the
/// buffers the engine's composes run in are kept from one compose to the
/// next while a hand is at work, and let go a rest after the last compose
/// handed over ([GpuEngine.restsAfter]).
///
/// What a rest keeps, and what comes home after it, is the crate's to pin
/// (rust/src/kernels/composite/spares_tests.rs) — here, when the hand is
/// taken to rest: a rest after the last compose, through whichever door
/// it was handed. Each on a widget test's clock, which a rest is taken by
/// as it is pumped.
void main() {
  const rest = EngineTileLedger.rest;
  const aMoment = Duration(milliseconds: 1);
  const all = (-1 << 31, -1 << 31, (1 << 31) - 1, (1 << 31) - 1);
  const identity = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
  final whole = (0, 0, gpuTileSide, gpuTileSide);
  late GpuPool pool;
  final held = <Pointer<Uint8>>[];

  setUp(() {
    pool = GpuPool(appGpuEngine, 1 << 30);
    GpuEngine.restsAfter = rest;
  });
  tearDown(() {
    GpuEngine.restsAfter = null;
    pool.free();
    held
      ..forEach(calloc.free)
      ..clear();
  });

  /// A plan of one row of one white tile, blurred: its compose runs the
  /// row's chain first, in buffers of the engine's.
  GpuPlan blurred() {
    final bytes = calloc<Uint8>(gpuTileBytes);
    bytes.asTypedList(gpuTileBytes).fillRange(0, gpuTileBytes, 255);
    held.add(bytes);
    final tiles = pool.store(pool.cel(), [bytes], (tile) => tile);
    final plan = GpuPlan(appGpuEngine);
    addTearDown(plan.free);
    final set = plan.set(0, 0, 1, 1, tiles);
    final chain = plan.chain(0, 0, 1, 1);
    plan.chainGaussian(
      chain,
      across: (sigma: 10 / 3, reach: 10),
      down: (sigma: 0, reach: 0),
      picture: whole,
      repeats: false,
      puts: whole,
    );
    final added = plan.row(
      set: set,
      inverse: identity,
      sampling: GpuSampling.blend,
      columns: gpuTileSide,
      rows: gpuTileSide,
      mode: GpuBlend.normal,
      chain: chain,
    );
    expect(added, isTrue);
    return plan;
  }

  /// What the engine keeps for no picture, once it has run all it was
  /// handed: asked behind a give-back that gives nothing back, which waits
  /// its turn on the engine's thread — a rest is taken there, this isolate
  /// waiting for none of it.
  int idle() {
    appGpuEngine.givePicturesBackPast(1 << 62);
    return appGpuEngine.idlePictureBytes;
  }

  testWidgets('what a compose ran in is kept for the next, and let go a '
      'rest after the last compose handed over', (tester) async {
    final plan = blurred();
    void compose() => appGpuComposite.run(pool, plan, [(0, 0)], all).free();
    // The composite's work buffer is made by the first run and stays: what
    // a rest leaves.
    compose();
    await tester.pump(rest);
    final atRest = idle();

    compose();
    final atWork = idle();
    expect(atWork, greaterThan(atRest), reason: '⛔premise: buffers kept');
    await tester.pump(rest - aMoment);
    expect(idle(), atWork, reason: 'kept within a rest');
    compose();
    await tester.pump(rest - aMoment);
    expect(idle(), atWork, reason: 'a compose handed over puts it off');
    await tester.pump(aMoment);

    expect(idle(), atRest, reason: 'let go a rest after the last');
  });

  testWidgets('a compose handed through any door puts the rest off', (
    tester,
  ) async {
    final plan = blurred();
    final screen = GpuScreen(appGpuComposite, whole);
    addTearDown(screen.free);
    final over = GpuScreen(appGpuComposite, whole);
    addTearDown(over.free);
    final surface = shownSurfaceOf(gpuTileSide, gpuTileSide);
    addTearDown(surface.free);
    final doors = <String, void Function()>{
      'run': () => appGpuComposite.run(pool, plan, [(0, 0)], all).free(),
      'show': () => appGpuComposite.show(pool, plan, surface, whole),
      'compose': () => unawaited(screen.compose(pool, plan, whole)),
      'composeOver': () =>
          unawaited(over.composeOver(screen, pool, plan, whole)),
    };

    for (final MapEntry(key: door, value: handOver) in doors.entries) {
      expect(appGpuEngine.debugRestOnItsWay, isFalse, reason: '⛔at $door');
      handOver();
      expect(appGpuEngine.debugRestOnItsWay, isTrue, reason: door);
      await tester.pump(rest);
      expect(appGpuEngine.debugRestOnItsWay, isFalse, reason: 'after $door');
    }
  });

  // A widget test's clock would not end a timer nothing asked for: an
  // engine no launch told when a hand rests arms none.
  testWidgets('no rest is on its way where no launch said when a hand '
      'rests', (tester) async {
    GpuEngine.restsAfter = null;
    final plan = blurred();

    appGpuComposite.run(pool, plan, [(0, 0)], all).free();

    expect(appGpuEngine.debugRestOnItsWay, isFalse);
  });

  // The rest would be taken on an engine freed.
  testWidgets('an engine closed takes no rest', (tester) async {
    final engine = GpuEngine.onFirstAdapter();
    final composite = GpuComposite(engine);
    final own = GpuPool(engine, 1 << 20);
    final plan = GpuPlan(engine)..solid(0xFF0000FF, 0, 0, 1, 1);
    composite.run(own, plan, [(0, 0)], all).free();
    expect(engine.debugRestOnItsWay, isTrue, reason: '⛔premise: one armed');
    plan.free();
    own.free();
    composite.free();

    engine.close();

    expect(engine.debugRestOnItsWay, isFalse);
  });
}
