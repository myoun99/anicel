// ONE LINE OF TEST RUNS FOR THE WHOLE MACHINE: a fixed number of places,
// each running a fixed number of suites at once, taken in the order asked.
//
//   bash tool/run.sh test_queue flutter test <files…>   run it in its turn
//   bash tool/run.sh test_queue --list                  who runs, who waits
//
// `affected_tests` takes its turn here by itself — a session that runs it
// waits for nothing else first.
//
// 🗣️유저 2026-10-18, tests-crowd-the-machine-Q1 「b + ③」 — b is 「②기계
// 하나의 테스트 대기열: CI 서버처럼 기계에 테스트 「자리」를 고정해(예: 실행
// 2개 × 동시 8) 세션들이 일을 넣으면 하나의 실행기가 차례로 돌린다 — 20초마다
// 묻는 폴링이 없어지고, 코어를 넘겨 나눠 먹지 않아 전체 처리량이 오른다」. And
// 10-19: 「기계가 비엇는지? 레인이 비엇는지 일일이 감시로 손으로 확인하는거말고
// ci로해서 자원 안쓰게한다」.
//
// WHY, measured on the main PC (20 logical cores) on 2026-10-18 · 19: one
// run fills the CPU at about ten suites at once, and ten is what every run
// takes when nobody says otherwise (package:test's default, half the
// cores) — so four session runs were forty suites on twenty cores. The same
// 60 files in two runs side by side took 145s at five suites each and 155s
// at ten each. And every session that waited asked `flutter_room` every
// twenty seconds: a PowerShell walk of every process on the machine, one to
// two seconds of CPU each time, from every waiting script at once.
//
// HOW. A run takes a ticket in the machine's own folder (the one
// `tool/run.sh` builds its exes in, shared by every worktree), named by the
// moment it asked, so the names sort in turn order. It holds the ticket's
// lock for as long as it lives; a ticket whose lock can be taken belongs to
// a run that is gone. That is the law `SessionScratch._runHasEnded` keeps
// for the app's per-run rooms — two places, not three: change both or
// neither. A run that waits lists the folder every two seconds and
// launches nothing. The run at the head of the line asks the machine once
// whether there is room (CLAUDE.md's four places and 4GB — what the queue
// does not hold, a session's app or analyze, still takes a place), and asks
// again only while there is none.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'flutter_room.dart';
import 'test_seconds.dart';

/// The test runs the line lets go at once.
const kQueuePlaces = 2;

/// The suites each of them holds at once. ⚖️Two places of six, not the
/// example's two of eight (Q1's own 「예」): one run filled the CPU at ten,
/// and two runs side by side were fastest at ten between them (145s at five
/// each against 155s at ten each) — twelve keeps the tail of one run
/// overlapped by the other without paying for twenty.
const kSuitesAPlace = 6;

/// How often a run that waits looks at the line again.
const kLookAgain = Duration(seconds: 2);

/// How long the head of the line waits to ask the machine again when there
/// was no room — the twenty seconds `lane.sh` waits between asks.
const kAskAgain = Duration(seconds: 20);

/// A ticket younger than this is not asked whether its run has ended: it
/// may be between being made and being locked, and taking its lock in that
/// instant would sweep a run that is alive.
const kTicketSettles = Duration(seconds: 2);

/// The line's folder on this machine, or null when it names none.
Directory? queueFolder(Map<String, String> environment) {
  final folder = machineCacheFolder(environment);
  return folder == null ? null : Directory('$folder/test_queue');
}

/// A ticket's name: when it was asked, so names sort in turn order, and
/// whose it is.
String ticketName(int microseconds, int processId) =>
    '${microseconds.toString().padLeft(17, '0')}-$processId.ticket';

/// Whether the ticket named [mine] may run: it stands among the first
/// [places] of the [held] tickets, in the order their names sort.
bool isMyTurn(String mine, Iterable<String> held, {int places = kQueuePlaces}) {
  final line = held.toList()..sort();
  final at = line.indexOf(mine);
  return at >= 0 && at < places;
}

/// The suites a run holds at once: what it asked for, and never more than
/// a place has.
int suitesFor(int? asked) =>
    asked == null || asked > kSuitesAPlace ? kSuitesAPlace : asked;

