import 'dart:async';

import 'package:anicel/src/core/once_a_microtask.dart';
import 'package:flutter_test/flutter_test.dart';

/// `OnceAMicrotask` — card told-once-a-microtask-is-written-nine-times
/// (2026-11-13).
void main() {
  test('🚨asked any number of times while the code runs, it is done once, '
      'after it — not as it is asked', () async {
    var done = 0;
    final told = OnceAMicrotask(() => done += 1);
    told.ask();
    told.ask();
    told.ask();
    expect(done, 0, reason: 'not while the code that asked runs');
    await Future<void>.value();
    expect(done, 1);
    await pumpEventQueue();
    expect(done, 1, reason: 'once for every ask before it');
  });

  test('asked till it is done, and not asked from the work on', () async {
    bool? askedInTheWork;
    late final OnceAMicrotask told;
    told = OnceAMicrotask(() => askedInTheWork = told.asked);
    expect(told.asked, isFalse);
    told.ask();
    expect(told.asked, isTrue);
    await pumpEventQueue();
    expect(askedInTheWork, isFalse);
    expect(told.asked, isFalse);
  });

  test('asked again once it is done, it is done again', () async {
    var done = 0;
    final told = OnceAMicrotask(() => done += 1);
    told.ask();
    await pumpEventQueue();
    told.ask();
    await pumpEventQueue();
    expect(done, 2);
  });

  test('🚨asked by the work itself, it is done once more after — let go of '
      'before the work, not after', () async {
    var done = 0;
    late final OnceAMicrotask told;
    told = OnceAMicrotask(() {
      done += 1;
      if (done == 1) {
        told.ask();
      }
    });
    told.ask();
    await pumpEventQueue();
    expect(done, 2);
  });

  test('done after the work already waiting, before what waits on a timer',
      () async {
    final order = <String>[];
    final told = OnceAMicrotask(() => order.add('told'));
    Timer.run(() => order.add('timer'));
    scheduleMicrotask(() => order.add('before'));
    told.ask();
    await pumpEventQueue();
    expect(order, ['before', 'told', 'timer']);
  });
}
