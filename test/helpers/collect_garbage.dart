import 'dart:developer' show reachabilityBarrier;

/// Runs full collections until two have completed, then two turns of the
/// event loop. For tests that prove a holder LETS GO: what nothing reaches
/// is collected by then, so a [WeakReference] to it reads null.
///
/// 🚨A FINALIZER'S CALLBACK IS NOT PROMISED HERE, though this comment used
/// to say it was. The VM hands the callback to the isolate as a message some
/// time after the collection that found the object dead, and on a loaded
/// machine that message lands after these two turns (tile-count-gc-flake,
/// 2026-09-11: one tile's 64 bytes still on the books inside a parity batch,
/// green alone). A count a finalizer brings down is waited for with
/// [collectGarbageUntil], which names what it waits for.
///
/// Churns small lists instead of asking the VM, because a test cannot
/// reach the VM service — the way `leak_tracker`'s `forceGC` does it.
///
/// 🚨★★★IT GIVES UP AFTER [atMost] (tile-count-timeout-under-load). The
/// loop used to wait for the barrier with no bound at all, and a barrier
/// that does not advance is not an error the caller ever hears about: in a
/// full affected batch this file hit the runner's TEN MINUTE cap twice in
/// one day (2026-09-16), which kills the whole file and says nothing about
/// what leaked.
///
/// 🔬Measured on this machine, idle: one collection is 110–472 turns of the
/// event loop and **34–124 ms**. Under a hundred-odd concurrent test
/// isolates the turns are the same and the SCHEDULING is not — so the bound
/// is wall-clock, not turns, and it is two orders of magnitude over the
/// idle cost.
///
/// ⚠️Giving up is not passing: nothing here asserts. The caller's own
/// `expect` reads the real number afterwards, so a release that never came
/// is still red — it just says so in seconds instead of taking the file
/// down with it.
Future<void> collectGarbage({
  Duration atMost = const Duration(seconds: 30),
}) async {
  final target = reachabilityBarrier + 2;
  final clock = Stopwatch()..start();
  final held = <List<int>>[];
  await churnUntil(
    happened: () => reachabilityBarrier >= target,
    elapsed: () => clock.elapsed,
    atMost: atMost,
    churn: () async {
      await Future<void>.delayed(Duration.zero);
      held.add(List<int>.filled(30000, 0));
      if (held.length > 100) {
        held.removeAt(0);
      }
    },
  );
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

/// The bounded wait itself: churn until [happened], or until [elapsed]
/// passes [atMost]. Answers whether it happened.
///
/// 🚨★★★SPLIT OUT BECAUSE THE BOUND WAS UNPINNABLE OTHERWISE, and a pin
/// that cannot fail is worse than none (2026-09-16). The first cut of this
/// round bounded the loop and pinned it by calling the real thing with a
/// 40ms bound — but on an idle machine the barrier moves in about 100ms
/// either way, so the test passed with the bound, without it, and with it
/// made two hundred times looser. **Both mutants survived**, which is what
/// said the pin was measuring nothing.
///
/// A VM cannot be told to stall, so the CLOCK and the CHURN are arguments
/// here and a test can hold them still.
Future<bool> churnUntil({
  required bool Function() happened,
  required Duration Function() elapsed,
  required Future<void> Function() churn,
  required Duration atMost,
}) async {
  while (!happened() && elapsed() < atMost) {
    await churn();
  }
  return happened();
}

/// Collects at least once, then again until [settled] holds — for what a
/// FINALIZER does (a byte count coming down, a native copy freed), which
/// arrives after the collection rather than inside it.
///
/// ⚠️It gives up after [rounds] collections without [settled], so the
/// caller's own `expect` still reports the real value: a release that never
/// comes stays red. The bound only decides how long that takes to say so.
///
/// ⛔It was 50, and a release that never came took one test past 10 GB and
/// five minutes to say so (2026-09-15): fifty rounds of churn under a heap
/// something was holding. Measured the same day, every call the suite makes
/// (five, across the three files that use this) settled in ONE collection —
/// so six leaves room for a finalizer message a loaded machine delivers late,
/// and still names a holder in seconds.
/// [collect] is the seam the bound is pinned through: a VM cannot be told
/// to stall, so a test hands in a collection that does nothing and reads
/// the bounds it was given.
Future<void> collectGarbageUntil(
  bool Function() settled, {
  int rounds = 6,
  Duration atMost = const Duration(seconds: 30),
  Future<void> Function(Duration atMost)? collect,
}) async {
  // ⚠️ONE clock for the whole wait, not one per collection. The bound used
  // to be handed to each round, so [rounds] × [atMost] was the real
  // ceiling and a round that forgot to pass it down lost the caller's
  // bound silently — an invariant nobody could see. There is nothing to
  // forget now: what is left of [atMost] is what the next collection gets.
  final clock = Stopwatch()..start();
  final run = collect ?? (Duration left) => collectGarbage(atMost: left);
  var collected = 0;
  do {
    await run(atMost - clock.elapsed);
    collected += 1;
  } while (!settled() && collected < rounds && clock.elapsed < atMost);
}
