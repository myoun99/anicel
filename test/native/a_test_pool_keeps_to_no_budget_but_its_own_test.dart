import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';

/// A test's pool keeps to no budget but its own, not to the OS's — the
/// machine's VRAM as the suites beside it leave it (🗣️관제 2026-11-16,
/// pool-tests-ride-the-os-vram-budget; GpuPool.debugBudgetTillOneIsSet has
/// the reds). ⛔A test of behaviour cannot tell: a pool kept to the OS's
/// passes on a machine with VRAM to spare — so this reads what each pool
/// is told. Which test may keep to the OS's is
/// test/architecture/a_test_keeps_a_pool_to_the_os_budget_only_by_name_test.dart's.
void main() {
  test("every pool a test makes keeps to none of the OS's budget — one made "
      "bare, a ledger's of its own, and the app's ledger's", () {
    final none = GpuPool.debugBudgetTillOneIsSet;
    expect(none, isNotNull, reason: 'the run sets one');
    final bare = GpuPool(appGpuEngine, 1 << 30);
    addTearDown(bare.free);
    final ledger = EngineTileLedger(appGpuEngine);
    addTearDown(ledger.pool.free);

    expect(
      [bare, ledger.pool, EngineTileLedger.instance.pool].map(
        (pool) => pool.budgetInstead,
      ),
      everyElement(none),
    );
  });
}
