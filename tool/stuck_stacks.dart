import 'dart:io';

import 'process_tree.dart';

/// 🚨WHERE A STOPPED BATCH STOOD, SAID BEFORE IT IS CUT.
///
/// 🗣️관제 2026-11-24 07:3x (card release-2026-11-24): a Linux CI shard
/// cut a batch after fifteen minutes with no test finished, twice, and
/// nothing told what its testers were doing — 브러시 found in WSL that the
/// engine (Rust) does not stop there, and the four files that stopped all
/// go through Dart's stamp landing or HomePage. So before [cutTree], every
/// `flutter_tester` of the batch leaves its threads in the log: the next run
/// that stops names where. ⛔A run that does not stop does nothing here — no
/// tool is looked for, nothing installed (관제: 「멈추지 않으면 아무것도 안
/// 한다」).
///
/// Each platform keeps the same law its own way: Linux, every native
/// thread's backtrace from gdb (installed on the spot on a CI runner that
/// lacks it — the runner is ours to change, the user's machine is not);
/// macOS, lldb's; Windows, the minidump the native call watch already
/// writes from outside the process (test/helpers/native_call_watch_dump.dart
/// — the same code, not a second dumper), in build/native_call_watch, which
/// the Windows shards keep from a red run. A platform without its tool says
/// so by name and the cut goes on.
///
/// ⚠️NOT THE DART STACK: these are the native threads. Dart code the JIT
/// compiled shows as frames without names; what the UI thread waits in,
/// or that it spins in compiled Dart, is what they can tell.

/// How long one tester's dump may take before it is given up — a debugger
/// can stop on a process too.
const kStackPatience = Duration(minutes: 2);

/// What runs to dump [tester] on [os]: the debugger and its arguments, or
/// why none can — [tools] says which of `gdb`, `lldb`, `sudo` (one that asks
/// no password) and the SDK's `dart` this machine has, each by its path.
({String? executable, List<String> arguments, String? none}) stackCommand(
  String os,
  int tester, {
  required Map<String, String> tools,
  required String dumps,
}) {
  switch (os) {
    case 'linux':
      final gdb = tools['gdb'];
      if (gdb == null) {
        return (executable: null, arguments: const [], none: 'no gdb here');
      }
      final asGdb = [
        '-p', '$tester', '-batch', '-nx',
        '-ex', 'thread apply all bt', '-ex', 'detach',
      ];
      // A runner's ptrace is limited to a process's own children
      // (Yama's ptrace_scope 1): another's tester needs root.
      final sudo = tools['sudo'];
      return sudo == null
          ? (executable: gdb, arguments: asGdb, none: null)
          : (executable: sudo, arguments: ['-n', gdb, ...asGdb], none: null);
    case 'macos':
      final lldb = tools['lldb'];
      if (lldb == null) {
        return (executable: null, arguments: const [], none: 'no lldb here');
      }
      return (
        executable: lldb,
        arguments: [
          '-p', '$tester', '--batch',
          '-o', 'thread backtrace all', '-o', 'detach',
        ],
        none: null,
      );
    case 'windows':
      final dart = tools['dart'];
      if (dart == null) {
        return (executable: null, arguments: const [], none: 'no dart here');
      }
      return (
        executable: dart,
        arguments: [
          kDumper,
          '$tester',
          '$dumps${Platform.pathSeparator}stuck-tester-$tester.dmp',
        ],
        none: null,
      );
  }
  return (executable: null, arguments: const [], none: 'no dumper for $os');
}

/// The native call watch's minidump writer, run from outside the process
/// it dumps.
const kDumper = 'test/helpers/native_call_watch_dump.dart';

/// Where the Windows dumps go — the folder the Windows shards keep.
const kStuckDumps = 'build/native_call_watch';

/// Says, through [say], the threads of every `flutter_tester` under [root]
/// — the batch about to be cut.
Future<void> sayWhereTestersStand(
  int root, {
  required void Function(String line) say,
}) async {
  final testers = [
    for (final row in treeIn(readProcessTable(), root))
      if (row.name.contains('flutter_tester')) row.pid,
  ];
  if (testers.isEmpty) {
    say('no flutter_tester under the batch to take the threads of');
    return;
  }
  final os = Platform.operatingSystem;
  final tools = await _toolsFor(os);
  if (os == 'windows') Directory(kStuckDumps).createSync(recursive: true);
  for (final tester in testers) {
    final command = stackCommand(os, tester, tools: tools, dumps: kStuckDumps);
    final executable = command.executable;
    if (executable == null) {
      say('flutter_tester $tester: its threads are not taken — '
          '${command.none}');
      continue;
    }
    say('flutter_tester $tester — its threads as they stand:');
    try {
      // Started, not run: a debugger given up on is killed, or it would
      // hold the tester it is attached to.
      final dumping = await Process.start(executable, command.arguments);
      final said = [
        dumping.stdout.transform(systemEncoding.decoder).join(),
        dumping.stderr.transform(systemEncoding.decoder).join(),
      ];
      final code = await dumping.exitCode.timeout(
        kStackPatience,
        onTimeout: () {
          dumping.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      for (final line in (await Future.wait(said)).join('\n').split('\n')) {
        if (line.trim().isNotEmpty) say('  $line');
      }
      if (code == -1) say('  given up after ${kStackPatience.inMinutes} min');
      if (os == 'windows' && code == 0) {
        say('  (the minidump: ${command.arguments.last})');
      }
    } on Object catch (error) {
      say('  not taken: $error');
    }
  }
}

/// The tools [stackCommand] asks for, found on this machine — and gdb put
/// on a CI runner that lacks it.
Future<Map<String, String>> _toolsFor(String os) async {
  final tools = <String, String>{};
  Future<String?> where(String name) async {
    final found = await Process.run('sh', ['-c', 'command -v $name']);
    final path = '${found.stdout}'.trim();
    return found.exitCode == 0 && path.isNotEmpty ? path : null;
  }

  switch (os) {
    case 'linux':
      final asks = await Process.run('sudo', ['-n', 'true']).then(
        (ran) => ran.exitCode == 0,
        onError: (Object _) => false,
      );
      if (asks) tools['sudo'] = 'sudo';
      var gdb = await where('gdb');
      if (gdb == null && asks && Platform.environment['CI'] == 'true') {
        await Process.run('sudo', [
          '-n', 'apt-get', 'install', '-y', '--no-install-recommends', 'gdb',
        ]).timeout(kStackPatience, onTimeout: () => ProcessResult(0, 1, '', ''));
        gdb = await where('gdb');
      }
      if (gdb != null) tools['gdb'] = gdb;
    case 'macos':
      final lldb = await where('lldb');
      if (lldb != null) tools['lldb'] = lldb;
    case 'windows':
      tools['dart'] = Platform.resolvedExecutable;
  }
  return tools;
}
