import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';

import 'native_call_watch.dart';

/// The watch over native calls made on a test's own isolate (board
/// `the-trimmed-movie-test-can-hang-on-windows-ci`). Its clock has to run
/// while this isolate is stuck — which is what a blocking `sleep` is here:
/// a synchronous call that does not come back in time.
void main() {
  test('a step that does not end in time is named — while the isolate that '
      'made it is still stuck in it', () async {
    final told = ReceivePort();
    addTearDown(told.close);
    final watch = await NativeCallWatch.start(
      'the watch\'s own pin',
      limit: const Duration(milliseconds: 300),
      told: told.sendPort,
    );
    addTearDown(watch.stop);

    watch.step('the first call');
    watch.step('the call that blocks');
    sleep(const Duration(seconds: 1));

    expect(
      await told.first.timeout(const Duration(seconds: 10)),
      allOf(
        contains('「the watch\'s own pin」'),
        contains('「the call that blocks」'),
      ),
    );
  });

  test('the limit is each step\'s, not the test\'s — steps that each end in '
      'time say nothing however long they run together', () async {
    final told = ReceivePort();
    addTearDown(told.close);
    final heard = <Object?>[];
    told.listen(heard.add);
    final watch = await NativeCallWatch.start(
      'many short steps',
      limit: const Duration(seconds: 2),
      told: told.sendPort,
    );
    addTearDown(watch.stop);

    for (var call = 0; call < 5; call += 1) {
      watch.step('call $call');
      sleep(const Duration(milliseconds: 600));
    }
    watch.stop();
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(heard, isEmpty, reason: 'three seconds of steps, none over two');
  });

  test('a watch that is stopped says nothing — or a run whose steps all '
      'ended would be ended after them', () async {
    final told = ReceivePort();
    addTearDown(told.close);
    final heard = <Object?>[];
    told.listen(heard.add);
    final watch = await NativeCallWatch.start(
      'stopped',
      limit: const Duration(milliseconds: 300),
      told: told.sendPort,
    );

    watch.step('a call that returned');
    watch.stop();
    await Future<void>.delayed(const Duration(seconds: 1));

    expect(heard, isEmpty);
  });
}
