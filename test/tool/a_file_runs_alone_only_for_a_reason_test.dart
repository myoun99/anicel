@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_bundles.dart' show bundlesOf, kRunsAlone;

/// 🗣️관제 2026-11-20 (card the-wide-check-takes-five-hours): the files that
/// run alone are a ledger, each with its reason and the whole counted — as
/// `test/architecture/layer_dependency_direction_test.dart` keeps its own.
/// A file joins it by the census (red in a bundle, green alone — or a wait
/// a bundle made run out), and leaves it when its test stops leaning on
/// what company changes.
void main() {
  test('every file the ledger runs alone is a test file that is there', () {
    expect(
      [
        for (final file in kRunsAlone.keys)
          if (!file.startsWith('test/') ||
              !file.endsWith('_test.dart') ||
              !File(file).existsSync())
            file,
      ],
      isEmpty,
      reason: 'a ledgered file that is gone ran alone for nothing — delete '
          'its line',
    );
  });

  test('each says what it leans on, and where it was seen', () {
    expect(
      [
        for (final MapEntry(key: file, value: reason) in kRunsAlone.entries)
          if (reason.trim().length < 40 || !reason.contains('census')) file,
      ],
      isEmpty,
    );
  });

  test('a ledgered file is run as a file of its own, the rest bundled', () {
    final ledgered = kRunsAlone.keys.first;
    final cut = bundlesOf([
      ledgered,
      'test/a_test.dart',
      'test/b_test.dart',
    ], read: (path) => 'void main() {}');
    expect(cut.alone, [ledgered]);
    expect(cut.bundles, [
      ['test/a_test.dart', 'test/b_test.dart'],
    ]);
  });

  test('the ledger is the whole of it, counted', () {
    expect(
      kRunsAlone,
      hasLength(45),
      reason: 'Going DOWN is the point — update this number with it. Going '
          'UP needs the census line that shows the file red in a bundle and '
          'green alone.',
    );
  });
}
