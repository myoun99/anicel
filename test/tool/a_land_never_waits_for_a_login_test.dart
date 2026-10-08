import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/lane_script.dart';

/// 🚨lane-land-hangs-on-mirror-login (2026-09-24): `land` pushed the mirror
/// with git-credential-manager free to wait for a login. A land runs
/// unattended, so with no saved login it never returned — the trunk's
/// engine was not rebuilt and the copy was not made. Its push must refuse
/// to ask; `backup`, which a person runs, must still ask so they can log in
/// there.
void main() {
  final body = LaneScript(File('tool/lane.sh').readAsStringSync()).body;

  test('the land pushes the mirror without asking for a login', () {
    final pushes = [
      for (final line in body('cmd_land').split('\n'))
        if (line.trim().endsWith('mirror_trunk')) line,
    ];
    expect(pushes, hasLength(1), reason: 'LIVENESS — a land pushes once');
    expect(pushes.single, contains('GIT_TERMINAL_PROMPT=0'));
    expect(pushes.single, contains('GCM_INTERACTIVE=Never'));
  });

  // 2026-10-08: the mirror's login was gone. `backup` printed its two
  // warnings, then 「mirrored master and 24 open lane(s)」, and returned 0 —
  // the one command whose whole job is the copy, saying it had made it.
  test('🚨a backup says 「mirrored」 only after its copies reached the '
      'mirror, and fails when they did not', () {
    final lane = LaneScript(File('tool/lane.sh').readAsStringSync());
    final backup = lane.codeOf('cmd_backup');
    int at(String text) => backup.indexWhere((line) => line.contains(text));

    expect(at('mirror_trunk || missed=1'), isNot(-1));
    final refused = at(r'[ -z "$missed" ] || die');
    expect(refused, isNot(-1));
    expect(at(r'echo "lane: mirrored $TRUNK and'), greaterThan(refused));

    final awayRefused = at(r'|| die "the open lanes did not reach $MIRROR');
    expect(awayRefused, isNot(-1));
    expect(at(r'echo "lane: mirrored $(git'), greaterThan(awayRefused));

    expect(
      lane.codeOf('mirror_trunk').lastWhere((line) => line.trim().isNotEmpty),
      '  return 1',
      reason: 'a push that failed is ANSWERED as one — the land goes on '
          'whatever it returns, the backup fails on it',
    );
  });

  test('backup, which a person runs, still asks', () {
    expect(body('cmd_backup'), contains('mirror_trunk'));
    for (final function in ['cmd_backup', 'mirror_trunk']) {
      expect(
        body(function),
        isNot(contains('GCM_INTERACTIVE')),
        reason: 'refusing to ask is the land\'s, not $function\'s',
      );
    }
  });
}
