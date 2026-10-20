// What landed on master since the last check, run wide once — and, when it
// is red, which landing made it so.
//
// 🗣️유저 2026-10-20, tests-crowd-the-machine-Q8 「나눈다 — 착지 전엔 가까운
// 테스트, 착지 뒤엔 관제가 묶어 넓게 + 범인 찾기」: a lane runs the tests
// near its change before it lands (`affected_tests`); after, the 관제 runs
// this — every landing since the last check together, with the wide
// selection, once. A red is walked back over those landings to the one
// that made it, for the 관제 to put on that lane's card. 「우리 병렬작업하는데
// 문제없나?」 — `lane.sh` lands one lane at a time, so the landings since a
// check are one stretch of master, and halving the stretch finds the
// landing.
//
// It runs in a lane of its own ([kCheckLane]), moved from commit to commit
// and given each one's engine and packages — never in the main checkout,
// whose files `lane.sh land` moves while a run would be reading them.
//
// What it keeps, in [machineCacheFolder]:
//   master_check.tsv  `checked` — the master the last check ran on, and
//                     `green` — the last master it found no red on: a
//                     bundle PR goes up to it and no further (Q8)
//   master_reds.tsv   each red file → the landing that made it red, until
//                     a check finds it green; a lane's own run does not
//                     hold its verdict back on one its master carries
//                     (`affected_tests`)
//   near_misses.tsv   each red the near run let through → how many
//                     imports from the landing's change it stood — what
//                     [kNearImports] is set by
//
// Usage:
//   bash tool/run.sh master_check          # check what landed since
//   bash tool/run.sh master_check --list   # say what it keeps, run nothing

import 'dart:convert';
import 'dart:io';

import 'import_graph.dart';
import 'test_seconds.dart';

/// The lane the check runs in.
const kCheckLane = 'master-check';

/// A landing on master: the commit it left master at, and the lane's name.
typedef Landing = ({String sha, String name});

/// The landings in [stretch] — master's commits since the last check,
/// oldest first — as [reflog] (`git reflog show --format=%H%x09%gs master`)
/// names them. The last commit is always one: whatever moved master there.
List<Landing> landingsIn(List<String> stretch, String reflog) {
  final names = <String, String>{};
  for (final line in const LineSplitter().convert(reflog)) {
    if (line.split('\t') case [final sha, final subject]) {
      names.putIfAbsent(sha, () => laneOf(subject));
    }
  }
  return [
    for (final (i, sha) in stretch.indexed)
      if (names.containsKey(sha) || i == stretch.length - 1)
        (sha: sha, name: names[sha] ?? 'master'),
  ];
}

/// The lane a reflog [subject] names (`merge work/<lane>: Fast-forward`),
/// or the subject itself when it names none.
String laneOf(String subject) =>
    RegExp(r'^merge work/([^:\s]+):').firstMatch(subject)?.group(1) ??
    subject;

/// Which of [count] landings turned each of [reds] red: the first whose
/// tip it is red at. Each is red at the last landing and is taken as green
/// before the first; [redsAt] runs files at a landing's tip and says which
/// were red. Halving keeps each file's own stretch, so reds that different
/// landings made part on the way.
Future<Map<String, int>> culprits(
  Set<String> reds,
  int count,
  Future<Set<String>> Function(int landing, Set<String> files) redsAt,
) async {
  final found = <String, int>{};
  // Green at [lo] (-1: before the first landing), red at [hi].
  Future<void> walk(Set<String> files, int lo, int hi) async {
    if (hi - lo == 1) {
      for (final file in files) {
        found[file] = hi;
      }
      return;
    }
    final mid = (lo + hi) ~/ 2;
    final red = await redsAt(mid, files);
    final already = files.intersection(red);
    if (already.isNotEmpty) await walk(already, lo, mid);
    final notYet = files.difference(red);
    if (notYet.isNotEmpty) await walk(notYet, mid, hi);
  }

  if (reds.isNotEmpty) await walk(reds, -1, count - 1);
  return found;
}

