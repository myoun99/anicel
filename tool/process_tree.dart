import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Ends the process [pid] and every process under it: `flutter test` runs
/// its testers two and three processes down, and ending the shell alone
/// leaves them holding the machine. ⚠️Off Windows only the shell's own
/// children go with it.
void cutTree(int pid) {
  if (Platform.isWindows) {
    Process.runSync('taskkill', ['/PID', '$pid', '/T', '/F']);
  } else {
    Process.runSync('pkill', ['-KILL', '-P', '$pid']);
    Process.killPid(pid, ProcessSignal.sigkill);
  }
}

/// Makes every process this one starts from here on — and every process
/// those start — end when this one ends, however it ends. The job that
/// holds them, or null where none was made; the run goes on either way.
///
/// 🚨A RUN NOBODY WAITS FOR (card
/// a-wide-check-cut-by-an-outer-timeout-leaves-its-runner-running): on
/// 2026-11-13 an outer `timeout` ended `master_check` at 23:57 and it said
/// 「stopped」, while the `affected_tests` it had started at 19:57 was still
/// launching batch 27 at 00:30 — holding the machine's line and the engine
/// hook's turn for a verdict nobody would read, beside a second check in
/// the same worktree. ⇒ Not a [cutTree] on the way out: a process that is
/// killed says no last words. The operating system ends them — a job that
/// kills its processes when its last handle closes, and this process holds
/// its only handle (not one a child inherits).
///
/// ⛔NO WAY OUT OF IT, not even for a process that asks to break away —
/// measured 2026-11-14 on the main PC: with breakaway allowed, the program
/// a bash `exec`ed (as `run.sh` does) left the job and outlived a starter
/// that was killed, the bash itself going with the job. A detached start
/// (`ProcessStartMode.detached`) is still made inside it, and ends with it.
/// ⚠️Off Windows nothing is made — there a tool takes its shell's place
/// (`run.sh` execs it), and a shell's or a `timeout`'s signal reaches the
/// process group the run is in.
int? endWhatThisStartsWithIt() {
  if (!Platform.isWindows) return null;
  final job = _createJob(nullptr, nullptr);
  if (job == 0) return null;
  final limits = calloc<_JobLimits>();
  try {
    limits.ref.basic.flags = _killOnJobClose;
    final made =
        _setJobInformation(
              job,
              _extendedLimitInformation,
              limits,
              sizeOf<_JobLimits>(),
            ) !=
            0 &&
        _assignToJob(job, _thisProcess) != 0;
    if (made) return job;
    _closeHandle(job);
    return null;
  } finally {
    calloc.free(limits);
  }
}

/// One process of the machine, as [readProcessTable] found it: what it has
/// committed in [bytes] (the figure the machine runs out of), when it began
/// in [born], which only ever orders two rows of one table, and the CPU it
/// has spent in [cpu], in 100-nanosecond ticks — 0 where it cannot be read.
typedef ProcessRow = ({
  int pid,
  int parent,
  int born,
  String name,
  int bytes,
  int cpu,
});

const _gib = 1 << 30;

/// The most one process of a test run may commit.
///
/// ⚖️MEASURED 2026-11-09 on the main PC, each process's peak commit as
/// Windows keeps it, through a green `affected_tests --all --no-cache` and
/// what the machine's other sessions ran beside it: of 5,672 testers the
/// largest reached 3.79 GB, the next 3.29 and 2.18, and the compiler under
/// them 1.60. Twice the largest, rounded up, against the 22 GB of the night
/// this was written for. A test that truly needs more is named when it is
/// cut, and raises this with a measurement of its own.
const kMostOneProcessCommits = 8 * _gib;

/// How often a run's memory is read.
const kLookAtMemory = Duration(seconds: 2);