/// [command] as a place runs it: a `flutter test` holds [suitesFor] its
/// own ask; any other command runs as it was given.
List<String> placed(List<String> command) {
  if (command.length < 2 || command[0] != 'flutter' || command[1] != 'test') {
    return command;
  }
  int? asked;
  final rest = <String>[];
  for (var i = 2; i < command.length; i++) {
    final word = command[i];
    if (word == '-j' || word == '--concurrency') {
      if (i + 1 < command.length) asked = int.tryParse(command[++i]);
    } else if (word.startsWith('--concurrency=')) {
      asked = int.tryParse(word.substring('--concurrency='.length));
    } else if (word.startsWith('-j') && int.tryParse(word.substring(2)) != null) {
      asked = int.parse(word.substring(2));
    } else {
      rest.add(word);
    }
  }
  return ['flutter', 'test', '--concurrency=${suitesFor(asked)}', ...rest];
}

/// The tickets in [line] whose runs are alive, by name — [mine] among them
/// — after taking away every one whose run has [ended].
List<String> heldTickets(
  Directory line, {
  required String mine,
  required bool Function(File ticket) ended,
  DateTime? now,
}) {
  final held = <String>[];
  final at = now ?? DateTime.now();
  for (final entity in line.listSync()) {
    if (entity is! File || !entity.path.endsWith('.ticket')) continue;
    final name = entity.uri.pathSegments.last;
    if (name == mine) {
      held.add(name);
      continue;
    }
    final DateTime made;
    try {
      made = entity.lastModifiedSync();
    } on FileSystemException {
      continue; // Given back while we looked.
    }
    if (at.difference(made) < kTicketSettles || !ended(entity)) {
      held.add(name);
      continue;
    }
    _deleteQuietly(entity);
    _deleteQuietly(File('${entity.path}.json'));
  }
  return held;
}

/// Whether the run that holds [ticket] is gone — asked by TAKING its lock,
/// as `SessionScratch._runHasEnded` asks of a room.
bool runHasEnded(File ticket) {
  RandomAccessFile? probe;
  try {
    // 🚨`append`, never `write`: on POSIX the open succeeds on a ticket a
    // live run holds (only the lock is refused), and `write` would empty it.
    probe = ticket.openSync(mode: FileMode.append);
    probe.lockSync(FileLock.exclusive);
    probe.unlockSync();
    return true;
  } on Object {
    // Held — on Windows the open itself is refused, on POSIX the lock is.
    return false;
  } finally {
    try {
      probe?.closeSync();
    } on Object {
      // Already gone.
    }
  }
}

/// One run's place in the line, held for as long as the run lives.
class Ticket {
  Ticket._(this.file, this._lock, this._about);

  /// Takes a ticket at the back of [line] for a run that does [what].
  factory Ticket.take(Directory line, String what) {
    line.createSync(recursive: true);
    final file = File(
      '${line.path}/${ticketName(DateTime.now().microsecondsSinceEpoch, pid)}',
    );
    final lock = file.openSync(mode: FileMode.append);
    lock.lockSync(FileLock.exclusive);
    // It has content on purpose, written under the lock: an empty ticket
    // would hide a probe that opened it the truncating way.
    lock.writeStringSync('$pid\n');
    final about = {
      'pid': pid,
      'what': what,
      'where': Directory.current.path,
      'asked': DateTime.now().toIso8601String(),
    };
    final ticket = Ticket._(file, lock, about);
    ticket._tell('waiting');
    return ticket;
  }

  final File file;
  final RandomAccessFile _lock;
  final Map<String, Object> _about;

  String get name => file.uri.pathSegments.last;

  /// What `--list` reads: the lock itself cannot be read on Windows while
  /// it is held, so who and what go in a file beside it.
  void _tell(String state) {
    try {
      File('${file.path}.json').writeAsStringSync(
        jsonEncode({..._about, 'state': state}),
      );
    } on FileSystemException {
      // `--list` shows the ticket without it.
    }
  }

  void running() => _tell('running');

