// ONE LINE OF TEST RUNS FOR THE WHOLE MACHINE, and ten suites at once
// between all of them, taken shortest first by the work each says it has —
// the longer a run has waited, the further forward it comes — and what the
// runs ahead leave of the ten goes to the next, so none stands free while
// a run waits.
//
//   bash tool/run.sh test_queue flutter test <files…>   run it in its turn
//   bash tool/run.sh test_queue timeout 300 flutter test <files…>
//   bash tool/run.sh test_queue --list                  who runs, who waits
//   bash tool/run.sh test_queue --usage [hours]         how much stood free
//
// `affected_tests` takes its turn here by itself — a session that runs it
// waits for nothing else first.
//
// 🗣️유저 2026-10-18, tests-crowd-the-machine-Q1 「b + ③」 — b is 「②기계
// 하나의 테스트 대기열: CI 서버처럼 기계에 테스트 「자리」를 고정해(예: 실행
// 2개 × 동시 8) 세션들이 일을 넣으면 하나의 실행기가 차례로 돌린다 — 20초마다
// 묻는 폴링이 없어지고, 코어를 넘겨 나눠 먹지 않아 전체 처리량이 오른다」. And
// 10-19: 「기계가 비엇는지? 레인이 비엇는지 일일이 감시로 손으로 확인하는거말고
// ci로해서 자원 안쓰게한다」, then 「최대가 10만되게 할수있나. 지금상태면
// 단독진행일때 5개제한이잖아」.
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
// launches nothing. Before each `flutter test` it launches ([Turn.take] —
// a run of many batches asks at every batch), a run whose turn has come
// asks the machine once whether there is room — CLAUDE.md's 4GB, measured
// before every launch; ⛔not its four places, which the line's runs take
// none of (유저 tests-crowd-the-machine-Q9 「line」, at the head of
// `flutter_room.dart`) — and asks again only while there is none. How many suites it takes ([suitesToRun]) is decided
// under one lock for the whole line, so two runs deciding in the same
// instant cannot both take the machine.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'flutter_room.dart';
import 'test_seconds.dart';

/// The suites every run in the line holds between them. ⚖️TEN, AS
/// MEASURED: one run filled the CPU at ten, and two runs side by side were
/// fastest at ten between them (145s at five each, 155s at ten each).
/// 🪦It was two places of six for a morning — twelve, on a guess — and then
/// two of five, which kept a run alone in the line at five (유저 10-19:
/// 「최대가 10만되게 할수있나. 지금상태면 단독진행일때 5개제한이잖아」).
const kMachineSuites = 10;

/// What a run takes when another is in line: half, so two run side by side
/// and the tail of one is filled by the other.
const kSharedSuites = kMachineSuites ~/ 2;

/// How often a run that waits looks at the line again.
const kLookAgain = Duration(seconds: 2);

/// How long a run whose turn has come waits to ask the machine again when
/// there was no room — the twenty seconds `lane.sh` waits between asks.
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

/// A run whose work ([Standing.work]) is this many machine-seconds or less
/// does not halve a long run's share: ten minutes of one suite's time — a
/// handful of files, a mutant's check. ↩️It was 「two files or fewer」
/// (`kShortRun`, 유저 10-19 Q3 「짧은 실행은 틈에 끼운다」) until 유저 10-20
/// Q6 (「작은실행은 순서 앞당긴다거나 … 다 싹 개선해줘」): that day eleven runs
/// of three to thirteen files stood an hour and three quarters behind two
/// long runs, every one of them too long for the old rule.
const kSmallWork = 600;

/// What a run that cannot say its work is counted at: an hour of one
/// suite's time — long, so it does not jump the line. A whole suite is such
/// a run, and so is the ticket of a tool from before [Standing.work].
const kUnknownWork = 3600;

