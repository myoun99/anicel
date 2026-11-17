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
/// `surface11-memory-watch-test-speaks-to-it` at 263. Counting the Windows
/// libraries alone (22:3x): 38 opens, 39 is refused at 260, that name at
/// 261, `surface11-denoise-off-ui` opens; and in a made-up hook folder a
/// 60-character name opens past long Android libraries, compile objects and
/// a folder inside `deps`, and is refused once a host library is as long.
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

  // ↩️관제 2026-11-17 22:16: every file under any `deps` was counted, and a
  // Surface lane at 247 was refused at 275 — what rustc writes there while
  // it compiles, and Android's folders, are nothing link.exe opens.
  test('it counts only the libraries in a Windows `deps` — the target\'s and '
      'the host\'s — and nothing in a folder within', () {
    final code = script.codeOf('fits_the_link').join('\n');
    expect(code, contains("! -path '*/deps/*/*'"));
    expect(
      code,
      contains(r"\( -path './*-pc-windows-msvc/*' -o -path './release/*' "
          r"-o -path './debug/*' \)"),
    );
    expect(code, contains(r"\( -name '*.rlib' -o -name '*.lib' \)"));
  });
}