/// Ends the test run at [_pid] the moment one of its processes commits more
/// than [_cap], and says so in [outgrew].
///
/// 🚨WHILE IT RUNS (card a-tester-grew-to-23-gb-and-took-the-desktop-down):
/// `flutter_room` measures before a launch, and on 2026-11-09 three testers
/// launched into plenty grew to 22 GB each until `dwm.exe` died of
/// STATUS_FATAL_MEMORY_EXHAUSTION and the desktop went black, with no time
/// limit having cut them by then.
///
/// ⚖️ONE PROCESS, NOT THE RUN'S SUM: a tester is one test file, so what one
/// may take does not change with how many suites the run was given.
class MemoryWatch {
  MemoryWatch(
    this._pid, {
    int cap = kMostOneProcessCommits,
    List<ProcessRow> Function() read = readProcessTable,
    void Function(int pid) cut = cutTree,
    Duration every = kLookAtMemory,
  }) : _cap = cap,
       _read = read,
       _cut = cut {
    _clock = Timer.periodic(every, (_) => look());
  }

  final int _pid;
  final int _cap;
  final List<ProcessRow> Function() _read;
  final void Function(int pid) _cut;
  late final Timer _clock;

  /// What outgrew the cap, in words — null while nothing has.
  String? outgrew;

  /// Reads the run once, and cuts it if it is past the cap.
  ///
  /// ⚠️NO LATCH: a cut that could not take (`taskkill` is a process to
  /// start, on a machine short of memory) is asked again at the next look.
  void look() {
    final largest = largestInTree(_read(), _pid);
    if (largest == null || largest.bytes <= _cap) return;
    outgrew =
        '${largest.name} (pid ${largest.pid}) reached '
        '${_inGb(largest.bytes)} GB, past the ${_inGb(_cap)} GB one process '
        'of a test run may commit';
    _cut(_pid);
  }

  void stop() => _clock.cancel();
}

String _inGb(int bytes) => (bytes / _gib).toStringAsFixed(1);

/// The largest process under [root] in [table], [root] among them — null
/// when [root] is not in it.
///
/// ⚠️A parent's number outlives the parent and comes round again, so a
/// process older than the one its number now names is not that one's child
/// (the law `flutter_room`'s `_launchersOf` keeps for the walk upwards).
ProcessRow? largestInTree(Iterable<ProcessRow> table, int root) {
  ProcessRow? largest;
  for (final process in treeIn(table, root)) {
    if (largest == null || process.bytes > largest.bytes) largest = process;
  }
  return largest;
}

/// [root] and every process under it in [table] — none when [root] is not
/// in it ([largestInTree] has the law of the walk).
List<ProcessRow> treeIn(Iterable<ProcessRow> table, int root) {
  final children = <int, List<ProcessRow>>{};
  ProcessRow? top;
  for (final row in table) {
    children.putIfAbsent(row.parent, () => []).add(row);
    if (row.pid == root) top = row;
  }
  if (top == null) return const [];
  final tree = [top];
  final seen = {top.pid};
  final ahead = [top];
  while (ahead.isNotEmpty) {
    final process = ahead.removeLast();
    for (final child in children[process.pid] ?? const <ProcessRow>[]) {
      if (child.born >= process.born && seen.add(child.pid)) {
        ahead.add(child);
        tree.add(child);
      }
    }
  }
  return tree;
}

/// What [CpuWatch] saw spent: the watched tree's own, and the rest's by
/// name, most first.
typedef CpuSpent = ({Duration ours, List<(String, Duration)> others});

/// What the machine's processes spend of the CPU while a test batch runs,
/// by name, the batch's own tree ([treeIn] of its root) apart.
///
/// 🔍WHAT ELSE RAN (the-wide-check-takes-five-hours, 2026-11-20): at the
/// same nine suites the wide check's batches of 11-15 and 11-16 took two to
/// three times those of 11-18, and what else the machine was doing then
/// could not be named — the line's record counts its own suites only.
///
/// ⚠️IT LOOKS AS OFTEN AS [MemoryWatch], because a tester lives as long as
/// its one test file: a look at the batch's start and end alone would miss
/// every one another run started and ended in between. A process first
/// seen after the first look is counted from naught; one that lived and
/// ended between two looks is missed.
class CpuWatch {
  CpuWatch(
    this._root, {
    List<ProcessRow> Function() read = readProcessTable,
    Duration every = kLookAtMemory,
  }) : _read = read {
    look();
    _clock = Timer.periodic(every, (_) => look());
  }

  final int _root;
  final List<ProcessRow> Function() _read;
  late final Timer _clock;
  var _looked = false;
  final _from = <(int, int), int>{};
  final _seen = <(int, int), ({String name, int cpu, bool ours})>{};

