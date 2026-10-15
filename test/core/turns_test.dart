import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/turns.dart';

/// [Turns] — work that runs at most so many at a time, the rest in the
/// order it asked (card `cel-thaw-holds-the-ui-thread` ⑧: thirteen rows
/// of a frame start their thaws together, and a machine has fewer cores).
void main() {
  test('🚨no more than its number at once — the rest wait, and start in '
      'the order they asked as each turn ends', () async {
    final turns = Turns(2);
    final holds = [for (var i = 0; i < 5; i += 1) Completer<void>()];
    final started = <int>[];
    final done = [
      for (var i = 0; i < 5; i += 1)
        turns.run(() async {
          started.add(i);
          await holds[i].future;
          return i;
        }),
    ];
    await pumpEventQueue();
    expect(started, [0, 1], reason: 'two turns, two at work');
    expect(turns.running, 2);

    holds[1].complete();
    await pumpEventQueue();
    expect(started, [0, 1, 2], reason: 'the turn passed to the first in line');
    expect(turns.running, 2, reason: 'passed on, not handed back');

    holds[0].complete();
    holds[2].complete();
    await pumpEventQueue();
    expect(started, [0, 1, 2, 3, 4]);

    holds[3].complete();
    holds[4].complete();
    expect(await Future.wait(done), [0, 1, 2, 3, 4]);
    expect(turns.running, 0, reason: 'every turn came back');
  });

  test('work that throws gives its turn back — and its caller the '
      'error', () async {
    final turns = Turns(1);
    await expectLater(
      turns.run<void>(() async => throw StateError('no')),
      throwsStateError,
    );
    expect(turns.running, 0);
    expect(await turns.run(() async => 7), 7, reason: 'the next one ran');
  });
}
