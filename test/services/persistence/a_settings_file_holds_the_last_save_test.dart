import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/versioned_settings_file.dart';

import '../../helpers/temp_dir.dart';

/// 🚨A SETTINGS FILE HOLDS WHAT WAS SAVED LAST (board
/// `settings-writes-land-out-of-order`). Two writes into one file promise
/// nothing about the order they finish in, and two in flight at once
/// interleave. Four stores found that one at a time and fixed only
/// themselves — the brush preset library's pins lived in its own test — and
/// the rest had nothing. The law is the writer's now, for every settings
/// file.
void main() {
  // Every file here is in a folder of the test's own — a write that
  // escaped the held disk must not land in the checkout (one did, under a
  // mutant that gave every file one writer).
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-settings');
  });
  tearDown(() => deleteTempQuietly(directory));

  String pathFor(String name) => '${directory.path}/$name';

  group('an asynchronous save — one write at a time per file', () {
    late _HeldDisk disk;

    setUp(() {
      disk = _HeldDisk();
      debugSettingsFileWrite = disk.write;
    });
    // A write left open would hold its file's next save — the next test's.
    tearDown(() async {
      while (await disk.finishOne()) {}
      debugSettingsFileWrite = null;
    });

    Future<void> save(String name, int value) => saveVersionedSettings(
      filePath: pathFor(name),
      version: 1,
      json: {'value': value},
    );

    test('a second save does not start a second write to the file', () async {
      unawaited(save('a.json', 1));
      unawaited(save('a.json', 2));

      expect(
        disk.started,
        [('a.json', 1)],
        reason: 'the second waits for the first to land',
      );

      expect(await disk.finishOne(), isTrue);

      expect(disk.started, [('a.json', 1), ('a.json', 2)]);
    });

    test('the saves in between are skipped — the last one is not, and each '
        'caller hears when the file holds its save or a newer one', () async {
      final heard = <int>[];
      for (final value in [1, 2, 3, 4]) {
        unawaited(save('a.json', value).then((_) => heard.add(value)));
      }

      expect(await disk.finishOne(), isTrue);
      expect(heard, [1], reason: 'the first landed; the rest wait');
      expect(await disk.finishOne(), isTrue);
      expect(await disk.finishOne(), isFalse, reason: 'nothing else is owed');

      expect(disk.started.map((write) => write.$2), [1, 4]);
      expect(heard, [1, 2, 3, 4]);
    });

    test('a failed write never reaches the caller, and the next save still '
        'writes', () async {
      disk.failing = true;
      final failed = save('a.json', 1);
      disk.failing = false;
      unawaited(save('a.json', 2));

      expect(await disk.finishOne(), isTrue);
      await expectLater(failed, completes);

      expect(disk.started.map((write) => write.$2), [1, 2]);
      expect(await disk.finishOne(), isTrue);
      expect(disk.landed, {'a.json': 2});
    });

    test('two files do not wait for each other', () async {
      unawaited(save('a.json', 1));
      unawaited(save('b.json', 2));

      expect(disk.started, [('a.json', 1), ('b.json', 2)]);
    });

    test('⛔a document JSON cannot hold is not written — and the caller '
        'does not hear of it', () async {
      final nan = saveVersionedSettings(
        filePath: pathFor('a.json'),
        version: 1,
        json: {'value': double.nan},
      );

      await expectLater(nan, completes);
      expect(disk.started, isEmpty);
    });
  });

  group('the real disk', () {
    test('a burst of saves leaves the file holding the LAST one, '
        'whole', () async {
      final path = '${directory.path}/burst.json';
      final saves = [
        for (var value = 0; value < 40; value += 1)
          saveVersionedSettings(
            filePath: path,
            version: 1,
            // Longest first: an overlapping write that outlived a shorter
            // one would leave its tail behind.
            json: {'value': value, 'pad': 'x' * (4000 - value * 100)},
          ),
      ];
      await Future.wait(saves);

      final held = jsonDecode(await File(path).readAsString()) as Map;
      expect(held['value'], 39);
    });

    test('the synchronous save has written before it returns, making the '
        'folder', () {
      final path = '${directory.path}/deep/and/deeper/now.json';

      saveVersionedSettingsSync(filePath: path, version: 2, json: {'on': true});

      expect(jsonDecode(File(path).readAsStringSync()), {
        'version': 2,
        'on': true,
      });
    });

    test('a synchronous save that cannot be written does not throw', () {
      final blocker = File('${directory.path}/a-file')..writeAsStringSync('');

      expect(
        () => saveVersionedSettingsSync(
          filePath: '${blocker.path}/inside.json',
          version: 1,
          json: const {},
        ),
        returnsNormally,
      );
    });
  });
}

/// A disk whose writes land when the TEST says — never on a timer, which
/// would be a bet on how busy the machine is
/// (`tests_do_not_race_the_code_test`).
class _HeldDisk {
  /// Every write the writer started, in order: the file's name and its
  /// value.
  final List<(String, int)> started = [];

  /// What each file holds once its writes landed, by name.
  final Map<String, int> landed = {};

  /// Whether the writes started from now on fail.
  bool failing = false;

  final List<({String name, int value, bool fails, Completer<void> done})>
  _open = [];

  Future<void> write(String filePath, String text) {
    final name = filePath.substring(filePath.lastIndexOf('/') + 1);
    final value = (jsonDecode(text) as Map)['value'] as int;
    started.add((name, value));
    final done = Completer<void>();
    _open.add((name: name, value: value, fails: failing, done: done));
    return done.future;
  }

  /// Lands the oldest write still open — or fails it — and gives the
  /// writer the turn it needs to start whatever waits. False means nothing
  /// was open: positive evidence the queue is empty.
  Future<bool> finishOne() async {
    if (_open.isEmpty) {
      return false;
    }
    final write = _open.removeAt(0);
    if (write.fails) {
      write.done.completeError(const FileSystemException('held disk'));
    } else {
      landed[write.name] = write.value;
      write.done.complete();
    }
    await pumpEventQueue();
    return true;
  }
}
