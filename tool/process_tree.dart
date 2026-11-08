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

/// One process of the machine, as [readProcessTable] found it: what it has
/// committed in [bytes] (the figure the machine runs out of), and when it
/// began in [born], which only ever orders two rows of one table.
typedef ProcessRow = ({int pid, int parent, int born, String name, int bytes});

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
  final children = <int, List<ProcessRow>>{};
  ProcessRow? top;
  for (final row in table) {
    children.putIfAbsent(row.parent, () => []).add(row);
    if (row.pid == root) top = row;
  }
  if (top == null) return null;
  var largest = top;
  final seen = {top.pid};
  final ahead = [top];
  while (ahead.isNotEmpty) {
    final process = ahead.removeLast();
    if (process.bytes > largest.bytes) largest = process;
    for (final child in children[process.pid] ?? const <ProcessRow>[]) {
      if (child.born >= process.born && seen.add(child.pid)) ahead.add(child);
    }
  }
  return largest;
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
