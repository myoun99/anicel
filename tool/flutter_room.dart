// Is there room on this machine for one more Flutter run?
//
//   dart tool/flutter_room.dart          runs=<n> free_gb=<n> room=<yes|no>
//   dart tool/flutter_room.dart --land   the same, asked for a land's gates
//   dart tool/flutter_room.dart --list   … and every run there is, with
//                                        whose it is
//
// `dart`, not `dart run`: nothing here comes from a package, so it starts
// without resolving any — the lane script asks before every gate.
//
// THE RULE IT MEASURES is CLAUDE.md's 「Flutter 실행은 여유만큼」 (유저
// 2026-09-26 · 10-01): before a run is launched, 4GB of commit headroom
// and fewer than four runs across every session. ⛔Not CPU% — the runs are
// Idle and keep it high whenever anything runs at all.
//
// 🚨ONE PLACE COUNTS (card a-sent-lane-is-gated-once). Until 2026-10-08
// every session counted with a script of its own, and each of them counted
// 「every dart.exe whose command line names the Flutter tool」. The 관제
// session measured that night: six such processes while the sessions had
// THREE runs going.
//   · Two were Android Studio's — `flutter daemon` and the debug app's
//     `flutter run`. Asked on the board whether what the user launches by
//     hand takes one of the four, 유저 chose 「세션이 띄운 것만 센다」
//     (a-sent-lane-is-gated-once-Q2, 10-08) — a build run by hand, release
//     ones too, is in that answer by name.
//   · One was a build step (`flutter assemble`) that a device integration
//     test had launched under itself: one run, counted twice.
// And a land's gates take none of the four: 유저 chose 「전해진 대로
// 넣는다」 (a-sent-lane-is-gated-once-Q1, 10-08) for 「착지 게이트는 이
// 넷에 세지 않는다 — 커밋 여유 4GB 는 똑같이 재고, 우선순위도 Idle
// 그대로」. So `--land` asks for the headroom alone, and what a landing
// lane's gates launch is not counted against anyone else.
//
// Exit codes: 0 room · 1 no room · 2 could not measure.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The runs every session together may have going (유저 2026-10-01).
const kFlutterPlaces = 4;

/// The commit headroom — RAM and page file — a launch asks for, in GB
/// (유저 2026-10-01; ten runs at once had emptied it).
const kHeadroomGb = 4;

/// The directory a land holds for as long as it lands, in the repository's
/// own .git. `tool/lane.sh` makes it and writes its own pid inside.
const kLandTurn = 'lane-land.turn';

/// What makes a process the Flutter tool: its command line names the
/// tool's snapshot.
const _toolMark = 'flutter_tools.snapshot';

/// A session's processes hang under this one (measured 2026-10-08:
/// `bash.exe < bash.exe < claude.exe < claude.exe`).
const _aSession = 'claude.exe';

/// Under one of these — and under no session — a run is the user's own:
/// Android Studio's helper and its debug app, a build from a terminal the
/// user opened.
const _theUsersOwn = {'studio64.exe', 'explorer.exe'};

/// One process as Windows lists it.
class WindowsProcess {
  const WindowsProcess({
    required this.pid,
    required this.parent,
    required this.name,
    this.born = 0,
    this.asked,
  });

  final int pid;
  final int parent;
  final String name;

  /// When it started — a number that only orders. A pid is handed out
  /// again once its process is gone, so a 「parent」 born after its child
  /// is somebody else wearing a dead parent's number.
  final int born;

  /// What the Flutter tool was asked to do; null for every other process.
  final String? asked;
}

/// One process as Git Bash's own table lists it (`ps -l`).
///
/// ⚠️Why Windows' parents are not enough. When one bash program hands over
/// to another (`exec` — `flutter` is a bash script), Windows starts a new
/// process and the one that started it exits. Every run launched from Git
/// Bash therefore ends, on Windows' side, at a `bash.exe` whose parent is
/// gone (measured 2026-10-08: `dart.exe < cmd.exe < bash.exe`, nothing
/// above). Bash's own table still knows who launched whom.
class BashProcess {
  const BashProcess({
    required this.pid,
    required this.parent,
    required this.winPid,
  });

  final int pid;
  final int parent;

  /// The Windows process this row stands for — the program it handed over
  /// to, when that one is not a bash program.
  final int winPid;
}

/// Whose a Flutter run is, and whether it takes one of the four.
enum RunOf {
  session("a session's", takesAPlace: true),

  /// ⚠️Nobody above it can be named: a run whose session is gone (a stopped
  /// task leaves its children running), or a bash table that could not be
  /// read. It runs all the same, and nothing says it is the user's.
  nobody('launched by nobody that can be named', takesAPlace: true),
  user("the user's own", takesAPlace: false),
  land("a land's gate", takesAPlace: false);

