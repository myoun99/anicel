import 'package:flutter_test/flutter_test.dart';

import 'collect_garbage.dart';

/// tile-count-timeout-under-load (2026-09-16): `tile_images_are_counted`
/// hit the runner's TEN MINUTE cap twice in one day inside a full affected
/// batch, and passed in about a second when it was run alone. The wait for
/// a collection had no bound — it churns until the reachability barrier
/// moves (a test cannot ask the VM service), and on a machine running a
/// hundred-odd test isolates that can outlast the runner.
///
/// 🚨★★★THE FIRST CUT OF THIS PIN MEASURED NOTHING. It called the real
/// wait with a 40ms bound and asserted it came back quickly — but on an
/// idle machine the barrier moves in about 100ms whatever the bound is, so
/// it passed with the bound, without it, and with it made two hundred
/// times looser. Both mutants survived; that is what said so. The clock and
/// the churn are arguments now, so the BOUND is what is being asked about.
void main() {
  test('🎯the bound ends a wait whose collection never comes', () async {
    var churns = 0;
    var fake = Duration.zero;

    final happened = await churnUntil(
      happened: () => false,
      elapsed: () => fake,
      atMost: const Duration(seconds: 30),
      churn: () async {
        churns += 1;
        fake += const Duration(seconds: 1);
      },
    );

    expect(happened, isFalse, reason: 'it says it did not happen');
    expect(
      churns,
      30,
      reason: 'one churn a second up to the bound, and then it stops',
    );
  });

  test('🚨and a collection that DOES come ends it there, bound or no bound', () async {
    var churns = 0;
    var collected = false;

    final happened = await churnUntil(
      happened: () => collected,
      elapsed: () => Duration.zero,
      atMost: const Duration(seconds: 30),
      churn: () async {
        churns += 1;
        if (churns == 3) {
          collected = true;
        }
      },
    );

    expect(happened, isTrue);
    expect(
      churns,
      3,
      reason: 'the bound is a floor under failure, not a ceiling on success',
    );
  });

  test('🚨a bound already spent churns nothing at all', () async {
    var churns = 0;

    final happened = await churnUntil(
      happened: () => false,
      elapsed: () => const Duration(seconds: 31),
      atMost: const Duration(seconds: 30),
      churn: () async => churns += 1,
    );

    expect(happened, isFalse);
    expect(churns, 0, reason: 'what is left of the bound is what it gets');
  });

  test('🚨the rounds share ONE bound — each collection gets what is left of '
      'it', () async {
    final given = <Duration>[];

    await collectGarbageUntil(
      () => false,
      rounds: 4,
      atMost: const Duration(seconds: 30),
      collect: (left) async {
        given.add(left);
        // A collection that takes real time, so the clock moves between
        // rounds the way a churning one would.
        await Future<void>.delayed(const Duration(milliseconds: 30));
      },
    );

    expect(given, hasLength(4));
    for (var i = 1; i < given.length; i += 1) {
      expect(
        given[i],
        lessThan(given[i - 1]),
        reason: 'one clock for the whole wait, not one per round: $given',
      );
    }
    expect(
      given.first,
      lessThanOrEqualTo(const Duration(seconds: 30)),
      reason: 'and never more than the caller asked for',
    );
  });

  test('the real wait still settles in well under its bound on an idle '
      'machine', () async {
    final clock = Stopwatch()..start();

    await collectGarbageUntil(() => true);

    // 🔬Measured here, idle: one collection is 34–124 ms.
    expect(clock.elapsed, lessThan(const Duration(seconds: 10)));
  });
}
