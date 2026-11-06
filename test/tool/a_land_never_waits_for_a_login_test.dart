import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/lane_script.dart';

/// 🚨lane-land-hangs-on-mirror-login (2026-09-24): `land` pushed the mirror
/// with git-credential-manager free to wait for a login. A land runs
/// unattended, so with no saved login it never returned — the trunk's
/// engine was not rebuilt and the copy was not made. Its push must refuse
/// to ask; `backup`, which a person runs, must still ask so they can log in
/// there.
///
/// ↩️2026-11-05 (관제, gpu-engine-skeleton): only the land's calls refused.
/// The mirror's login lapsed, and three credential managers stood waiting
/// at a window nobody would see — `backup`, `sync`, `send` and `unsend`
/// still asked, whoever ran them. Every call to the mirror now goes through
/// `mirror_git`, which asks nobody and gives up after a while; `backup`
/// asks only when a person runs it, at a terminal.
void main() {
  final lane = LaneScript(File('tool/lane.sh').readAsStringSync());
  final script = lane.text;

  test('🚨every call that reaches the mirror goes through mirror_git', () {
    // A command continued over lines is read as one.
    final commands = script.replaceAll(RegExp(r'\\\n\s*'), ' ').split('\n');
    final calls = [
      for (final line in commands)
        if (!line.trimLeft().startsWith('#') &&
            line.contains(r'"$MIRROR"') &&
            RegExp(r'\b(push|fetch|ls-remote)\b').hasMatch(line))
          line.trim(),
    ];
    expect(calls, hasLength(greaterThan(10)), reason: 'LIVENESS');
    expect(
      [
        for (final call in calls)
          if (!call.contains('mirror_git ')) call,
      ],
      isEmpty,
    );
  });

  test('which asks for no login, and gives up after MIRROR_WAIT — unless '
      'a backup at a terminal asked it to ask', () {
    final git = lane.codeOf('mirror_git');
    int at(String text) => git.indexWhere((line) => line.contains(text));

    final asks = at(r'if [ -n "${MIRROR_ASKS:-}" ]; then');
    final refuses = at(
      r'GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never timeout "$MIRROR_WAIT" '
      r'git -C "$ROOT" "$@"',
    );
    expect(asks, isNot(-1));
    expect(refuses, greaterThan(at('else')));
    expect(at('else'), greaterThan(asks));
    expect(script, contains('\nMIRROR_WAIT=120\n'));
    expect(script, contains('\nMIRROR_ASKS=\n'));
  });

  test('backup, which a person runs, still asks — at a terminal, and only '
      'there', () {
    final backup = lane.codeOf('cmd_backup');
    expect(backup.join('\n'), contains('local missed= MIRROR_ASKS='));
    final terminal = backup.indexWhere(
      (line) => line.trim() == '[ -t 0 ] && MIRROR_ASKS=1',
    );
    expect(terminal, isNot(-1));
    expect(
      terminal,
      lessThan(backup.indexWhere((line) => line.contains('mirror_trunk'))),
    );
    bool sets(String function) =>
        lane.codeOf(function).any((line) => line.contains('MIRROR_ASKS=1'));
    expect(
      [
        for (final function in lane.functions)
          if (function != 'cmd_backup' && sets(function)) function,
      ],
      isEmpty,
      reason: 'asking is the backup\'s alone',
    );
  });

  // 2026-10-08: the mirror's login was gone. `backup` printed its two
  // warnings, then 「mirrored master and 24 open lane(s)」, and returned 0 —
  // the one command whose whole job is the copy, saying it had made it.
  test('🚨a backup says 「mirrored」 only after its copies reached the '
      'mirror, and fails when they did not', () {
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
}
