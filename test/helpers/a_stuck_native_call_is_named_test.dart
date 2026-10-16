import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'native_call_watch.dart';
import 'project_scratch_folder.dart';

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
      dumps: null,
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

  test(
    '🚨on Windows it leaves the process\'s threads behind too — a minidump '
    'written from outside while the isolate is still stuck in the call, and '
    'named in what it says (Q1)',
    () async {
      final dumps = Directory.systemTemp.createTempSync('native-call-watch');
      deleteAfterSessionEnds(dumps);
      final told = ReceivePort();
      addTearDown(told.close);
      final watch = await NativeCallWatch.start(
        'the dump pin',
        limit: const Duration(milliseconds: 300),
        told: told.sendPort,
        dumps: dumps.path,
      );
      addTearDown(watch.stop);

      watch.step('the call that blocks');
      // Stuck, as a native call is, until the dump is whole — so what it
      // keeps of this isolate is the isolate inside the call.
      final giveUp = DateTime.now().add(const Duration(minutes: 1));
      List<File> written() => [
        for (final entity in dumps.listSync())
          if (entity is File && entity.path.endsWith('.dmp')) entity,
      ];
      while (written().isEmpty && DateTime.now().isBefore(giveUp)) {
        sleep(const Duration(milliseconds: 50));
      }

      final dump = written().single;
      expect(
        await told.first.timeout(const Duration(seconds: 30)),
        contains(dump.path),
      );
      final raw = dump.readAsBytesSync();
      expect(String.fromCharCodes(raw.take(4)), 'MDMP');
      // The header's stream directory: what the dump holds. (The modules
      // let go of are a stream only once one has been.)
      final bytes = ByteData.sublistView(raw);
      final count = bytes.getUint32(8, Endian.little);
      final at = bytes.getUint32(12, Endian.little);
      expect(
        [
          for (var i = 0; i < count; i += 1)
            bytes.getUint32(at + i * 12, Endian.little),
        ],
        containsAll([
          3, // every thread and its stack
          4, // the modules
          12, // the handles
          16, // the memory map
          17, // each thread's state
        ]),
      );
    },
    skip: Platform.isWindows ? null : 'a minidump is a Windows file',
    timeout: const Timeout(Duration(minutes: 2)),
  );

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
      dumps: null,
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
      dumps: null,
    );

    watch.step('a call that returned');
    watch.stop();
    await Future<void>.delayed(const Duration(seconds: 1));

    expect(heard, isEmpty);
  });
}
