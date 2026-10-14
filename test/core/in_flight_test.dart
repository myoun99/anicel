import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/in_flight.dart';

/// [InFlight] — work asked for by key while it runs is one run, and the key
/// is let go when it ends (`work_in_flight_is_shared_in_one_place_test`
/// says who keeps runs in it).
void main() {
  test('🚨two asks while it runs are ONE run — the same future, the work '
      'begun once; another key is another run', () async {
    final runs = InFlight<String, int>();
    final hold = Completer<int>();
    var begun = 0;
    Future<int> work() {
      begun += 1;
      return hold.future;
    }

    final first = runs.join('a', work);
    final second = runs.join('a', work);
    final other = runs.join('b', () async => 2);

    expect(second, same(first));
    expect(begun, 1);
    expect(runs.isRunning('a'), isTrue);
    expect(runs.runOf('a'), same(first));
    hold.complete(1);
    expect(await second, 1);
    expect(await other, 2);
  });

  test('🚨once it ends the key is let go — answered, or failed — and the '
      'next ask runs it anew', () async {
    final runs = InFlight<String, int>();
    var begun = 0;

    expect(await runs.join('a', () async => begun += 1), 1);
    expect(runs.isRunning('a'), isFalse, reason: 'answered, let go');
    expect(runs.runOf('a'), isNull);

    await expectLater(
      runs.join('a', () async => throw StateError('no')),
      throwsStateError,
    );
    expect(runs.isRunning('a'), isFalse, reason: 'failed, let go too');

    expect(await runs.join('a', () async => begun += 1), 2, reason: 'anew');
  });

  test('work that had its answer when it was asked is let go all the '
      'same', () async {
    final runs = InFlight<String, int>();
    final run = runs.join('a', () => Future.value(7));
    expect(runs.isRunning('a'), isTrue, reason: 'in flight until it lands');

    expect(await run, 7);

    expect(runs.isRunning('a'), isFalse);
  });
}
