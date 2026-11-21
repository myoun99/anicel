// ONE CI SHARD'S SLICE OF THE SUITE — weighed by the seconds each file took
// in CI's last run, so that the shards end together.
//
//   dart tool/test_shard.dart deal --total N --index I
//       [--times <record>] [--leave-out <list>] [--behind-ms <i>=<ms>,…]
//   dart tool/test_shard.dart seed --times <record>
//   dart tool/test_shard.dart keep --files <list> --to <record>
//
// `deal` prints, one path a line, the test files shard I of N runs. `seed`
// lays a record over this machine's own (test_seconds.dart), so the shard's
// run orders and batches its files by it too. `keep` writes this machine's
// times for the files in <list> — what the shard hands the next run. A
// record is `<path>\t<milliseconds>` a line ([readTimes]). Run from the
// repository root (.github/actions/test-shard runs all three).
//
// 🆕2026-11-17 (card ci-shards-dealt-by-measured-seconds — 관제, for 유저
// 「넓은검사 너무 기니까 최대한 효율적으로 … 구글이나 메타 … 거기서 하는방식」:
// split by recorded time, as Chromium's sharding, CircleCI's timing split and
// Knapsack do). ↩️Till then the action dealt by each file's SIZE, in awk:
// three times the size for a test that opens the app. Measured on the three
// Linux shards of run 44026201673 that correlates 0.53 with the time a file
// took, and dealt six ways its longest shard was 31.9 minutes. The size was
// chosen because a CHECKED-IN timings table goes stale silently; a record
// that each run writes and the next run reads is never older than a run.
//
// ⚖️WHICH RUN: the last one of CI that left a record, whatever its event —
// since a master push whose tree a pull request already passed stands down
// (ci.yml's scope job), nearly every run that tests is a bundle PR's. The
// scope job picks it ONCE and hands every shard the same record: a shard
// that read another record would deal other piles, and a file would run
// twice or not at all.
//
// A file with no record — new since that run, or every file when no run
// left one — is weighed as before, by its size (x3 if it opens the app),
// scaled to milliseconds by what the timed files took for their sizes, so
// the estimate and the record are one unit. ⛔A test file named below that
// is not there is an error, not an empty set (the size deal's rule): a
// rename would otherwise leave the estimate on nothing, and a slow shard
// looks exactly like a normal one
// (test/architecture/the_shards_weigh_files_that_are_there_test.dart).
import 'dart:io';

import 'import_graph.dart';
import 'test_seconds.dart';

/// The files whose tests open the app: what a file reaching one of them
/// weighs three times its size when no run timed it (ci-takes-an-hour-on-
/// lavapipe: on run 44026201673 those 385 files of 2,209 took 62% of the
/// time, 1,348 ms a KB against 188 for the rest — size alone correlates
/// 0.44, size x3 for these 0.53, x2 0.52, x5 0.51, x7 0.49). ⚖️NOT the tests
/// that reach the GPU engine: 76% of the files reach it, the size deal
/// already spread them evenly, and weighing them lowered the correlation to
/// 0.42.
const kOpensTheApp = [
  'lib/src/ui/home_page.dart',
  'lib/src/ui/editor_workspace.dart',
];

/// What a file that opens the app weighs per byte against one that does
/// not, when no run timed it ([kOpensTheApp]).
const kOpensTheAppFactor = 3;

/// The weight each of [sizes]' files is dealt by: the milliseconds [known]
/// says it took, or — with no record of it — its size (times
/// [kOpensTheAppFactor] if it is one of [opensTheApp]) at the milliseconds
/// a byte the timed files took. With no file timed a byte weighs one: the
/// size deal, unit and all.
Map<String, int> shardWeights({
  required Map<String, int> sizes,
  required Set<String> opensTheApp,
  required Map<String, int> known,
}) {
  int bytes(String file) =>
      sizes[file]! * (opensTheApp.contains(file) ? kOpensTheAppFactor : 1);
  var timedMs = 0;
  var timedBytes = 0;
  for (final file in sizes.keys) {
    final ms = known[file];
    if (ms == null) continue;
    timedMs += ms;
    timedBytes += bytes(file);
  }
  final perByte = timedBytes == 0 ? 1.0 : timedMs / timedBytes;
  return {
    for (final file in sizes.keys)
      file: known[file] ?? (bytes(file) * perByte).round(),
  };
}

/// [files] dealt to [total] shards by [weights], longest first to the
/// lightest ([dealt]). Ties go by [files]' order, so give them sorted.
///
/// [behind]: the milliseconds of test time each shard is behind before
/// its first test, by its index — none for a shard not named.
///
/// 🔬Run 44754294330 (11-20 · card ci-shards-dealt-by-measured-seconds,
/// 🤖AI 검증 실패 11-21): shard 0 runs `flutter analyze` before its tests
/// (ci.yml — the merge gate's, so it stays there) and its tests began 93 s
/// after the other five's, which the deal did not know: it gave all six
/// the same 2,541 s. That shard ended last, 11:31 after the first.
List<List<String>> shardsOf(
  List<String> files,
  Map<String, int> weights, {
  required int total,
  Map<int, int> behind = const {},
}) => dealt(
  longestFirst(files, weights),
  total,
  (file) => weights[file]!,
  loadedWith: [for (var index = 0; index < total; index++) behind[index] ?? 0],
);

/// What [behind] loads the deal with: itself where the weights are
/// milliseconds — some file of [files] timed in [known] — and nothing
/// where they are bytes: with no file timed a file weighs its size
/// ([shardWeights]), and a shard's milliseconds behind are of no unit the
/// deal holds.
Map<int, int> behindInTheDeal(
  Map<int, int> behind,
  Iterable<String> files,
  Map<String, int> known,
) => files.any(known.containsKey) ? behind : const {};

