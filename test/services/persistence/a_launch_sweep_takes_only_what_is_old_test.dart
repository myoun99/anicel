@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/sweep_old_files.dart';

/// 🚨THE SWEEP RUNS ONCE PER LAUNCH, OVER SOMEBODY'S WORKING FILES.
///
/// Two stores swept their own directory this way — the recovery snapshots
/// and the staged media — and they had drifted: only one swallowed a
/// failed delete. A session open longer than the window must not have its
/// own bytes taken out from under it, which is what the cutoff is for.
void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('anicel-sweep');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  File aged(String name, Duration age, DateTime now) {
    final file = File('${directory.path}/$name')..writeAsStringSync('x');
    file.setLastModifiedSync(now.subtract(age));
    return file;
  }

  test('a directory that is not there sweeps nothing and does not throw', () {
    final missing = Directory('${directory.path}/never-made');
    expect(
      sweepFilesOlderThan(missing, olderThan: const Duration(days: 30)),
      0,
    );
  });

  test('older than the window goes, younger stays', () {
    final now = DateTime(2026, 9, 4, 12);
    final old = aged('old.bin', const Duration(days: 31), now);
    final fresh = aged('fresh.bin', const Duration(days: 29), now);

    final swept = sweepFilesOlderThan(
      directory,
      olderThan: const Duration(days: 30),
      now: now,
    );

    expect(swept, 1);
    expect(old.existsSync(), isFalse);
    expect(
      fresh.existsSync(),
      isTrue,
      reason: 'a session open inside the window keeps its own bytes',
    );
  });

  test('a file exactly at the cutoff stays', () {
    final now = DateTime(2026, 9, 4, 12);
    final edge = aged('edge.bin', const Duration(days: 30), now);

    sweepFilesOlderThan(
      directory,
      olderThan: const Duration(days: 30),
      now: now,
    );

    expect(
      edge.existsSync(),
      isTrue,
      reason: 'the test is isBefore — ties belong to the file, not the sweep',
    );
  });

  test('a SUBDIRECTORY is never swept, however old', () {
    final now = DateTime(2026, 9, 4, 12);
    final nested = Directory('${directory.path}/nested')..createSync();
    aged('old.bin', const Duration(days: 90), now);

    final swept = sweepFilesOlderThan(
      directory,
      olderThan: const Duration(days: 30),
      now: now,
    );

    expect(swept, 1);
    expect(
      nested.existsSync(),
      isTrue,
      reason: 'the sweep takes files it made, not folders it found',
    );
  });

  test('it walks one level, not the tree', () {
    final now = DateTime(2026, 9, 4, 12);
    Directory('${directory.path}/nested').createSync();
    final deep = File('${directory.path}/nested/old.bin')
      ..writeAsStringSync('x');
    deep.setLastModifiedSync(now.subtract(const Duration(days: 90)));

    expect(
      sweepFilesOlderThan(
        directory,
        olderThan: const Duration(days: 30),
        now: now,
      ),
      0,
    );
    expect(deep.existsSync(), isTrue);
  });
}
