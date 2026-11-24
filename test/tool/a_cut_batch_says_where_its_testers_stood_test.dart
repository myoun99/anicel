import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/stuck_stacks.dart';

/// 🗣️관제 2026-11-24 07:3x (card release-2026-11-24): a batch cut for
/// fifteen minutes with no test finished says first where each of its
/// testers stood — so the next Linux CI run that stops names it. Run by
/// hand on the main PC (2026-11-24): a fake `flutter_tester.exe` under a
/// script that called [sayWhereTestersStand] was found and left its
/// minidump. ⚠️gdb and lldb were not run by hand — this machine's WSL has
/// no gdb, and installing one is the user's to allow — so the first Linux
/// CI run that stops is their first run. The suite starts no process, so
/// here the plan is pinned, and the cut asking for it.
void main() {
  const tools = {
    'gdb': '/usr/bin/gdb',
    'sudo': 'sudo',
    'lldb': '/usr/bin/lldb',
    'dart': r'C:\flutter\bin\cache\dart-sdk\bin\dart.exe',
  };

  test('Linux takes every native thread from gdb, as root where it can', () {
    final asked = stackCommand('linux', 42, tools: tools, dumps: 'd');
    expect(asked.executable, 'sudo');
    expect(asked.arguments, [
      '-n', '/usr/bin/gdb', '-p', '42', '-batch', '-nx',
      '-ex', 'thread apply all bt', '-ex', 'detach',
    ]);
    final alone = stackCommand(
      'linux',
      42,
      tools: {'gdb': '/usr/bin/gdb'},
      dumps: 'd',
    );
    expect(alone.executable, '/usr/bin/gdb');
    expect(alone.arguments.first, '-p');
  });

  test('macOS takes them from lldb; Windows writes the minidump the native '
      'call watch writes, with its writer', () {
    final mac = stackCommand('macos', 7, tools: tools, dumps: 'd');
    expect(mac.executable, '/usr/bin/lldb');
    expect(mac.arguments, contains('thread backtrace all'));
    final windows = stackCommand('windows', 7, tools: tools, dumps: 'd');
    expect(windows.executable, tools['dart']);
    expect(windows.arguments.first, kDumper);
    expect(windows.arguments[1], '7');
    expect(File(kDumper).existsSync(), isTrue, reason: 'LIVENESS');
    expect(
      File('.github/workflows/ci.yml').readAsStringSync(),
      contains('path: $kStuckDumps/'),
      reason: 'the folder the Windows shards keep from a red run',
    );
  });

  test('a platform without its tool says so by name', () {
    for (final os in ['linux', 'macos', 'windows', 'fuchsia']) {
      final none = stackCommand(os, 1, tools: const {}, dumps: 'd');
      expect(none.executable, isNull, reason: os);
      expect(none.none, isNotEmpty, reason: os);
    }
  });

  test('🚨the cut asks for the threads, and only then cuts', () {
    final source = File('tool/affected_tests.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(
      source,
      contains('    silent = true;\n'
          '    // 🗣️관제 2026-11-24 07:3x: where it stood, said before it is cut\n'
          '    // (stuck_stacks.dart says why).\n'
          '    await sayWhereTestersStand(process.pid, say: _report);\n'
          '    final cut = cutTree(process.pid);\n'
          '    _report(cutSaid(cut, await stillStanding(cut)));\n'),
    );
    final stacks = File('tool/stuck_stacks.dart').readAsStringSync();
    expect(
      stacks,
      contains("Platform.environment['CI'] == 'true'"),
      reason: 'gdb is put on a CI runner only — never on a machine of ours',
    );
  });
}