/// What a shard hands the next run: [known]'s times of [files], its own
/// slice, and of nothing else. The shards' records then never overlap, and
/// the scope job that joins them needs no rule for two values of one file —
/// ⛔with the record the shard was seeded with in it too, every shard's
/// would hold every file, and the last one joined would speak for files it
/// never ran.
Map<String, int> shardRecord(Map<String, int> known, Set<String> files) => {
  for (final MapEntry(key: file, value: ms) in known.entries)
    if (files.contains(file)) file: ms,
};

void main(List<String> args) {
  final verb = args.isEmpty ? null : args.first;
  final options = _options(args.skip(1).toList());
  if (options == null) return _usage();
  switch (verb) {
    case 'deal':
      final total = int.tryParse(options['--total'] ?? '');
      final index = int.tryParse(options['--index'] ?? '');
      if (total == null || index == null || index < 0 || index >= total) {
        return _usage();
      }
      final behind = _behind(options['--behind-ms']);
      if (behind == null) return _usage();
      _deal(
        total: total,
        index: index,
        times: options['--times'],
        leaveOut: options['--leave-out'],
        behind: behind,
      );
    case 'seed':
      final times = options['--times'];
      if (times == null) return _usage();
      _seed(times);
    case 'keep':
      final files = options['--files'];
      final to = options['--to'];
      if (files == null || to == null) return _usage();
      _keep(files: files, to: to);
    default:
      _usage();
  }
}

/// `--behind-ms`'s `<index>=<ms>,…` as a map — empty where it is not
/// given, null where it does not read.
Map<int, int>? _behind(String? option) {
  if (option == null || option.isEmpty) return const {};
  final behind = <int, int>{};
  for (final pair in option.split(',')) {
    final parts = pair.split('=');
    final at = parts.length == 2 ? int.tryParse(parts.first) : null;
    final much = parts.length == 2 ? int.tryParse(parts.last) : null;
    if (at == null || much == null) return null;
    behind[at] = much;
  }
  return behind;
}

void _deal({
  required int total,
  required int index,
  required String? times,
  required String? leaveOut,
  required Map<int, int> behind,
}) {
  final missing = [
    for (final path in kOpensTheApp)
      if (!File(path).existsSync()) path,
  ];
  if (missing.isNotEmpty) {
    stderr.writeln('no such file: ${missing.join(', ')}');
    exit(2);
  }
  final graph = buildImportGraph(roots: kGraphRoots);
  final out = leaveOut == null ? const <String>{} : _lines(leaveOut);
  final files = [
    for (final file in graph.keys.where(isSuite).toList()..sort())
      if (!out.contains(file)) file,
  ];
  final known = times == null ? const <String, int>{} : _timesIn(times);
  final weights = shardWeights(
    sizes: {for (final file in files) file: File(file).lengthSync()},
    opensTheApp: testsReaching(kOpensTheApp.toSet(), graph),
    known: known,
  );
  final timed = files.where(known.containsKey).length;
  final behindHere = behindInTheDeal(behind, files, known);
  final shards = shardsOf(files, weights, total: total, behind: behindHere);
  stdout.write(shards[index].map((file) => '$file\n').join());
  final seconds = [
    for (final shard in shards)
      shard.fold(0, (sum, file) => sum + weights[file]!) ~/ 1000,
  ];
  final late = [
    for (final MapEntry(key: shard, value: ms) in behindHere.entries)
      'shard $shard ${ms ~/ 1000} s behind',
  ];
  stderr.writeln(
    '${files.length} files${out.isEmpty ? '' : ' (${out.length} left out)'}'
    ': $timed weighed by the seconds the last run took,'
    ' ${files.length - timed} by their size'
    '${timed == 0 ? '' : ' — each shard about ${seconds.join(' / ')} s'}'
    '${late.isEmpty ? '' : ' (${late.join(', ')})'}',
  );
}

void _seed(String times) {
  final record = timesRecord(Platform.environment);
  if (record == null) {
    stderr.writeln('this machine names no cache folder — nothing seeded');
    return;
  }
  final laid = _timesIn(times);
  updatePairs(record, (known) => merged(timesIn(known), laid));
}

void _keep({required String files, required String to}) {
  // A deal that failed left no list: nothing of this shard was run.
  final mine = File(files).existsSync() ? _lines(files) : const <String>{};
  final kept = shardRecord(timesOnThisMachine(), mine);
  File(to)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(writePairs(kept));
}

Map<String, int> _timesIn(String path) {
  final file = File(path);
  return file.existsSync()
      ? readTimes(file.readAsStringSync())
      : const <String, int>{};
}

Set<String> _lines(String path) => {
  for (final line in File(path).readAsLinesSync())
    if (line.trim().isNotEmpty) line.trim().replaceAll('\\', '/'),
};

/// `--name value` pairs, or null when one has no value.
Map<String, String>? _options(List<String> args) {
  if (args.length.isOdd) return null;
  return {
    for (var i = 0; i < args.length; i += 2)
      if (args[i].startsWith('--')) args[i]: args[i + 1] else '': '',
  }..remove('');
}

void _usage() {
  stderr.writeln(
    'usage: dart tool/test_shard.dart deal --total N --index I'
    ' [--times <record>] [--leave-out <list>]\n'
    '           [--behind-ms <index>=<ms>,…]\n'
    '       dart tool/test_shard.dart seed --times <record>\n'
    '       dart tool/test_shard.dart keep --files <list> --to <record>',
  );
  exit(2);
}
