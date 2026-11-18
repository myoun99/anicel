import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';

/// A screen's free waits for none of the bodies handed over ahead of it
/// (rust/src/kernels/composite/abi.rs, `gpu_engine_screen_free`), and its
/// part of [GpuScreen.liveBytes] is off as the free returns all the same:
/// what its last body told, and nothing a body still ahead tells after.
void main() {
  const whole = (0, 0, 1, 1);

  /// A plan of one red tile over [whole], and the pool it names.
  ({GpuPool pool, GpuPlan plan}) aPlan() {
    final pool = GpuPool(appGpuEngine, 1 << 30);
    addTearDown(pool.free);
    final plan = GpuPlan(appGpuEngine);
    addTearDown(plan.free);
    plan.solid(0xFF0000FF, 0, 0, 1, 1);
    return (pool: pool, plan: plan);
  }

  test('a screen counts what its compose made, and is off as its free '
      'returns', () async {
    final (:pool, :plan) = aPlan();
    final before = GpuScreen.liveBytes;
    final screen = GpuScreen(appGpuComposite, whole);
    await screen.compose(pool, plan, whole);
    expect(screen.bytes, isPositive, reason: '⛔premise: it keeps a tile');
    expect(GpuScreen.liveBytes - before, screen.bytes, reason: 'counted');

    screen.free();

    expect(GpuScreen.liveBytes, before);
  });

  test('a compose still ahead of the free counts nowhere once it runs',
      () async {
    final (:pool, :plan) = aPlan();
    final before = GpuScreen.liveBytes;
    final screen = GpuScreen(appGpuComposite, whole);
    // The engine stands still: the compose is handed over, and has not run
    // as the free is called.
    appGpuEngine.debugStandStill(const Duration(seconds: 1));
    final composed = screen.compose(pool, plan, whole);
    screen.free();
    expect(GpuScreen.liveBytes, before, reason: 'nothing told yet');

    await composed;
    await appGpuEngine.done();

    expect(GpuScreen.liveBytes, before);
  });
}
