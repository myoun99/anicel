// How long each test file took on this machine — so a run hands its longest
// files out first.
//
// 🆕2026-10-18 (card tests-crowd-the-machine). A batch ends when its slowest
// file ends, and `flutter test` starts files in the order it is given them.
// Measured on the main PC: 60 timeline files at four at a time took 205s
// while their run times summed to 697s — 174s of work per slot — because
// the 75s file started near the end and ran alone. Handed out longest
// first, the long ones run beside the many short ones and the tail goes.
// That is the classic longest-processing-time-first rule; what it needs is
// the time, and a run leaves it in a JSON report beside its console
// (`--file-reporter`), so the console a session reads is unchanged.
//
// WHERE: the machine's own cache, beside `tool/run.sh`'s exes —
// `%LOCALAPPDATA%\anicel` on Windows, `~/.cache/anicel` elsewhere. ⛔The
// same place spelled twice (here and in run.sh): change both or neither.
// Per machine on purpose: a file's time is this machine's, and every
// worktree on it shares the one record.
import 'dart:convert';
import 'dart:io';

/// This machine's folder for what the tools keep between runs, or null if
/// the environment names none.
String? machineCacheFolder(Map<String, String> environment) {
  final local = environment['LOCALAPPDATA'];
  if (local != null && local.isNotEmpty) {
    return '${local.replaceAll('\\', '/')}/anicel';
  }
  final xdg = environment['XDG_CACHE_HOME'];
  if (xdg != null && xdg.isNotEmpty) return '$xdg/anicel';
  final home = environment['HOME'];
  return home == null || home.isEmpty ? null : '$home/.cache/anicel';
}

/// `<path>\t<value>` per line — every record the tools keep in
/// [machineCacheFolder]. A line that is not one is skipped: two runs that
/// wrote at once leave, at worst, a file to measure or run again.
Map<String, String> readPairs(String text) => {
  for (final line in const LineSplitter().convert(text))
    if (line.split('\t') case [final path, final value]
        when path.isNotEmpty && value.isNotEmpty)
      path: value,
};

String writePairs(Map<String, Object> pairs) => [
  for (final path in (pairs.keys.toList()..sort())) '$path\t${pairs[path]}\n',
].join();

/// Rewrites the record [file] with what [update] makes of what it holds.
/// Read again just before the write, and written whole and renamed into
/// place, so two runs that finish together lose at most a line, never the
/// file.
void updatePairs(
  File file,
  Map<String, Object> Function(Map<String, String> known) update,
) {
  file.parent.createSync(recursive: true);
  final known = file.existsSync()
      ? readPairs(file.readAsStringSync())
      : const <String, String>{};
  final part = File('${file.path}.$pid.part')
    ..writeAsStringSync(writePairs(update(known)));
  part.renameSync(file.path);
}

/// The times record: `<path>\t<milliseconds>`.
Map<String, int> readTimes(String text) => timesIn(readPairs(text));

/// The times in a record's [pairs]; a value that is no number is skipped.
Map<String, int> timesIn(Map<String, String> pairs) => {
  for (final MapEntry(key: path, value: ms) in pairs.entries)
    path: ?int.tryParse(ms),
};

/// What a `json` report says of one test file, by its path from the
/// repository's root with `/`: how long it took from its loading to its
/// last test, and whether it was green — null for either when the report
/// cannot say.
typedef SuiteRun = ({String path, int? ms, bool? green});