  const RunOf(this.words, {required this.takesAPlace});

  final String words;
  final bool takesAPlace;
}

/// One Flutter run: a Flutter tool that no other Flutter tool launched.
class FlutterRun {
  const FlutterRun({required this.pid, required this.asked, required this.of});

  final int pid;
  final String asked;
  final RunOf of;
}

/// The machine's processes, and who launched whom.
class Machine {
  Machine({
    required Iterable<WindowsProcess> windows,
    Iterable<BashProcess> bash = const [],
  }) : _windows = {for (final process in windows) process.pid: process},
       _bash = {for (final process in bash) process.pid: process},
       _bashAt = {for (final process in bash) process.winPid: process};

  final Map<int, WindowsProcess> _windows;
  final Map<int, BashProcess> _bash;
  final Map<int, BashProcess> _bashAt;

  /// Every Flutter run there is, and whose each one is. [landHolder] is
  /// the number the land holding the turn wrote down (bash's own pid for
  /// it), when one is landing.
  ///
  /// ⚠️ROOTS ONLY. One run is several processes that carry the tool's
  /// name: `dart.exe` and the `dartvm.exe` under it, and whatever tool a
  /// run launches under itself (`flutter assemble` under a device test).
  List<FlutterRun> flutterRuns({int? landHolder}) {
    final tools = {
      for (final process in _windows.values)
        if (process.asked != null) process.pid,
    };
    final landing = _bash[landHolder]?.winPid;
    final runs = <FlutterRun>[];
    for (final pid in tools) {
      final above = _above(pid);
      if (above.any(tools.contains)) continue;
      runs.add(
        FlutterRun(
          pid: pid,
          asked: _windows[pid]!.asked!,
          of: _whose(above, landing),
        ),
      );
    }
    return runs;
  }

  RunOf _whose(Set<int> above, int? landing) {
    if (landing != null && above.contains(landing)) return RunOf.land;
    final names = {
      for (final pid in above) ?_windows[pid]?.name.toLowerCase(),
    };
    if (names.contains(_aSession)) return RunOf.session;
    if (names.any(_theUsersOwn.contains)) return RunOf.user;
    return RunOf.nobody;
  }

  /// Everything that launched [pid], however far up, by either table.
  Set<int> _above(int pid) {
    final seen = <int>{};
    final ahead = [pid];
    while (ahead.isNotEmpty) {
      for (final parent in _launchersOf(ahead.removeLast())) {
        if (seen.add(parent)) ahead.add(parent);
      }
    }
    return seen..remove(pid);
  }

  Iterable<int> _launchersOf(int pid) sync* {
    final process = _windows[pid];
    final parent = _windows[process?.parent];
    if (process != null && parent != null && parent.born <= process.born) {
      yield parent.pid;
    }
    final launcher = _bash[_bashAt[pid]?.parent];
    if (launcher != null) yield launcher.winPid;
  }
}

/// Whether one more run may be launched now. A land's gates ([aLand]) are
/// asked for the headroom alone.
bool roomFor({
  required int taken,
  required int freeGb,
  required bool aLand,
}) => freeGb >= kHeadroomGb && (aLand || taken < kFlutterPlaces);

/// What PowerShell is asked: the free commit, then every process — and of
/// a command line only what the Flutter tool was asked to do, so nothing
/// else that was typed on this machine travels through here.
const _ask =
    "\$mark = '$_toolMark'\n"
    r'''
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
"free`t$((Get-CimInstance Win32_OperatingSystem).FreeVirtualMemory)"
$wanted = 'ProcessId', 'ParentProcessId', 'Name', 'CommandLine', 'CreationDate'
foreach ($p in Get-CimInstance Win32_Process -Property $wanted) {
  $born = 0
  if ($null -ne $p.CreationDate) { $born = $p.CreationDate.Ticks }
  $tool = 0
  $asked = ''
  if ($null -ne $p.CommandLine) {
    $at = $p.CommandLine.IndexOf($mark)
    if ($at -ge 0) {
      $tool = 1
      $rest = $p.CommandLine.Substring($at + $mark.Length).TrimStart('"')
      $asked = ($rest -replace '\s+', ' ').Trim()
    }
  }
  $cells = 'proc', $p.ProcessId, $p.ParentProcessId, $born, $tool, $p.Name
  ($cells + $asked) -join "`t"
}
''';