/// What the check keeps on this machine, in [folder].
class MasterRecords {
  MasterRecords(String folder)
    : _check = File('$folder/master_check.tsv'),
      _reds = File('$folder/master_reds.tsv'),
      _misses = File('$folder/near_misses.tsv');

  /// The records of this machine, or null when it names no folder.
  static MasterRecords? of(Map<String, String> environment) {
    final folder = machineCacheFolder(environment);
    return folder == null ? null : MasterRecords(folder);
  }

  final File _check;
  final File _reds;
  final File _misses;

  Map<String, String> _read(File file) {
    try {
      return file.existsSync() ? readPairs(file.readAsStringSync()) : {};
    } on FileSystemException {
      return {};
    }
  }

  /// The master the last check ran on.
  String? get checked => _read(_check)['checked'];

  /// The last master the check found no red on.
  String? get green => _read(_check)['green'];

  /// Each file red on master → the landing that made it red.
  Map<String, Landing> get reds => {
    for (final MapEntry(:key, :value) in _read(_reds).entries)
      if (value.split(' ') case [final sha, final name])
        key: (sha: sha, name: name),
  };

  /// Each red the near run let through (`<landing sha> <file>`) → how far
  /// it stood, or `-` when no import reached it.
  Map<String, String> get misses => _read(_misses);

  /// Keeps a check of [checked]: its [reds], and [checked] as green when
  /// there are none.
  void keep({required String checked, required Map<String, Landing> reds}) {
    updatePairs(_reds, (_) => {
      for (final MapEntry(:key, :value) in reds.entries)
        key: '${value.sha} ${value.name}',
    });
    updatePairs(_check, (known) => {
      ...known,
      'checked': checked,
      if (reds.isEmpty) 'green': checked,
    });
  }

  /// Adds [found] — each missed red (`<landing sha> <file>`) → its distance.
  void noteMisses(Map<String, String> found) =>
      updatePairs(_misses, (known) => {...known, ...found});
}

/// The landing [file] is red on master since, when [carries] says this
/// checkout holds that landing — a red the checkout's own change did not
/// make (🗣️Q8: 「master 에 이미 있는 빨강은 목록으로 표시해 다른 레인의 착지
/// 전 검사가 남의 빨강으로 막히지 않게」, 관제's answer the user took).
Landing? redOnMaster(
  String file,
  Map<String, Landing> reds,
  bool Function(String sha) carries,
) {
  final landing = reds[file];
  return landing != null && carries(landing.sha) ? landing : null;
}

/// How many imports from [test] the first of [changed] stands — by its
/// own reach within that many ([Reaches]) — or null when none is reached.
int? importsAway(
  String test,
  Set<String> changed,
  Map<String, Set<String>> imports,
  String Function(String path) read,
) {
  var reached = -1;
  for (var within = 0; ; within++) {
    final reach = Reaches(imports, read, within: within).of(test);
    if (reachesAny(reach, changed)) return within;
    if (reach.files.length == reached) return null;
    reached = reach.files.length;
  }
}

Future<void> main(List<String> args) async {
  final records = MasterRecords.of(Platform.environment);
  if (records == null) {
    stderr.writeln('master_check: this machine names no folder to keep in.');
    exit(2);
  }
  if (args.contains('--list')) {
    _describe(records).forEach(stdout.writeln);
    return;
  }
  final root = _mainCheckout();
  final lock = _lockFor(root);
  if (lock == null) {
    _say('a check is already running.');
    return;
  }
  try {
    exit(await _check(root, records));
  } on _Unfinished catch (e) {
    _say('⚠️the check did not finish — ${e.why}. Nothing was kept.');
    exit(1);
  }
}

