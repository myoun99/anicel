import 'dart:developer' show reachabilityBarrier;
import 'dart:typed_data' show Uint8List;

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
/// Churns instead of asking the VM, because a test cannot reach the VM
/// service — what it churns is [_churn]'s to say.
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
  final held = <Uint8List>[];
  await churnUntil(
    happened: () => reachabilityBarrier >= target,
    elapsed: () => clock.elapsed,
    atMost: atMost,
    churn: () async {
      await Future<void>.delayed(Duration.zero);
      _churn(held);
    },
  );
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

/// A megabyte of bytes on [held], the one before let go: what brings the
/// collector round.
///
/// 🚨★★★OLD-SPACE GARBAGE THE CHURN MARKS AGAINST ITSELF, NOT PROMOTED
/// LISTS (gc-pin-stall, 2026-11-08). This used to be `leak_tracker`'s
/// churn — a hundred 240 KB lists of pointers kept alive — and those 24 MB
/// outgrow new space, so every scavenge promoted them. Promotion is the one
/// old-space growth the VM grants with no back pressure: it is forced
/// growth, and the check after a scavenge asks for no marking at all. So
/// the mark had to outrun the promotion on its helper threads alone, and
/// on a loaded machine it did not: the barrier stood still for 60–97 s
/// while the heap grew by every byte churned, to 16 GB in two test
/// processes at once. The bare VM's own log (`--verbose_gc`) showed it at
/// idle as well — every slow mark of ten pairs was one a promotion
/// started, up to 2.35 s, its two tasks marking 288 MB each.
///
/// A list over 256 KB is made in old space directly, and each one makes
/// the thread that asks for it mark 1.25 times its size and finalize a
/// finished mark — so the collection moves with the churn itself, whatever
/// the helper threads get. Bytes hold no pointers: nothing more to mark.
/// Measured the same day, bare VM: a collection in 13–58 ms.
void _churn(List<Uint8List> held) {
  held
    ..clear()
    ..add(Uint8List(churnBytes));
}

/// The bytes of each list [_churn] makes: past the 256 KB a list may take
/// in new space (the VM's `kNewAllocatableSize`), so it is made in old
/// space and never promoted.
const churnBytes = 1 << 20;

/// Runs full collections until two have completed INSIDE this turn of the
/// event loop — for a test that reads what a holder does after a
/// collection and before any finalizer's message can land: the VM hands
/// those to the isolate as messages, and none runs till the turn ends. A
/// [WeakReference] to what nothing reaches reads null after.
///
/// ⚠️It gives up after [atMost], as [collectGarbage] does, and asserts
/// nothing: the caller's own `expect` reads the real value.
void collectGarbageInThisTurn({
  Duration atMost = const Duration(seconds: 30),
}) {
  final target = reachabilityBarrier + 2;
  final clock = Stopwatch()..start();
  final held = <Uint8List>[];
  while (reachabilityBarrier < target && clock.elapsed < atMost) {
    _churn(held);
  }
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
