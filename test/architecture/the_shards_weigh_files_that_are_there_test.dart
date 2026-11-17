import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _action = '.github/actions/test-shard/action.yml';

/// 🚨THE FILES A SHARD WEIGHS BY ARE THERE.
///
/// The test shards weigh the tests that open the app three times their size
/// (ci-takes-an-hour-on-lavapipe, 2026-11-17), and find them as the tests
/// that reach the files [_action] names to tool/tests_reaching_files.dart.
/// A rename of one would stop every shard at its deal on CI — a round of
/// the bundle PR lost — so the landing's architecture run says it first.
void main() {
  test('every file the shard action weighs by is in the tree', () {
    final call = RegExp(
      r'dart tool/tests_reaching_files\.dart((?:\s*\\?\s*lib/\S+)+)',
    ).firstMatch(File(_action).readAsStringSync());
    expect(call, isNotNull, reason: '$_action no longer calls the tool');
    final named = RegExp(r'lib/\S+')
        .allMatches(call![1]!)
        .map((m) => m[0]!)
        .toList();
    expect(named, isNotEmpty, reason: 'the scan reads the call');
    expect(
      [
        for (final path in named)
          if (!File(path).existsSync()) path,
      ],
      isEmpty,
      reason: 'a renamed file leaves the deal on nothing',
    );
  });
}