Future<int> _check(String root, MasterRecords records) async {
  final head = _git(root, ['rev-parse', 'master']);
  final checked = records.checked ?? _git(root, ['rev-parse', 'origin/master']);
  if (head == checked) {
    _say('master is where the last check left it (${_short(head)}).');
    return 0;
  }
  final stretch = _lines(
    _git(root, ['rev-list', '--reverse', '$checked..$head']),
  );
  if (stretch.isEmpty) {
    _say('master (${_short(head)}) is behind the last check '
        '(${_short(checked)}) — nothing landed to check.');
    return 2;
  }
  // The check before goes first: a red no landing made — red before the
  // stretch, where the last check did not run it — is found there, and no
  // lane is named for it.
  final landings = [
    (sha: checked, name: 'before ${_short(checked)}'),
    ...landingsIn(
      stretch,
      _git(root, ['reflog', 'show', '--format=%H%x09%gs', 'master']),
    ),
  ];
  _say('${landings.length - 1} landing(s) since ${_short(checked)}: '
      '${landings.skip(1).map((l) => l.name).join(', ')}.');

  final lane = await _laneAt(root, head);
  final known = records.reds;
  final red = await _redsAt(root, lane, [
    '--wide',
    '--base',
    checked,
    ...known.keys.where((file) => File('$lane/$file').existsSync()),
  ]);
  final fresh = red.difference(known.keys.toSet());
  final away = _distances(lane, fresh);
  final found = await culprits(fresh, landings.length, (i, files) async {
    final at = await _laneAt(root, landings[i].sha);
    return _redsAt(root, at, [
      for (final file in files)
        if (File('$at/$file').existsSync()) file,
    ]);
  });

  final reds = {
    for (final file in red) file: known[file] ?? landings[found[file]!],
  };
  final misses = {
    for (final MapEntry(key: file, value: i) in found.entries)
      if (i > 0)
        '${landings[i].sha} $file':
            '${away(file, _changedBy(root, landings[i - 1].sha, landings[i].sha)) ?? '-'}',
  };
  records
    ..keep(checked: head, reds: reds)
    ..noteMisses(misses);
  for (final file in known.keys) {
    if (!red.contains(file)) _say('✅green again: $file');
  }
  for (final file in fresh) {
    final landing = reds[file]!;
    final far = misses['${landing.sha} $file'];
    _say('🔴$file — red since ${landing.name} (${_short(landing.sha)})'
        '${far == null ? '' : ', $far import(s) from its change'}');
  }
  _say(reds.isEmpty
      ? 'GREEN through ${_short(head)} — a bundle PR may go up to it.'
      : 'RED — ${reds.length} file(s); the last green master is '
          '${_short(records.green ?? '(none)')}.');
  return reds.isEmpty ? 0 : 1;
}

/// How far each of [reds] stands from a change ([importsAway]), asked of
/// the graph of [lane] as it is now — before the walk moves it.
int? Function(String file, Set<String> changed) _distances(
  String lane,
  Set<String> reds,
) {
  if (reds.isEmpty) return (_, _) => null;
  final was = Directory.current;
  Directory.current = lane;
  try {
    final imports = buildImportGraph(roots: kGraphRoots);
    final texts = {
      for (final file in imports.keys)
        if (!file.startsWith('lib/')) file: File(file).readAsStringSync(),
    };
    return (file, changed) =>
        importsAway(file, changed, imports, (path) => texts[path] ?? '');
  } finally {
    Directory.current = was;
  }
}

/// The files changed from [from] to [to].
Set<String> _changedBy(String root, String from, String to) =>
    _lines(_git(root, ['diff', '--name-only', from, to])).toSet();

