import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨card one-red-pan-cost-test-reddens-the-rest (2026-11-25): a test takes
/// the tree it pumped down before what it handed that tree is let go of,
/// through one helper — `theTreeGoesFirst` (test/helpers/
/// the_tree_goes_first.dart), where the order and its measurement are said.
/// ↩️52 tests wrote the tear-down by hand, each with a note of why; the
/// tests that let a stroke overlay go without it were the reds that
/// reddened the test after them.
void main() {
  final byHand = RegExp(
    r'addTearDown\(\s*\(\)\s*(?:async\s*)?(?:=>|\{)\s*(?:await\s+)?'
    r'tester\.pumpWidget\(',
  );
  const helper = 'test/helpers/the_tree_goes_first.dart';

  test('⛔premise: the scan sees the tear-down where it is written', () {
    expect(byHand.hasMatch(File(helper).readAsStringSync()), isTrue);
  });

  test('no test takes its tree down with a tear-down of its own', () {
    expect(
      [
        for (final file in dartFilesUnder('test'))
          if (file.path.replaceAll(r'\', '/') != helper &&
              byHand.hasMatch(file.readAsStringSync()))
            file.path.replaceAll(r'\', '/'),
      ],
      isEmpty,
      reason: 'call theTreeGoesFirst(tester) after the tear-downs of what '
          'the tree is handed',
    );
  });
}