  /// Reads the machine once.
  void look() {
    final table = _read();
    final ours = {for (final row in treeIn(table, _root)) row.pid};
    for (final row in table) {
      final key = (row.pid, row.born);
      _from.putIfAbsent(key, () => _looked ? 0 : row.cpu);
      _seen[key] = (
        name: row.name,
        cpu: row.cpu,
        ours: ours.contains(row.pid) || (_seen[key]?.ours ?? false),
      );
    }
    _looked = true;
  }

  /// Stops looking, and says what was spent: the batch's own, and the
  /// rest's by name, most first.
  CpuSpent stop() {
    _clock.cancel();
    look();
    var ours = 0;
    final others = <String, int>{};
    for (final MapEntry(:key, value: seen) in _seen.entries) {
      final spent = seen.cpu - _from[key]!;
      if (spent <= 0) continue;
      if (seen.ours) {
        ours += spent;
      } else {
        others[seen.name] = (others[seen.name] ?? 0) + spent;
      }
    }
    Duration of(int ticks) => Duration(microseconds: ticks ~/ 10);
    return (
      ours: of(ours),
      others: [
        for (final MapEntry(:key, :value) in others.entries) (key, of(value)),
      ]..sort((a, b) => b.$2.compareTo(a.$2)),
    );
  }
}

/// The machine's processes; empty when they cannot be read, for a watch
/// that cannot see must not be what fails a run.
///
/// ⛔NOT POWERSHELL, as `flutter_room` asks once before a launch: that is one
/// to two seconds of CPU and a process to start, every look of every run
/// (the polling `test_queue.dart`'s head records taking down), where this
/// is a few milliseconds and starts nothing on a machine that may be out
/// of memory.
List<ProcessRow> readProcessTable() {
  try {
    if (Platform.isWindows) return _readWindowsTable();
    final asked = Process.runSync('ps', ['-A', '-o', 'pid=,ppid=,rss=,comm=']);
    return asked.exitCode == 0 ? rowsFromPs(asked.stdout as String) : const [];
  } on Exception {
    return const [];
  }
}

final _psRow = RegExp(r'^\s*(\d+)\s+(\d+)\s+(\d+)\s+(.+)$');

/// The table out of what `ps` printed. RSS in KB is what it has for
/// [ProcessRow.bytes]. Off Windows an orphan goes to init, so no number
/// needs [ProcessRow.born] to tell who it means.
List<ProcessRow> rowsFromPs(String text) => [
  for (final line in const LineSplitter().convert(text))
    if (_psRow.firstMatch(line) case final found?)
      (
        pid: int.parse(found[1]!),
        parent: int.parse(found[2]!),
        born: 0,
        name: found[4]!,
        bytes: int.parse(found[3]!) * 1024,
        cpu: 0,
      ),
];

List<ProcessRow> _readWindowsTable() {
  final rows = <ProcessRow>[];
  final snapshot = _snapshot(_snapProcesses, 0);
  if (snapshot == _invalidHandle) return rows;
  final entry = calloc<_ProcessEntry>();
  final counters = calloc<_MemoryCounters>();
  final times = calloc<Uint64>(4);
  try {
    entry.ref.size = sizeOf<_ProcessEntry>();
    counters.ref.size = sizeOf<_MemoryCounters>();
    for (
      var more = _firstProcess(snapshot, entry);
      more != 0;
      more = _nextProcess(snapshot, entry)
    ) {
      final process = _openProcess(_queryLimited, 0, entry.ref.pid);
      if (process == 0) continue;
      final read =
          _memoryInfo(process, counters, sizeOf<_MemoryCounters>()) != 0 &&
          _processTimes(process, times, times + 1, times + 2, times + 3) != 0;
      _closeHandle(process);
      if (!read) continue;
      rows.add((
        pid: entry.ref.pid,
        parent: entry.ref.parent,
        born: times[0],
        name: _exeName(entry.ref),
        bytes: counters.ref.committed,
        cpu: times[2] + times[3],
      ));
    }
  } finally {
    calloc.free(entry);
    calloc.free(counters);
    calloc.free(times);
    _closeHandle(snapshot);
  }
  return rows;
}