/// The files `affected_tests` found red in [lane] with [args] — run once
/// more and still red, and not quarantined.
Future<Set<String>> _redsAt(String root, String lane, List<String> args) async {
  final out = File('${Directory.systemTemp.path}/master-check-$pid.reds');
  if (out.existsSync()) out.deleteSync();
  final run = await Process.start(
    'bash',
    ['$root/tool/run.sh', 'affected_tests', '--reds-to', out.path, ...args],
    workingDirectory: lane,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await run.exitCode;
  if (!out.existsSync()) {
    throw _Unfinished('affected_tests stopped (exit $code) before its verdict');
  }
  final reds = _lines(out.readAsStringSync()).toSet();
  out.deleteSync();
  return reds;
}

/// The check's lane, moved to [sha] with that commit's packages and engine.
Future<String> _laneAt(String root, String sha) async {
  final lane = _lanePath(root);
  if (!File('$lane/.git').existsSync()) {
    await _bash(root, ['tool/lane.sh', 'open', kCheckLane]);
  }
  if (_git(lane, ['status', '--porcelain']).isNotEmpty) {
    throw _Unfinished('$lane holds changes nobody committed');
  }
  final was = _git(lane, ['rev-parse', 'HEAD']);
  if (was != sha) _git(lane, ['checkout', '--quiet', '--detach', sha]);
  final packages = Process.runSync('git', [
    '-C', lane, 'diff', '--quiet', was, sha, '--', 'pubspec.yaml',
    'pubspec.lock', //
  ]);
  if (packages.exitCode != 0) {
    await _run('flutter', ['pub', 'get'], lane, shell: true);
  }
  await _bash(root, ['tool/lane.sh', 'engine', kCheckLane]);
  return lane;
}

String _lanePath(String root) =>
    '$root/.claude/worktrees/lane-$kCheckLane';

Future<void> _bash(String root, List<String> args) =>
    _run('bash', args, root);

Future<void> _run(
  String exe,
  List<String> args,
  String where, {
  bool shell = false,
}) async {
  final run = await Process.start(
    exe,
    args,
    workingDirectory: where,
    // `flutter` is a .bat on Windows, which only a shell runs.
    runInShell: shell && Platform.isWindows,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await run.exitCode;
  if (code != 0) throw _Unfinished('$exe ${args.join(' ')} exit $code');
}

/// The main checkout: where master is, whichever checkout this runs from.
String _mainCheckout() {
  final common = _git('.', [
    'rev-parse', '--path-format=absolute', '--git-common-dir', //
  ]).replaceAll('\\', '/');
  return common.endsWith('/.git')
      ? common.substring(0, common.length - '/.git'.length)
      : common;
}

/// This machine's one check at a time: a lock the running check holds
/// until it ends, however it ends.
RandomAccessFile? _lockFor(String root) {
  final file = File('$root/.claude/worktrees/.master-check.lock')
    ..parent.createSync(recursive: true);
  final lock = file.openSync(mode: FileMode.append);
  try {
    lock.lockSync(FileLock.exclusive);
    return lock;
  } on FileSystemException {
    lock.closeSync();
    return null;
  }
}

List<String> _describe(MasterRecords records) => [
  'checked: ${records.checked ?? '(never — the next check starts from origin/master)'}',
  'green:   ${records.green ?? '(none yet)'}',
  for (final MapEntry(:key, :value) in records.reds.entries)
    '🔴$key — red since ${value.name} (${_short(value.sha)})',
  for (final MapEntry(:key, :value) in records.misses.entries)
    'missed: $key — $value import(s) away',
];

String _git(String where, List<String> args) {
  final result = Process.runSync('git', ['-C', where, ...args]);
  if (result.exitCode != 0) {
    throw _Unfinished('git ${args.join(' ')}: ${result.stderr}'.trim());
  }
  return (result.stdout as String).trim();
}

List<String> _lines(String text) => [
  for (final line in const LineSplitter().convert(text))
    if (line.trim().isNotEmpty) line.trim(),
];

String _short(String sha) => sha.length > 9 ? sha.substring(0, 9) : sha;

void _say(String message) => stdout.writeln('[master_check] $message');

class _Unfinished implements Exception {
  _Unfinished(this.why);
  final String why;
}
