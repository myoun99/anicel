import 'package:flutter_test/flutter_test.dart';

import 'collect_garbage.dart';

/// tile-count-timeout-under-load (2026-09-16): `tile_images_are_counted`
/// hit the runner's TEN MINUTE cap twice in one day inside a full affected
/// batch, and passed in a second when it was run alone.
///
/// The wait for a collection had no bound: it churned until the
/// reachability barrier moved, and on a machine running a hundred-odd test
/// isolates that can be forever. A bound turns「the file died and told you
/// nothing」into「the caller's expect reads the real number」.
///
/// 🔬Idle cost of one collection on this machine, measured the same day:
/// 110–472 turns of the event loop, 34–124 ms. The default bound is 30
/// seconds — two orders of magnitude of room.
void main() {
  test('🎯a collection that never settles still comes back — bounded by the '
      'clock, not by luck', () async {
    final clock = Stopwatch()..start();

    // A condition that can never hold, so only the bound can end this.
    await collectGarbageUntil(
      () => false,
      rounds: 3,
      atMost: const Duration(milliseconds: 40),
    );

    expect(
      clock.elapsed,
      lessThan(const Duration(seconds: 5)),
      reason: 'three rounds of 40ms — it used to wait with no bound at all',
    );
  });

  test('🚨and a settled condition still ends it on the first collection', () {
    // ⚠️The bound is a floor under failure, not a ceiling on success: a
    // wait that had started giving up early would make every finalizer
    // pin flaky instead of slow.
    return expectLater(
      () async {
        final clock = Stopwatch()..start();
        await collectGarbageUntil(() => true);
        return clock.elapsed;
      }(),
      completion(lessThan(const Duration(seconds: 10))),
    );
  });
}