/// One held ticket as the line reads it: the suites its run holds, or null
/// while it waits; the test files its `flutter test` names — null when it
/// names none (the whole suite, a folder) or is no `flutter test`; the
/// machine-seconds that `flutter test` should take ([workOf]) — null when
/// it cannot say; since when it has waited, or run — null when it did not
/// say, and then the line reads when it was asked ([askedAt]); and whether
/// its tool takes what is left of its share ([suitesToRun]) — false for a
/// tool from before, which takes all of it or waits.
typedef Standing = ({
  String name,
  int? suites,
  int? files,
  int? work,
  DateTime? since,
  bool takesWhatIsLeft,
});

/// When the ticket [name] was asked, read off its name ([ticketName]).
DateTime? askedAt(String name) {
  final micros = int.tryParse(name.split('-').first);
  return micros == null ? null : DateTime.fromMicrosecondsSinceEpoch(micros);
}

int _workOf(Standing standing) => standing.work ?? kUnknownWork;

bool _isSmall(Standing standing) => _workOf(standing) <= kSmallWork;

/// The suites [standing] would take now: all of its share — the machine
/// alone among the long runs in [line], half beside another
/// ([kSharedSuites]) — and never more than the files it names or what it
/// [asked].
int _wants(Standing standing, List<Standing> line, {int? asked}) {
  final share = line.any((o) => o.name != standing.name && !_isSmall(o))
      ? kSharedSuites
      : kMachineSuites;
  return [share, ?asked, ?standing.files].reduce(math.min);
}

/// How long [standing] should run at [suites], in seconds — never under one.
double _wallOf(Standing standing, int suites) =>
    math.max(1, _workOf(standing) / suites);

/// How far forward [standing] stands in [line] at [now]: (waited + its run)
/// over its run — the highest-response-ratio-next rule. A short run comes
/// forward fast, and a long one comes forward too as it waits, so no run
/// waits for ever; runs alike keep the order they asked in.
double _forwardness(Standing standing, List<Standing> line, DateTime now) {
  final wall = _wallOf(standing, _wants(standing, line));
  final since = standing.since ?? askedAt(standing.name) ?? now;
  final waited = math.max(0, now.difference(since).inMilliseconds / 1000);
  return (waited + wall) / wall;
}

/// The waiting runs in [line], the first in line first ([_forwardness]).
List<Standing> waitingInTurn(List<Standing> line, DateTime now) {
  final forward = {
    for (final s in line)
      if (s.suites == null) s.name: _forwardness(s, line, now),
  };
  return [
    for (final s in line)
      if (s.suites == null) s,
  ]..sort((a, b) {
    final ahead = forward[b.name]!.compareTo(forward[a.name]!);
    return ahead != 0 ? ahead : a.name.compareTo(b.name);
  });
}

/// The suites the run holding [mine] may start its `flutter test` with now,
/// or null while it waits.
///
/// 🗣️NO SUITE STANDS FREE WHILE A RUN WAITS (유저 10-20: 「계속 10줄 중 아까
/// 낮처럼 2개쓴다거나 지금처럼 6개만쓴다거나 이런거 안일어나게 하고싶어」).
/// What the running runs leave of [kMachineSuites] is handed down the line
/// in turn ([waitingInTurn]): each waiting run takes what it may hold
/// ([_wants]) — never more than it [asked] for — or what is left when that
/// is less, and the rest goes on to the one behind it.
///
/// ↩️Until then a run took all of what it may hold or waited, and the ones
/// behind took a gap only when the line could tell they would end before
/// the first could start (EASY backfill). The first in line, wanting five
/// where three stood free, kept the three idle; behind a run that could
/// not say its work, only a two-minute run took a gap. What made it wait —
/// 「a long batch started on the one suite left would run at one for its
/// whole length」 — is answered where the batch is made: `affected_tests`
/// sizes each batch to the suites it was given (`kBatchWall`).
///
/// ⚠️A run of a tool from before ([Standing.takesWhatIsLeft] false) still
/// takes all or waits, so what it would not take is not kept for it.
int? suitesToRun(
  String mine,
  List<Standing> line, {
  int? asked,
  DateTime? now,
}) {
  var left =
      kMachineSuites - line.fold<int>(0, (n, s) => n + (s.suites ?? 0));
  for (final s in waitingInTurn(line, now ?? DateTime.now())) {
    if (left <= 0) return null;
    final isMe = s.name == mine;
    final wants = _wants(s, line, asked: isMe ? asked : null);
    final takes = wants <= left || isMe || s.takesWhatIsLeft
        ? math.min(wants, left)
        : 0;
    if (isMe) return takes;
    left -= takes;
  }
  return null;
}