/// Every test file in a `json` report ([SuiteRun]), keyed by its path
/// from [root].
///
/// ⛔GREEN ONLY FROM A RUN THAT ENDED. A file is green when every test it
/// finished passed and none was left open — and only when the report
/// reached its `done`: a run killed by a time limit leaves files whose
/// finished tests all passed, and those are not green. A test skipped
/// counts as passed; a file that failed to load is a hidden test that
/// ends in `error`, and red.
List<SuiteRun> suiteRuns(String report, {required String root}) {
  final prefix = '${root.replaceAll('\\', '/')}/'.toLowerCase();
  final path = <int, String>{};
  final first = <int, int>{};
  final last = <int, int>{};
  final suiteOf = <int, int>{};
  final open = <int, int>{};
  final red = <int>{};
  var ended = false;
  for (final line in const LineSplitter().convert(report)) {
    final Object? event;
    try {
      event = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (event is! Map<String, dynamic>) continue;
    final time = event['time'];
    if (time is! int) continue;
    switch (event['type']) {
      case 'suite':
        final suite = event['suite'] as Map<String, dynamic>;
        final p = (suite['path'] as String?)?.replaceAll('\\', '/');
        if (p != null) path[suite['id'] as int] = p;
      case 'testStart':
        final test = event['test'] as Map<String, dynamic>;
        final suite = test['suiteID'] as int;
        suiteOf[test['id'] as int] = suite;
        first.putIfAbsent(suite, () => time);
        open[suite] = (open[suite] ?? 0) + 1;
      case 'testDone':
        final suite = suiteOf[event['testID'] as int];
        if (suite == null) continue;
        last[suite] = time;
        open[suite] = open[suite]! - 1;
        if (event['result'] != 'success') red.add(suite);
      case 'done':
        ended = true;
    }
  }
  return [
    for (final MapEntry(key: suite, value: p) in path.entries)
      (
        path: p.toLowerCase().startsWith(prefix)
            ? p.substring(prefix.length)
            : p,
        ms: first[suite] != null && last[suite] != null
            ? last[suite]! - first[suite]!
            : null,
        green: !ended || last[suite] == null || open[suite] != 0
            ? null
            : !red.contains(suite),
      ),
  ];
}

/// Each test file's time among [runs] ([suiteRuns]).
Map<String, int> timesOf(List<SuiteRun> runs) => {
  for (final run in runs) run.path: ?run.ms,
};

/// [known] with [measured] laid over it: a file measured again keeps the
/// mean of the two, so one slow run on a crowded machine moves it halfway.
Map<String, int> merged(Map<String, int> known, Map<String, int> measured) => {
  ...known,
  for (final MapEntry(key: path, value: ms) in measured.entries)
    path: known[path] == null ? ms : (known[path]! + ms) ~/ 2,
};

/// [files] with the longest first by [known]. A file never timed goes ahead
/// of all of them: it may be the longest, and running it early times it.
/// Equal times keep their order, so the same record gives the same run.
List<String> longestFirst(List<String> files, Map<String, int> known) {
  final order = [for (var i = 0; i < files.length; i++) i];
  int rank(String file) => known[file] ?? 1 << 30;
  order.sort((a, b) {
    final byTime = rank(files[b]).compareTo(rank(files[a]));
    return byTime != 0 ? byTime : a.compareTo(b);
  });
  return [for (final i in order) files[i]];
}

/// A file never timed, counted at this — about the mean of the files this
/// machine has timed (9.3s over 2,583 files, 10-20) — so a run of untimed
/// files is neither free nor the whole machine.
const kUntimedFileMs = 10000;

/// The machine-seconds [files] should take by [known]: what each took last
/// time, [kUntimedFileMs] for one never timed.
int workOf(Iterable<String> files, Map<String, int> known) =>
    files.fold(0, (sum, file) => sum + (known[file] ?? kUntimedFileMs)) ~/
    1000;

/// [files] cut into batches of about [work] machine-seconds each, every
/// batch longest first, and none past [fits] (the command line's budget).
///
/// 🗣️유저 10-20, tests-crowd-the-machine-Q6 「전부」: a run's suites are
/// fixed for a whole `flutter test`, so a batch is how long the line goes
/// without deciding again. 🧪That day one batch held five suites for 26
/// minutes (the 110 heaviest timeline files, cut only by the command
/// line's length) while eleven runs of three to thirteen files waited
/// behind it — the longest an hour and three quarters.
///
/// The files are dealt longest first to whichever batch holds the least so
/// far — the longest-processing-time rule [longestFirst] already runs a
/// batch by, applied to the batches themselves — so every batch starts on
/// its heavy files and ends on light ones, and no batch is left with only
/// the tail. ⚖️A batch costs its `flutter test`'s start, 5~15s measured
/// that day, which is why a batch is minutes and not one file.
List<List<String>> timedBatches(
  List<String> files,
  Map<String, int> known, {
  required int work,
  bool Function(List<String> batch) fits = _anyLength,
}) {
  if (files.isEmpty) return const [];
  final ordered = longestFirst(files, known);
  for (var count = (workOf(files, known) / work).ceil().clamp(1, files.length);
      ;
      count++) {
    final batches = [for (var i = 0; i < count; i++) <String>[]];
    final load = List.filled(count, 0);
    for (final file in ordered) {
      var least = 0;
      for (var i = 1; i < count; i++) {
        if (load[i] < load[least]) least = i;
      }
      batches[least].add(file);
      load[least] += known[file] ?? kUntimedFileMs;
    }
    if (count == files.length || batches.every(fits)) return batches;
  }
}

bool _anyLength(List<String> batch) => true;
