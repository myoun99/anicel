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
Future<void> collectGarbage() async {
  final target = reachabilityBarrier + 2;
  final churn = <List<int>>[];
  while (reachabilityBarrier < target) {
    await Future<void>.delayed(Duration.zero);
    churn.add(List<int>.filled(30000, 0));
    if (churn.length > 100) {
      churn.removeAt(0);
    }
  }
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
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
Future<void> collectGarbageUntil(
  bool Function() settled, {
  int rounds = 6,
}) async {
  var collected = 0;
  do {
    await collectGarbage();
    collected += 1;
  } while (!settled() && collected < rounds);
}