  void giveBack() {
    try {
      _lock.unlockSync();
      _lock.closeSync();
    } on Object {
      // Closed with the process, if it came to that.
    }
    _deleteQuietly(file);
    _deleteQuietly(File('${file.path}.json'));
  }
}

void _deleteQuietly(File file) {
  try {
    file.deleteSync();
  } on FileSystemException {
    // Gone already, or another waiter swept it first.
  }
}

/// Runs [run] in its turn in the machine's line: when its ticket is among
/// the first [kQueuePlaces] and the machine has [room]. [say] hears where
/// it stands; nothing is said while nothing changes.
Future<T> inTurn<T>(
  String what,
  Future<T> Function() run, {
  Directory? line,
  Future<bool> Function()? room,
  bool Function(File ticket) ended = runHasEnded,
  void Function(String) say = print,
  Duration lookAgain = kLookAgain,
  Duration askAgain = kAskAgain,
}) async {
  final folder = line ?? queueFolder(Platform.environment);
  if (folder == null) return run(); // No machine folder: no line to stand in.
  var ticket = Ticket.take(folder, what);
  try {
    int? stood;
    var roomless = false;
    while (true) {
      // A ticket swept in the instant between being made and being locked
      // stands nowhere; it takes another at the back.
      if (!ticket.file.existsSync()) ticket = Ticket.take(folder, what);
      final held = heldTickets(folder, mine: ticket.name, ended: ended);
      if (isMyTurn(ticket.name, held)) {
        if (await (room ?? machineHasRoom)()) break;
        if (!roomless) {
          say('test_queue: my turn, and the machine has no room — asking '
              'again every ${askAgain.inSeconds}s');
        }
        roomless = true;
        await Future<void>.delayed(askAgain);
        continue;
      }
      final at = (held..sort()).indexOf(ticket.name) + 1;
      if (at != stood) {
        say('test_queue: number $at in line, behind $kQueuePlaces places — '
            'waiting (nothing runs while it waits)');
        stood = at;
      }
      await Future<void>.delayed(lookAgain);
    }
    ticket.running();
    return await run();
  } finally {
    ticket.giveBack();
  }
}

/// Whether this machine has room for one more run, by `flutter_room`'s own
/// measure. ⛔One that cannot be measured has none — 「no answer」 is not
/// 「room」 (`lane.sh`'s room_first). Off Windows there is nothing to
/// measure with, and the line's places are the whole bound.
Future<bool> machineHasRoom() async {
  if (!Platform.isWindows) return true;
  final measured = await measureRoom(aLand: false);
  return measured?.room ?? false;
}

/// The line as `--list` prints it, one ticket a row, in turn order.
List<String> describeLine(Directory line) {
  if (!line.existsSync()) return const ['(nobody in line)'];
  final tickets = [
    for (final entity in line.listSync())
      if (entity is File && entity.path.endsWith('.ticket')) entity,
  ]..sort((a, b) => a.path.compareTo(b.path));
  if (tickets.isEmpty) return const ['(nobody in line)'];
  return [
    for (final (i, ticket) in tickets.indexed)
      '${i + 1}. ${_about(ticket)}${runHasEnded(ticket) ? '  (ended)' : ''}',
  ];
}

String _about(File ticket) {
  try {
    final about = jsonDecode(File('${ticket.path}.json').readAsStringSync())
        as Map<String, dynamic>;
    return '${about['state']} · pid ${about['pid']} · since ${about['asked']}'
        ' · ${about['what']} · ${about['where']}';
  } on Object {
    return ticket.uri.pathSegments.last;
  }
}

Future<void> main(List<String> args) async {
  final line = queueFolder(Platform.environment);
  if (args.length == 1 && args.first == '--list') {
    if (line == null) {
      stdout.writeln('(this machine names no folder for the line)');
      return;
    }
    describeLine(line).forEach(stdout.writeln);
    return;
  }
  if (args.isEmpty) {
    stderr.writeln('usage: bash tool/run.sh test_queue <command…> | --list');
    exitCode = 2;
    return;
  }
  final command = placed(args);
  exitCode = await inTurn(command.join(' '), () async {
    final started = await Process.start(
      command.first,
      command.skip(1).toList(),
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
    );
    return started.exitCode;
  });
}
