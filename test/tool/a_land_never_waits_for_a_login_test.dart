import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨lane-land-hangs-on-mirror-login (2026-09-24): `land` pushed the mirror
/// with git-credential-manager free to wait for a login. A land runs
/// unattended, so with no saved login it never returned — the trunk's
/// engine was not rebuilt and the copy was not made. Its push must refuse
/// to ask; `backup`, which a person runs, must still ask so they can log in
/// there.
void main() {
  final script = File('tool/lane.sh').readAsStringSync().replaceAll(
    '\r\n',
    '\n',
  );

  String body(String function) {
    final start = script.indexOf('\n$function() {');
    expect(start, isNot(-1), reason: 'LIVENESS — $function is in the script');
    return script.substring(start, script.indexOf('\n}\n', start));
  }

  test('the land pushes the mirror without asking for a login', () {
    final pushes = [
      for (final line in body('cmd_land').split('\n'))
        if (line.trim().endsWith('mirror_trunk')) line,
    ];
    expect(pushes, hasLength(1), reason: 'LIVENESS — a land pushes once');
    expect(pushes.single, contains('GIT_TERMINAL_PROMPT=0'));
    expect(pushes.single, contains('GCM_INTERACTIVE=Never'));
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