/// How many suites [command] asks for, if it is a `flutter test` that says.
int? askedSuites(List<String> command) {
  final at = _flutterTestAt(command);
  if (at == null) return null;
  int? asked;
  for (var i = at + 2; i < command.length; i++) {
    final word = command[i];
    if ((word == '-j' || word == '--concurrency') && i + 1 < command.length) {
      asked = int.tryParse(command[++i]);
    } else if (word.startsWith('--concurrency=')) {
      asked = int.tryParse(word.substring('--concurrency='.length));
    } else if (word.startsWith('-j') && int.tryParse(word.substring(2)) != null) {
      asked = int.parse(word.substring(2));
    }
  }
  return asked;
}

/// How many test files [command] names, if it is a `flutter test` that
/// names them — see [filesNamed].
int? filesAsked(
  List<String> command, {
  bool Function(String word) isFolder = FileSystemEntity.isDirectorySync,
}) {
  final at = _flutterTestAt(command);
  return at == null
      ? null
      : filesNamed(command.sublist(at + 2), isFolder: isFolder);
}

/// How many test files the `flutter test` [arguments] name, or null when
/// they name none — the whole suite — or a folder, which is a whole folder
/// of them.
int? filesNamed(
  List<String> arguments, {
  bool Function(String word) isFolder = FileSystemEntity.isDirectorySync,
}) {
  var files = 0;
  for (final word in arguments) {
    if (word.endsWith('.dart')) {
      files++;
    } else if (!word.startsWith('-') && isFolder(word)) {
      return null;
    }
  }
  return files == 0 ? null : files;
}

