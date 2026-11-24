@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/affected_tests.dart' show pastTheCache;

/// 🗣️유저 2026-11-24 13:12 (affected-tests-skipped-the-changed-test-file-
/// Q1 「바뀐 시험 파일은 늘 돌린다」): the result cache lets a file go when
/// it was green on this machine with the inputs it has now — but never a
/// test file the lane changed.
void main() {
  const changedTest =
      'test/ui/a_placement_starts_from_its_files_preset_test.dart';
  const unchanged = 'test/ui/a_layer_is_drawn_test.dart';
  const redBefore = 'test/ui/a_cut_is_named_test.dart';

  test('a changed test file green here with the same inputs still runs, and '
      'is named as run for that', () {
    final past = pastTheCache(
      [changedTest, unchanged, redBefore],
      green: {changedTest, unchanged},
      changed: {changedTest},
    );
    expect(past.left, [changedTest, redBefore]);
    expect(past.letGo, {unchanged});
    expect(past.kept, [changedTest]);
  });

  test('a run whose every file is green here still runs the changed one', () {
    final past = pastTheCache(
      [changedTest, unchanged],
      green: {changedTest, unchanged},
      changed: {changedTest},
    );
    expect(past.left, [changedTest]);
  });

  test('a changed test file the cache does not hold runs without being named '
      'as kept', () {
    final past = pastTheCache(
      [changedTest, unchanged],
      green: {unchanged},
      changed: {changedTest},
    );
    expect(past.left, [changedTest]);
    expect(past.kept, isEmpty);
  });

  test('with nothing changed, every green file is let go', () {
    final past = pastTheCache(
      [changedTest, unchanged, redBefore],
      green: {changedTest, unchanged},
      changed: const {},
    );
    expect(past.left, [redBefore]);
    expect(past.letGo, {changedTest, unchanged});
  });
}