/// The free commit in GB and the processes, out of what [_ask] printed —
/// null when that is not an answer.
({int freeGb, List<WindowsProcess> processes})? windowsAnswerFrom(
  String text,
) {
  int? freeGb;
  final processes = <WindowsProcess>[];
  for (final line in const LineSplitter().convert(text)) {
    final cells = line.split('\t');
    if (cells.first == 'free' && cells.length == 2) {
      final kb = int.tryParse(cells[1]);
      if (kb != null) freeGb = kb ~/ (1024 * 1024);
    }
    if (cells.first != 'proc' || cells.length != 7) continue;
    final pid = int.tryParse(cells[1]);
    final parent = int.tryParse(cells[2]);
    if (pid == null || parent == null) continue;
    processes.add(
      WindowsProcess(
        pid: pid,
        parent: parent,
        born: int.tryParse(cells[3]) ?? 0,
        name: cells[5],
        asked: cells[4] == '1' ? cells[6] : null,
      ),
    );
  }
  if (freeGb == null || processes.isEmpty) return null;
  return (freeGb: freeGb, processes: processes);
}

/// Bash's table out of what `ps -l` printed: PID, PPID, PGID, WINPID …,
/// behind a state letter on some rows.
List<BashProcess> bashTableFrom(String text) {
  final row = RegExp(r'^\s*[A-Z]?\s*(\d+)\s+(\d+)\s+\d+\s+(\d+)\s');
  return [
    for (final line in const LineSplitter().convert(text))
      if (row.firstMatch(line) case final found?)
        BashProcess(
          pid: int.parse(found[1]!),
          parent: int.parse(found[2]!),
          winPid: int.parse(found[3]!),
        ),
  ];
}

Future<({int freeGb, List<WindowsProcess> processes})?> _askWindows() async {
  if (!Platform.isWindows) return null;
  // The script travels encoded: no quoting of its own survives two command
  // lines otherwise.
  final units = <int>[
    for (final unit in _ask.codeUnits) ...[unit & 0xff, unit >> 8],
  ];
  try {
    final asked = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      base64.encode(units),
    ], stdoutEncoding: null).timeout(const Duration(minutes: 1));
    if (asked.exitCode != 0) return null;
    return windowsAnswerFrom(
      utf8.decode(asked.stdout as List<int>, allowMalformed: true),
    );
  } on ProcessException {
    return null;
  } on TimeoutException {
    return null;
  }
}

/// Bash's table, or nothing when no `ps` of Git Bash's is on the path
/// (asked from PowerShell): every run launched from bash then ends where
/// Windows' parents end, and takes a place.
List<BashProcess> _bashTable() {
  try {
    final asked = Process.runSync('ps', ['-l']);
    return asked.exitCode == 0
        ? bashTableFrom(asked.stdout as String)
        : const [];
  } on ProcessException {
    return const [];
  }
}

/// The number the landing lane's script wrote into its turn, if a land is
/// under way in this repository.
int? _landHolder() {
  try {
    final git = Process.runSync('git', [
      'rev-parse',
      '--path-format=absolute',
      '--git-common-dir',
    ], workingDirectory: File.fromUri(Platform.script).parent.path);
    if (git.exitCode != 0) return null;
    final pid = File('${(git.stdout as String).trim()}/$kLandTurn/pid');
    return int.tryParse(pid.readAsStringSync().trim());
  } on ProcessException {
    return null;
  } on FileSystemException {
    return null;
  }
}

Future<void> main(List<String> args) async {
  const known = {'--land', '--list'};
  if (!args.every(known.contains)) {
    stderr.writeln('usage: dart tool/flutter_room.dart [--land] [--list]');
    exitCode = 2;
    return;
  }
  final answer = await _askWindows();
  if (answer == null) {
    stderr.writeln(
      'flutter_room: this machine could not be measured (Windows was asked '
      'through powershell.exe)',
    );
    exitCode = 2;
    return;
  }
  final bash = _bashTable();
  final runs = Machine(
    windows: answer.processes,
    bash: bash,
  ).flutterRuns(landHolder: _landHolder());
  final taken = runs.where((run) => run.of.takesAPlace).length;
  final room = roomFor(
    taken: taken,
    freeGb: answer.freeGb,
    aLand: args.contains('--land'),
  );
  stdout.writeln(
    'runs=$taken free_gb=${answer.freeGb} room=${room ? 'yes' : 'no'}',
  );
  if (args.contains('--list')) {
    for (final run in runs) {
      final counted = run.of.takesAPlace ? 'counted' : 'not counted';
      final asked = run.asked.length > 90
          ? '${run.asked.substring(0, 90)}…'
          : run.asked;
      stdout.writeln('  $counted — ${run.of.words}: pid ${run.pid}  $asked');
    }
    if (bash.isEmpty) {
      stdout.writeln("  (Git Bash's own table could not be read)");
    }
  }
  exitCode = room ? 0 : 1;
}
