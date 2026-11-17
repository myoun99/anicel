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
// WHERE: the machine's own cache (machine_cache.dart, which says where
// that is and why it is a file of its own). Per machine on purpose: a
// file's time is this machine's, and every worktree on it shares the one
// record.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'machine_cache.dart';

export 'machine_cache.dart';

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
  final read = readReport(report);
  final prefix = _prefixOf(root);
  final testsOf = <int, List<ReportedTest>>{};
  for (final test in read.tests) {
    (testsOf[test.suite] ??= []).add(test);
  }
  SuiteRun runOf(int suite, String path) {
    final tests = testsOf[suite] ?? const <ReportedTest>[];
    final ends = [for (final test in tests) ?test.end];
    final first = tests.isEmpty ? null : tests.first.start;
    final last = ends.isEmpty ? null : ends.reduce(math.max);
    final open = tests.any((test) => test.end == null);
    return (
      path: _fromRoot(path, prefix),
      ms: first != null && last != null ? last - first : null,
      green: !read.ended || last == null || open
          ? null
          : !tests.any((test) => test.red),
    );
  }

  return [
    for (final MapEntry(key: suite, value: path) in read.paths.entries)
      runOf(suite, path),
  ];
}

/// One test as a `json` file report tells it ([readReport]).
final class ReportedTest {
  ReportedTest(this.suite, this.name, this.start);

  /// The file it is in, by the id [Report.paths] names it by.
  final int suite;
  final String name;

  /// When it started and when it ended, in milliseconds from the run's
  /// start; an [end] of null is a test that never finished.
  final int start;
  int? end;

  /// Whether it ended in anything but success — a failure, an error.
  bool red = false;

  /// A file's load, which the report tells as a test of its own: the
  /// compile, not a test of the file.
  bool get isLoading => name.startsWith('loading ');
}

/// What a `json` file report says ([readReport]).
final class Report {
  /// Each test file by its id, as the report spells it, with `/`.
  final paths = <int, String>{};

  /// Every test, in the order it started.
  final tests = <ReportedTest>[];

  /// Whether the run reached its `done`.
  bool ended = false;
}

/// 🚨THE ONE READING OF A `json` FILE REPORT (2026-11-17, card
/// a-slow-test-cannot-creep). What a file took and whether it was green
/// ([suiteRuns]), what a silent batch is still running (affected_tests'
/// `stillRunning`) and which tests took a minute ([slowTests]) are three
/// views of the same events. ↩️Till then the first two read the report
/// each for itself, and the minute would have been a third — so they are
/// one reader now (the_test_report_is_read_in_one_place_test scans for a
/// fourth). An event with no time is not one: the reporter stamps every
/// event, and only a broken line lacks it.
Report readReport(String text) {
  final report = Report();
  final byId = <int, ReportedTest>{};
  for (final line in const LineSplitter().convert(text)) {
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
        final path = (suite['path'] as String?)?.replaceAll('\\', '/');
        if (path != null) report.paths[suite['id'] as int] = path;
      case 'testStart':
        final test = event['test'] as Map<String, dynamic>;
        final started = ReportedTest(
          test['suiteID'] as int,
          test['name'] as String? ?? '',
          time,
        );
        byId[test['id'] as int] = started;
        report.tests.add(started);
      case 'testDone':
        final test = byId[event['testID']];
        if (test == null) continue;
        test
          ..end = time
          ..red = event['result'] != 'success';
      case 'done':
        report.ended = true;
    }
  }
  return report;
}

/// How [root] begins a path the report spells, compared with no regard to
/// case: Windows' drive letter comes either way.
String _prefixOf(String root) => '${root.replaceAll('\\', '/')}/'.toLowerCase();

/// [path] from the repository's root, when it is under [prefix].
String _fromRoot(String path, String prefix) =>
    path.toLowerCase().startsWith(prefix)
        ? path.substring(prefix.length)
        : path;

/// 🆕A TEST THAT TAKES A MINUTE IS SAID (2026-11-17, card
/// a-slow-test-cannot-creep; 🗣️유저 11-17 「시험 시간 긴거 줄인다던가?
/// 넓은검사 너무 기니까」 — 관제 chose the knob). Google gives each size
/// of test a time and fails the one past it; here it is a WARNING, never a
/// red (관제, as CLAUDE.md keeps the complexity line: a gate makes the
/// work a game of the number). A minute because that is what a wait for
/// what cannot come costs since 10-16 (`waitPatience`, test/helpers/
/// poll_until.dart): on 10-19 the large share of the heaviest files was
/// such waits, each one test of 60 s and more — and one that comes back
/// says nothing unless the run says it. Per TEST, from the report's own
/// testStart → testDone, not per file from a machine's record: a file's
/// time is many tests and one machine's, a test of a minute is a minute
/// anywhere. 🔬The reports this machine still held that day (134 batches,
/// 126,700 tests): 30 tests of a minute or more, most of them 61–79 s.
const kSlowTest = Duration(seconds: 60);

/// A test that took [kSlowTest] or more ([slowTests]).
typedef SlowTest = ({String path, String name, int ms});

/// The tests [report] says took [kSlowTest] or more, slowest first, each by
/// its file's path from [root]. ⛔Not a file's load (the compile, which a
/// crowded machine stretches) nor a test that never finished — the batch
/// cut by its silence says those ([readReport]).
List<SlowTest> slowTests(String report, {required String root}) {
  final read = readReport(report);
  final prefix = _prefixOf(root);
  return [
    for (final test in read.tests)
      if (test.end case final end?
          when !test.isLoading &&
              end - test.start >= kSlowTest.inMilliseconds)
        (
          path: _fromRoot(read.paths[test.suite] ?? '?', prefix),
          name: test.name,
          ms: end - test.start,
        ),
  ]..sort((a, b) => b.ms.compareTo(a.ms));
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