String _exeName(_ProcessEntry entry) {
  final name = StringBuffer();
  for (var i = 0; i < _maxPath && entry.exe[i] != 0; i++) {
    name.writeCharCode(entry.exe[i]);
  }
  return name.toString();
}

const _maxPath = 260;
const _snapProcesses = 2;
const _invalidHandle = -1;
const _queryLimited = 0x1000;
const _thisProcess = -1;
const _extendedLimitInformation = 9;
const _killOnJobClose = 0x2000;

/// `JOBOBJECT_EXTENDED_LIMIT_INFORMATION`, whose basic `LimitFlags` is all
/// [endWhatThisStartsWithIt] sets.
final class _JobLimits extends Struct {
  external _BasicJobLimits basic;
  @Array(6)
  external Array<Uint64> ioCounters;
  @Array(4)
  external Array<IntPtr> memoryLimitsAndPeaks;
}

/// `JOBOBJECT_BASIC_LIMIT_INFORMATION`.
final class _BasicJobLimits extends Struct {
  @Int64()
  external int perProcessUserTimeLimit;
  @Int64()
  external int perJobUserTimeLimit;
  @Uint32()
  external int flags;
  @IntPtr()
  external int minimumWorkingSetSize;
  @IntPtr()
  external int maximumWorkingSetSize;
  @Uint32()
  external int activeProcessLimit;
  @IntPtr()
  external int affinity;
  @Uint32()
  external int priorityClass;
  @Uint32()
  external int schedulingClass;
}

/// `PROCESSENTRY32W`.
final class _ProcessEntry extends Struct {
  @Uint32()
  external int size;
  @Uint32()
  external int usage;
  @Uint32()
  external int pid;
  @IntPtr()
  external int heap;
  @Uint32()
  external int module;
  @Uint32()
  external int threads;
  @Uint32()
  external int parent;
  @Int32()
  external int priority;
  @Uint32()
  external int flags;
  @Array(_maxPath)
  external Array<Uint16> exe;
}

/// `PROCESS_MEMORY_COUNTERS`, whose `PagefileUsage` is the process's commit
/// charge — the figure Windows' own exhaustion report names a process by.
final class _MemoryCounters extends Struct {
  @Uint32()
  external int size;
  @Uint32()
  external int faults;
  @Array(6)
  external Array<IntPtr> workingSetAndPools;
  @IntPtr()
  external int committed;
  @IntPtr()
  external int peakCommitted;
}

typedef _WalkNative = Int32 Function(IntPtr, Pointer<_ProcessEntry>);
typedef _WalkDart = int Function(int, Pointer<_ProcessEntry>);
typedef _TimesNative =
    Int32 Function(
      IntPtr,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
    );
typedef _TimesDart =
    int Function(
      int,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
    );

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _snapshot = _kernel32
    .lookupFunction<IntPtr Function(Uint32, Uint32), int Function(int, int)>(
      'CreateToolhelp32Snapshot',
    );
final _firstProcess = _kernel32.lookupFunction<_WalkNative, _WalkDart>(
  'Process32FirstW',
);
final _nextProcess = _kernel32.lookupFunction<_WalkNative, _WalkDart>(
  'Process32NextW',
);
final _openProcess = _kernel32
    .lookupFunction<
      IntPtr Function(Uint32, Int32, Uint32),
      int Function(int, int, int)
    >('OpenProcess');
final _closeHandle = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
final _memoryInfo = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<_MemoryCounters>, Uint32),
      int Function(int, Pointer<_MemoryCounters>, int)
    >('K32GetProcessMemoryInfo');
final _processTimes = _kernel32.lookupFunction<_TimesNative, _TimesDart>(
  'GetProcessTimes',
);
final _createJob = _kernel32
    .lookupFunction<
      IntPtr Function(Pointer<Void>, Pointer<Utf16>),
      int Function(Pointer<Void>, Pointer<Utf16>)
    >('CreateJobObjectW');
final _setJobInformation = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Int32, Pointer<_JobLimits>, Uint32),
      int Function(int, int, Pointer<_JobLimits>, int)
    >('SetInformationJobObject');
final _assignToJob = _kernel32
    .lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
      'AssignProcessToJobObject',
    );
