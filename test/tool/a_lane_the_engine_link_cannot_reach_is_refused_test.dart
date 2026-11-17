import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/lane_script.dart';

/// The engine's build hook links through a junction it stands in the lane,
/// and link.exe stops at 259 characters: on the Surface a lane named 30
/// characters died at the link with LNK1104, which reads like a full disk
/// (card a-long-lane-name-breaks-the-engine-link, 저장 2026-11-17). So both
/// ways a worktree is made — `open` and `receive` — measure the lane's path
/// against the deepest file the link opens (`fits_the_link`) BEFORE the
/// worktree is added: refused after it, the lane would be there, half made.
/// 🧪What the measure does was run by hand on the main PC that day: a
/// 36-character name opens, 37 is refused at 260, and the Surface's
/// `surface11-memory-watch-test-speaks-to-it` at 263.
void main() {
  final script = LaneScript(File('tool/lane.sh').readAsStringSync());

  for (final command in ['cmd_open', 'cmd_receive']) {
    test('$command measures the path before it adds the worktree', () {
      final code = script.codeOf(command);
      final measured = code.indexWhere(
        (line) => line.trim() == r'fits_the_link "$p"',
      );
      final added = code.indexWhere(
        (line) => line.contains(r'worktree add "$p"'),
      );
      expect(added, isNot(-1), reason: 'LIVENESS — $command adds one');
      expect(measured, isNot(-1), reason: '$command measures the path');
      expect(measured, lessThan(added));
    });
  }

  test('the measure is the deepest link input under the hook folder, '
      'against 259', () {
    final code = script.codeOf('fits_the_link').join('\n');
    expect(code, contains('target-hook'));
    expect(code, contains("-path '*/deps/*'"));
    expect(code, contains('-le 259'));
  });
}