/// The machine-seconds the `flutter test` in [command] should take by
/// [known] ([workOf]) — null when it names no test files (the whole suite,
/// a folder) or is no `flutter test`.
int? workAsked(List<String> command, Map<String, int> known) {
  final at = _flutterTestAt(command);
  if (at == null) return null;
  final files = [
    for (final word in command.skip(at + 2))
      if (word.endsWith('.dart')) word.replaceAll(r'\', '/'),
  ];
  return filesAsked(command) == null ? null : workOf(files, known);
}

/// This machine's test times ([readTimes]), or none when it keeps none.
Map<String, int> timesOnThisMachine() {
  final folder = machineCacheFolder(Platform.environment);
  final file = folder == null ? null : File('$folder/test_times.tsv');
  try {
    return file != null && file.existsSync()
        ? readTimes(file.readAsStringSync())
        : const {};
  } on FileSystemException {
    return const {};
  }
}

/// [command] as its turn runs it: a `flutter test` holds [suites] suites,
/// whatever it said; any other command runs as it was given.
///
/// The `flutter test` may come after words of its own — `timeout 300
/// flutter test …`. 🚨That is where a run's own time limit belongs: one put
/// around `test_queue` counts the wait in line too, and a mutant that only
/// waited is read as killed (브러시/렌더링 found it on the line's first
/// morning, 10-19).
List<String> placed(List<String> command, int suites) {
  final at = _flutterTestAt(command);
  if (at == null) return command;
  final rest = <String>[];
  for (var i = at + 2; i < command.length; i++) {
    final word = command[i];
    if (word == '-j' || word == '--concurrency') {
      i++;
    } else if (!word.startsWith('--concurrency=') &&
        !(word.startsWith('-j') && int.tryParse(word.substring(2)) != null)) {
      rest.add(word);
    }
  }
  return [
    ...command.take(at),
    'flutter',
    'test',
    '--concurrency=$suites',
    ...rest,
  ];
}

int? _flutterTestAt(List<String> command) {
  for (var i = 0; i + 1 < command.length; i++) {
    if (command[i] == 'flutter' && command[i + 1] == 'test') return i;
  }
  return null;
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

/// What the run holding the ticket [name] in [line] said: the suites it
/// holds — none while it waits — the files its `flutter test` names, the
/// work it should take and since when it waits or runs ([Standing]). One
/// that has said nothing readable waits, names none and cannot say its
/// work, which keeps it from halving or overtaking anyone it should not.
Standing standingOf(Directory line, String name) {
  try {
    final about = jsonDecode(
      File('${line.path}/$name.json').readAsStringSync(),
    );
    if (about is Map) {
      return (
        name: name,
        suites: about['state'] == 'running' ? about['suites'] as int? : null,
        files: about['files'] as int?,
        work: about['work'] as int?,
        since: DateTime.tryParse('${about['since'] ?? ''}'),
        takesWhatIsLeft: about['takesWhatIsLeft'] == true,
      );
    }
  } on Object {
    // Read as one that said nothing.
  }
  return (
    name: name,
    suites: null,
    files: null,
    work: null,
    since: null,
    takesWhatIsLeft: false,
  );
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
    final about = <String, Object>{
      'pid': pid,
      'what': what,
      'where': Directory.current.path,
      'asked': DateTime.now().toIso8601String(),
      'takesWhatIsLeft': true,
    };
    final ticket = Ticket._(file, lock, about);
    ticket.waiting(null);
    return ticket;
  }

  final File file;
  final RandomAccessFile _lock;
  final Map<String, Object> _about;

  String get name => file.uri.pathSegments.last;

  /// What `--list` and the rest of the line read: the lock itself cannot be
  /// read on Windows while it is held, so who, what, how many suites and
  /// how many files go in a file beside it.
  void _tell(Map<String, Object?> now) {
    try {
      File('${file.path}.json').writeAsStringSync(jsonEncode({..._about, ...now}));
    } on FileSystemException {
      // The line reads this ticket as waiting; nobody behind it starts.
    }
  }

  /// Holds no suites since [since], and its next `flutter test` names
  /// [files] and should take [work] machine-seconds.
  void waiting(int? files, {int? work, DateTime? since}) => _tell({
    'state': 'waiting',
    'files': files,
    'work': work,
    'since': (since ?? DateTime.now()).toIso8601String(),
  });

  void running(int suites, int? files, {int? work}) => _tell({
    'state': 'running',
    'suites': suites,
    'files': files,
    'work': work,
    'since': DateTime.now().toIso8601String(),
  });

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

/// [decide] with the whole line's decision lock held: one run at a time
/// reads the line and says what it takes.
T _deciding<T>(Directory line, T Function() decide) {
  final lock = File('${line.path}/deciding.lock').openSync(
    mode: FileMode.append,
  );
  try {
    lock.lockSync(FileLock.blockingExclusive);
    return decide();
  } finally {
    try {
      lock.unlockSync();
    } on Object {
      // Released with the handle below.
    }
    lock.closeSync();
  }
}

/// One run's place in the machine's line, from its ticket until it is
/// given back. Every `flutter test` the run launches first [take]s its
/// suites and [putDown]s them when it ends — so a run of many batches
/// keeps its place between them, and the line decides each batch afresh:
/// the moment a run's suites can change is the moment a `flutter test`
/// starts. A long run that took all ten alone gives five to the next long
/// run at its next batch, and room to a short run waiting, instead of
/// holding them to its end.
class Turn {
  Turn._(
    this._folder,
    this._what, {
    required this.asked,
    required this.room,
    required this.ended,
    required this.say,
    required this.lookAgain,
    required this.askAgain,
  }) : _ticket = _folder == null ? null : Ticket.take(_folder, _what);

  final Directory? _folder;
  final String _what;
  Ticket? _ticket;

  /// The most suites this run asked for, whatever the line would give.
  final int? asked;
  final Future<bool> Function() room;
  final bool Function(File ticket) ended;
  final void Function(String) say;
  final Duration lookAgain;
  final Duration askAgain;

  /// The suites a `flutter test` naming [files] test files, with [work]
  /// machine-seconds to do ([workOf]), may hold ([suitesToRun]), once its
  /// turn has come and the machine has [room]. [say] hears where it stands;
  /// nothing is said while nothing changes.
  Future<int> take({int? files, int? work}) async {
    final folder = _folder;
    if (folder == null) {
      // No machine folder: no line to stand in, and the machine is its own.
      return [kMachineSuites, ?asked, ?files].reduce(math.min);
    }
    var since = DateTime.now();
    _ticket!.waiting(files, work: work, since: since);
    _noteUsage();
    List<Standing> standings() => [
      for (final name in heldTickets(folder, mine: _ticket!.name, ended: ended))
        if (name == _ticket!.name)
          (
            name: name,
            suites: null,
            files: files,
            work: work,
            since: since,
            takesWhatIsLeft: true,
          )
        else
          standingOf(folder, name),
    ];
    int? stood;
    var roomless = false;
    while (true) {
      // A ticket swept in the instant between being made and being locked
      // stands nowhere; it takes another at the back.
      if (!_ticket!.file.existsSync()) {
        since = DateTime.now();
        _ticket = Ticket.take(folder, _what)
          ..waiting(files, work: work, since: since);
      }
      final line = standings();
      if (suitesToRun(_ticket!.name, line, asked: asked) != null) {
        if (await room()) {
          // Asked again under the lock: the line may have moved while the
          // machine was measured, and what is taken is said before the lock
          // goes.
          final suites = _deciding(folder, () {
            final now = suitesToRun(_ticket!.name, standings(), asked: asked);
            if (now != null) {
              _ticket!.running(now, files, work: work);
              noteUsage(folder);
            }
            return now;
          });
          if (suites != null) return suites;
          continue;
        }
        if (!roomless) {
          say('test_queue: my turn, and the machine has no room — asking '
              'again every ${askAgain.inSeconds}s');
        }
        roomless = true;
        await Future<void>.delayed(askAgain);
        continue;
      }
      final waiting = waitingInTurn(line, DateTime.now());
      final at = waiting.indexWhere((s) => s.name == _ticket!.name) + 1;
      if (at != stood) {
        say('test_queue: number $at of the ${waiting.length} waiting, '
            'shortest and longest-waiting first — $kMachineSuites suites '
            'between the runs (nothing runs while it waits)');
        stood = at;
      }
      await Future<void>.delayed(lookAgain);
    }
  }

  /// The `flutter test` that [take] let start has ended: this run holds no
  /// suites until it takes them again.
  void putDown() {
    _ticket?.waiting(null);
    _noteUsage();
  }

  void _giveBack() {
    _ticket?.giveBack();
    _noteUsage();
  }

  void _noteUsage() {
    final folder = _folder;
    if (folder != null) _deciding(folder, () => noteUsage(folder));
  }
}

/// Runs [run] with a place in the machine's line ([Turn]) — never more than
/// [asked] suites for any of its `flutter test`s.
Future<T> standInLine<T>(
  String what,
  Future<T> Function(Turn turn) run, {
  int? asked,
  Directory? line,
  Future<bool> Function()? room,
  bool Function(File ticket) ended = runHasEnded,
  void Function(String) say = print,
  Duration lookAgain = kLookAgain,
  Duration askAgain = kAskAgain,
}) async {
  final turn = Turn._(
    line ?? queueFolder(Platform.environment),
    what,
    asked: asked,
    room: room ?? machineHasRoom,
    ended: ended,
    say: say,
    lookAgain: lookAgain,
    askAgain: askAgain,
  );
  try {
    return await run(turn);
  } finally {
    turn._giveBack();
  }
}

/// Runs [run] — one `flutter test` naming [files] test files, or any one
/// command — in its turn in the machine's line, handing it the suites it
/// may hold ([Turn.take]).
Future<T> inTurn<T>(
  String what,
  Future<T> Function(int suites) run, {
  int? asked,
  int? files,
  int? work,
  Directory? line,
  Future<bool> Function()? room,
  bool Function(File ticket) ended = runHasEnded,
  void Function(String) say = print,
  Duration lookAgain = kLookAgain,
  Duration askAgain = kAskAgain,
}) => standInLine(
  what,
  (turn) async => run(await turn.take(files: files, work: work)),
  asked: asked,
  line: line,
  room: room,
  ended: ended,
  say: say,
  lookAgain: lookAgain,
  askAgain: askAgain,
);

/// Whether this machine has room for one more run, by `flutter_room`'s own
/// measure. ⛔One that cannot be measured has none — 「no answer」 is not
/// 「room」 (`lane.sh`'s room_first). Off Windows there is nothing to
/// measure with, and the line's suites are the whole bound.
///
/// It asks for the headroom alone: the line's runs take none of the four
/// places (유저 tests-crowd-the-machine-Q9 「line」). [measure] is
/// `flutter_room`'s, wherever there is one to ask.
Future<bool> machineHasRoom({
  Future<MachineRoom?> Function({required bool headroomAlone})? measure,
}) async {
  final ask = measure ?? (Platform.isWindows ? measureRoom : null);
  if (ask == null) return true;
  final measured = await ask(headroomAlone: true);
  return measured?.room ?? false;
}

/// The line's record of itself, in its folder: one row each time a run
/// starts to wait, takes its suites, puts them down or leaves — when, the
/// suites the runs hold and how many wait — so how much of the ten stood
/// free while runs waited is a number ([usageOf]), not a look at `--list`
/// (유저 10-20: 「계속 10줄 중 아까 낮처럼 2개쓴다거나 지금처럼 6개만쓴다거나
/// 이런거 안일어나게 하고싶어」).
const kUsageFile = 'usage.tsv';

/// The size past which the record keeps only its later half.
const kUsageKeeps = 1 << 20;

/// Writes the row [kUsageFile] keeps for [line] as it stands now. ⚠️With
/// the line's decision lock held ([_deciding]): it is the one writer then,
/// and the one that may cut the record down.
///
/// ⚠️It reads the tickets there and asks no run whether it has ended —
/// sweeping is [heldTickets]' job, done every look of every run that waits,
/// so a ticket left by a run that was killed counts until the next look.
void noteUsage(Directory line) {
  final standings = [
    for (final entity in line.listSync())
      if (entity is File && entity.path.endsWith('.ticket'))
        standingOf(line, entity.uri.pathSegments.last),
  ];
  final held = standings.fold<int>(0, (n, s) => n + (s.suites ?? 0));
  final waiting = standings.where((s) => s.suites == null).length;
  final file = File('${line.path}/$kUsageFile');
  try {
    file.writeAsStringSync(
      '${DateTime.now().toIso8601String()}\t$held\t$waiting\n',
      mode: FileMode.append,
    );
    if (file.lengthSync() > kUsageKeeps) {
      final rows = file.readAsLinesSync();
      file.writeAsStringSync('${rows.skip(rows.length ~/ 2).join('\n')}\n');
    }
  } on FileSystemException {
    // A row missed is a moment unrecorded; the line runs on.
  }
}

/// From the rows of [kUsageFile] (in any order), between [from] and [to]:
/// how long runs waited, and the suites held and left free in that time on
/// average. A row stands until the next one, the last until [to].
({Duration waited, double held}) usageOf(
  Iterable<String> rows, {
  required DateTime from,
  required DateTime to,
}) {
  final states = [
    for (final row in rows)
      if (row.split('\t') case [final at, final held, final waiting])
        if ((DateTime.tryParse(at), int.tryParse(held), int.tryParse(waiting))
            case (final DateTime at?, final int held?, final int waiting?))
          (at: at, held: held, waiting: waiting),
  ]..sort((a, b) => a.at.compareTo(b.at));
  var waited = Duration.zero;
  var heldWhileWaiting = 0.0;
  for (final (i, state) in states.indexed) {
    final start = state.at.isBefore(from) ? from : state.at;
    final next = i + 1 < states.length ? states[i + 1].at : to;
    final end = next.isAfter(to) ? to : next;
    if (state.waiting == 0 || !end.isAfter(start)) continue;
    final span = end.difference(start);
    waited += span;
    heldWhileWaiting += state.held * span.inMilliseconds;
  }
  return (
    waited: waited,
    held: waited == Duration.zero
        ? 0
        : heldWhileWaiting / waited.inMilliseconds,
  );
}

/// The line as `--list` prints it at [now], one ticket a row: the running
/// runs, then the waiting ones in turn ([waitingInTurn]).
List<String> describeLine(Directory line, {DateTime? now}) {
  if (!line.existsSync()) return const ['(nobody in line)'];
  final tickets = {
    for (final entity in line.listSync())
      if (entity is File && entity.path.endsWith('.ticket'))
        entity.uri.pathSegments.last: entity,
  };
  if (tickets.isEmpty) return const ['(nobody in line)'];
  final standings = [
    for (final name in tickets.keys.toList()..sort()) standingOf(line, name),
  ];
  final inTurn = [
    for (final s in standings)
      if (s.suites != null) s,
    ...waitingInTurn(standings, now ?? DateTime.now()),
  ];
  return [
    for (final (i, s) in inTurn.indexed)
      '${i + 1}. ${_about(tickets[s.name]!)}'
          '${runHasEnded(tickets[s.name]!) ? '  (ended)' : ''}',
  ];
}

String _about(File ticket) {
  try {
    final about = jsonDecode(File('${ticket.path}.json').readAsStringSync())
        as Map<String, dynamic>;
    final suites = about['suites'] == null ? '' : ' ${about['suites']} suites';
    final files = about['files'] == null ? '' : ' · ${about['files']} files';
    final work = about['work'] == null
        ? ''
        : ' · ~${((about['work'] as int) / 60).ceil()} machine-min';
    return '${about['state']}$suites$files$work · pid ${about['pid']} · '
        'since ${about['asked']} · ${about['what']} · ${about['where']}';
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
  if (args.isNotEmpty && args.first == '--usage' && args.length <= 2) {
    final hours = args.length == 2 ? int.tryParse(args[1]) : 24;
    final file = line == null ? null : File('${line.path}/$kUsageFile');
    if (hours == null || file == null || !file.existsSync()) {
      stdout.writeln('(no record of the line on this machine)');
      return;
    }
    final to = DateTime.now();
    final (:waited, :held) = usageOf(
      file.readAsLinesSync(),
      from: to.subtract(Duration(hours: hours)),
      to: to,
    );
    stdout.writeln(
      'the last $hours h: runs waited ${waited.inMinutes} min, and the runs '
      'held ${held.toStringAsFixed(1)} of $kMachineSuites suites meanwhile — '
      '${((kMachineSuites - held) * waited.inMinutes / 60).toStringAsFixed(1)}'
      ' suite-hours stood free',
    );
    return;
  }
  if (args.isEmpty) {
    stderr.writeln(
      'usage: bash tool/run.sh test_queue <command…> | --list | --usage [hours]',
    );
    exitCode = 2;
    return;
  }
  exitCode = await inTurn(
    args.join(' '),
    asked: askedSuites(args),
    files: filesAsked(args),
    work: workAsked(args, timesOnThisMachine()),
    (suites) async {
      final command = placed(args, suites);
      final started = await Process.start(
        command.first,
        command.skip(1).toList(),
        mode: ProcessStartMode.inheritStdio,
        runInShell: Platform.isWindows,
      );
      return started.exitCode;
    },
  );
}
