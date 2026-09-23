// Which tests can this change actually have broken?
//
// The full suite is 733 files and the better part of half an hour, and most
// of that is spent proving that code nobody touched still works. This walks
// the import graph backwards from the files you changed and runs only the
// tests that can reach them. Measured on this repository: a median change
// selects about a third of the suite and finishes in 1252s against 1760s,
// 1.41x — smaller than it sounds like it should be, because a handful of
// model files are imported by most of the tree.
//
// It is a LOCAL tool and deliberately not a CI one. CI keeps running
// everything: the whole point of a safety net is that it does not share the
// assumptions of the thing it is catching. What this buys is the edit-run
// loop, where waiting 29 minutes to learn about a typo is the tax.
//
// Where it refuses to guess, it runs everything. That is the only safe
// direction for a tool like this to be wrong in.
//
// Usage:
//   dart run tool/affected_tests.dart            # run them
//   dart run tool/affected_tests.dart --list     # print them, run nothing
//   dart run tool/affected_tests.dart --all      # the escape hatch
//   dart run tool/affected_tests.dart --base HEAD~3
//
// Exit code is flutter test's own, or 0 when nothing needed running.

import 'dart:convert';
import 'dart:io';

import 'import_graph.dart';
import 'native_engine_provenance.dart';

/// Changing one of these means the graph cannot answer, so we do not ask it.
///
/// Dependencies and toolchain change what every file compiles to; the native
/// sources sit behind FFI where no import edge reaches them; the platform
/// directories decide what the app links against; and
/// `test/flutter_test_config.dart` is loaded by flutter_test before every
/// suite in the tree while nothing imports it — an edge the graph cannot
/// see because it does not exist in the source.
const _runEverything = <String>[
  'pubspec.yaml',
  'pubspec.lock',
  'analysis_options.yaml',
  'dart_test.yaml',
  'packages/',
  'android/',
  'ios/',
  'linux/',
  'macos/',
  'windows/',
  'test/flutter_test_config.dart',
];

/// The tag [gcTagMarker] writes, as `--exclude-tags` names it.
const gcTag = 'gc';

/// The marker a file writes to say 「my assertion waits for the garbage
/// collector」 — see [partitionByGcTag].
const gcTagMarker = "@Tags(['$gcTag'])";

/// Splits the run into the [crowd] and the ones that go [alone].
///
/// 🚨★★★**A PIN THAT WAITS FOR THE COLLECTOR CANNOT RUN IN A CROWD.**
/// `flutter test` runs a batch's files in concurrent isolates, and a full
/// collection under a hundred of them is scheduled when the machine gets
/// round to it. The pins that read a [WeakReference] then give up on a
/// bounded wait and report what they see — which under that load is 「still
/// alive」 for a holder that has already let go.
///
/// 🔬Measured, twice, on two different files: `tile_images_are_counted`
/// lost one tile's 64 bytes inside a parity batch and was green alone
/// (2026-09-11), and `a_parked_transform_lets_go_of_its_picture` went red
/// in an 822-test batch, green alone AND green across its own 476-test
/// directory (2026-09-18) — the second time blocking a landing.
///
/// ⛔**NOT by raising the bound.** That is the same instrument shaken
/// harder: the wait already gives up in seconds by design, because an
/// unbounded one took this suite past ten gigabytes and the runner's
/// ten-minute cap. What is wrong is the COMPANY, not the patience.
///
/// ⚠️It is a whole-FILE question because the tag is a library annotation,
/// so partitioning by file is exact — no `--exclude-tags` pass that could
/// come back 「no tests match」 and read as a failure to start. (The whole
/// suite is the one run that does exclude it, and [runPlan] says why that
/// one cannot come back empty.)
({List<String> crowd, List<String> alone}) partitionByGcTag(
  List<String> files,
  String Function(String path) read,
) {
  final crowd = <String>[];
  final alone = <String>[];
  for (final file in files) {
    (read(file).contains(gcTagMarker) ? alone : crowd).add(file);
  }
  return (crowd: crowd, alone: alone);
}

/// The `flutter test` argument lists one run is made of: the [crowd], in as
/// many commands as the command line allows, then the pins that wait for
/// the collector, [alone] and last.
///
/// [selected] empty means THE WHOLE SUITE, and [suite] is then every test
/// file there is. Its crowd stays ONE command that names no files — a whole
/// suite of paths is far past what [batches] splits against — and leaves
/// the tag out instead, which cannot come back 「no tests match」 with
/// thousands of others in it.
///
/// 🚨**THE WHOLE SUITE USED TO SKIP THE SPLIT.** An empty selection names
/// no files to partition, so it stayed one command with every file in it,
/// the pins included — and every run a blanket file forces (the test
/// config, `windows/`, the pubspec) and `--all` ran them in the crowd
/// [partitionByGcTag] exists to keep them out of. The parked-transform pin
/// went red that way in a whole-suite gate (2026-09-23, 「16 tiles, 16
/// still alive」, green in its own batch) — that file's third time.
({List<List<String>> crowd, List<String> alone}) runPlan({
  required List<String> selected,
  required List<String> suite,
  required String Function(String path) read,
  required List<List<String>> Function(List<String> files) batches,
}) {
  if (selected.isEmpty) {
    final alone = partitionByGcTag(suite, read).alone;
    final crowd = alone.isEmpty
        ? const <String>[]
        : const ['--exclude-tags', gcTag];
    return (crowd: [crowd], alone: alone);
  }
  final split = partitionByGcTag(selected, read);
  // ⛔An empty command IS the whole suite, so a selection of nothing but
  // pins has no crowd at all — [batches] off Windows hands an empty list
  // back as one empty batch.
  return (
    crowd: split.crowd.isEmpty ? const <List<String>>[] : batches(split.crowd),
    alone: split.alone,
  );
}

/// What a change to [changedDart] can have broken, out of [tests].
Set<String> selectTests({
  required Set<String> changedDart,
  required List<String> tests,
  required Map<String, Set<String>> imports,
  required String Function(String path) read,
}) => {
  // A changed test runs because it changed, whatever it imports.
  ...changedDart.where((f) => f.startsWith('test/') && f.endsWith('_test.dart')),
  // Everything that can reach a changed file, however far away.
  for (final test in tests)
    if (closureOf(test, imports).any(changedDart.contains)) test,
  // And every source scan that reads where a changed file lives — the one
  // dependency no edge carries.
  ...scansReaching(changedDart, tests, read),
};

/// The [tests] that read, as text, a `lib` path holding one of the [changed]
/// files — the source scans no import edge reaches. See
/// [libPrefixesReadAsText] for the round they were missing from.
List<String> scansReaching(
  Set<String> changed,
  Iterable<String> tests,
  String Function(String path) read,
) => [
  for (final test in tests)
    if (libPrefixesReadAsText(read(test)).any(
      (prefix) => changed.any((file) => file.startsWith(prefix)),
    ))
      test,
];

Future<void> main(List<String> args) async {
  final listOnly = args.contains('--list');
  final runAll = args.contains('--all');
  final base = _flagValue(args, '--base') ?? 'origin/master';

  final root = _repoRoot();
  if (root == null) {
    stderr.writeln('not inside a git checkout.');
    exit(2);
  }
  Directory.current = root;

  if (runAll) {
    _report('--all: running the whole suite.');
    exit(await _runTests(const [], listOnly: listOnly));
  }

  final changed = _changedFiles(base);
  if (changed.isEmpty) {
    _report('nothing has changed against $base — nothing to run.');
    exit(0);
  }

  final blanket = changed.where(_forcesFullRun).toList()..sort();
  if (blanket.isNotEmpty) {
    _report('running everything: ${blanket.first} changed'
        '${blanket.length > 1 ? ' (and ${blanket.length - 1} more like it)' : ''}.');
    exit(await _runTests(const [], listOnly: listOnly));
  }

  final imports = buildImportGraph();
  final tests = _suitesIn(imports);

  final changedDart = changed.where((f) => f.endsWith('.dart')).toSet();
  final selected = selectTests(
    changedDart: changedDart,
    tests: tests,
    imports: imports,
    read: (path) => File(path).readAsStringSync(),
  );

  final present = selected.where((f) => File(f).existsSync()).toList()..sort();
  if (present.isEmpty) {
    _report('no test reaches the ${changedDart.length} changed Dart file(s).');
    exit(0);
  }

  _report('${present.length} of ${tests.length} test files reach the '
      '${changedDart.length} changed Dart file(s).');
  exit(await _runTests(present, listOnly: listOnly));
}

String? _flagValue(List<String> args, String name) {
  final i = args.indexOf(name);
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}

void _report(String message) => stdout.writeln('[affected] $message');

Directory? _repoRoot() {
  final result = Process.runSync('git', ['rev-parse', '--show-toplevel']);
  if (result.exitCode != 0) return null;
  return Directory((result.stdout as String).trim());
}

/// Committed changes against the merge base, plus whatever is still in the
/// working tree — the edit-run loop is mostly the latter.
Set<String> _changedFiles(String base) {
  final merged = <String>{};
  final mergeBase =
      Process.runSync('git', ['merge-base', base, 'HEAD']).stdout as String;
  final from = mergeBase.trim().isEmpty ? base : mergeBase.trim();
  merged.addAll(_gitLines(['diff', '--name-only', from, 'HEAD']));
  merged.addAll(_gitLines(['diff', '--name-only', 'HEAD']));
  merged.addAll(_gitLines(['diff', '--name-only', '--cached']));
  merged.addAll(_gitLines(['ls-files', '--others', '--exclude-standard']));
  return merged.where((f) => f.isNotEmpty).toSet();
}

List<String> _gitLines(List<String> args) {
  final result = Process.runSync('git', args);
  if (result.exitCode != 0) return const [];
  return (result.stdout as String)
      .split('\n')
      .map((l) => l.trim().replaceAll('\\', '/'))
      .where((l) => l.isNotEmpty)
      .toList();
}

bool _forcesFullRun(String path) => _runEverything.any(
      (prefix) => prefix.endsWith('/') ? path.startsWith(prefix) : path == prefix,
    );

/// The files `flutter test` runs as suites, out of [graph].
///
/// The graph covers everything under test/ — helpers, fixtures and
/// flutter_test_config.dart included, because tests reach their changed
/// dependencies through those. Only files flutter test will actually run
/// as a suite may be handed back, though: passing it the config would ask
/// it to run a file that defines no tests.
List<String> _suitesIn(Map<String, Set<String>> graph) => graph.keys
    .where((f) => f.startsWith('test/') && f.endsWith('_test.dart'))
    .toList()
  ..sort();

/// Every suite there is — what a whole-suite run has to find its collector
/// pins among ([runPlan]).
List<String> _suiteFiles() =>
    _suitesIn(buildImportGraph(roots: const ['test']));


/// How many characters of arguments one invocation may carry.
///
/// `flutter` is a .bat, so on Windows the whole command line goes through
/// cmd.exe's ~8191-character buffer whatever launched it. A selection of
/// 214 files is about 9,800 characters, and the failure is not subtle —
/// "コマンド ラインが長すぎます", exit 1, no tests run. The CI shard action
/// has carried `xargs -0 -s 6000` against this exact wall since the day it
/// was written; this tool shipped without it and was caught the first time
/// somebody changed a widely-imported file.
///
/// 6000 keeps 2k of daylight below the real ceiling. Elsewhere ARG_MAX is
/// megabytes and one batch is always enough.
const _argBudget = 6000;

/// Split so no invocation exceeds the budget. A file that is somehow longer
/// than the whole budget still goes out alone rather than being dropped —
/// failing loudly beats running less than we said we would.
List<List<String>> _batches(List<String> files) {
  if (!Platform.isWindows) return [files];
  final out = <List<String>>[];
  var current = <String>[];
  var length = 0;
  for (final file in files) {
    final cost = file.length + 1;
    if (current.isNotEmpty && length + cost > _argBudget) {
      out.add(current);
      current = <String>[];
      length = 0;
    }
    current.add(file);
    length += cost;
  }
  if (current.isNotEmpty) out.add(current);
  return out;
}

Future<int> _runTests(List<String> files, {required bool listOnly}) async {
  // The collector-waiting pins go last and by themselves, a whole suite
  // included — see [runPlan].
  final plan = runPlan(
    selected: files,
    suite: files.isEmpty ? _suiteFiles() : const [],
    read: (path) => File(path).readAsStringSync(),
    batches: _batches,
  );
  final batches = [...plan.crowd, if (plan.alone.isNotEmpty) plan.alone];
  if (listOnly) {
    for (final batch in batches) {
      final wholeSuite = batch.isEmpty || batch.first.startsWith('--');
      stdout.writeln(
        wholeSuite ? '(the whole suite) ${batch.join(' ')}' : batch.join('\n'),
      );
    }
    return 0;
  }

  // 🚨THE ENGINE IS PART OF WHAT A RUN MEASURES. Every suite loads the build
  // under build/native_standalone, and a build from other C turns that C's
  // behaviour into this checkout's reds and greens — 156 reds once, found by
  // running the same files in another checkout (2026-09-13; the whole story
  // is at the head of native_engine_provenance.dart). Said before the run,
  // so it can be stopped, and again beside the verdict it qualifies.
  final engine = _engineCaveat();
  if (engine != null) _report(engine);

  if (plan.alone.isNotEmpty) {
    _report('${plan.alone.length} pin(s) wait for the garbage collector '
        '($gcTagMarker) and run in a batch of their own — in company they '
        'report a holder that has already let go.');
  }
  if (plan.crowd.length > 1) {
    _report('${plan.crowd.expand((batch) => batch).length} files exceed the '
        'command-line budget: running them in ${plan.crowd.length} batches. '
        'Each batch pays the resident compiler\'s cold start again.');
  }

  var worst = 0;
  var skipped = 0;
  final failed = <int>[];
  final neverRan = <int>[];
  for (var i = 0; i < batches.length; i++) {
    if (batches.length > 1) _report('batch ${i + 1} of ${batches.length}');
    final result = await _flutterTest(batches[i]);
    skipped += result.skipped;
    if (result.exitCode != 0) {
      failed.add(i + 1);
      if (!result.ranTests) neverRan.add(i + 1);
      if (worst == 0) worst = result.exitCode;
    }
  }

  // A batch that exits non-zero having run NOTHING is not a test failure,
  // and reading it as one costs an hour. It happened on this tool's first
  // day in anger: an over-long command line made cmd.exe refuse to launch
  // flutter at all, and what reached the reader was exit 1 plus a single
  // mojibake line in the system locale — indistinguishable at a glance
  // from a red suite. The message below is the distinction, drawn from
  // whether any test result appeared rather than from parsing an error
  // string we cannot even decode.
  if (neverRan.isNotEmpty) {
    _report('batch(es) ${neverRan.join(', ')} FAILED TO START — no test '
        'result came back at all, so this is not a failing test. Look at '
        'the launch error above, not at the suite.');
  }

  // The verdict goes LAST and says the word, because a run this long is
  // read through `tail` and a pipeline reports the exit code of whatever
  // ended it. A green tail under a red run has already nearly been
  // believed once.
  if (failed.isEmpty) {
    _report('PASSED (${batches.length} batch(es), exit 0)');
  } else {
    _report('FAILED — batch(es) ${failed.join(', ')} of ${batches.length}, '
        'exit $worst');
  }
  _reportSkips(skipped);
  if (engine != null) _report(engine);
  return worst;
}

/// What to say when the engine the suites load was not built from the C in
/// this checkout, or null when there is nothing to say.
///
/// No engine at all says nothing here: the suites skip, and a skip is
/// already reported by name.
String? _engineCaveat() {
  const rebuild = 'Rebuild it from this checkout: bash tool/lane.sh engine';
  final root = Directory.current.path;
  final source = nativeSourceId(root);
  if (source == null) {
    return '⚠️this checkout holds no $nativeSourceDir, so whether the engine '
        'was built from it is unchecked.';
  }
  String short(String id) => id.length > 8 ? id.substring(0, 8) : id;
  return switch (engineProvenance(root, source)) {
    EngineProvenance.current || EngineProvenance.absent => null,
    EngineProvenance.foreign =>
      '⚠️THE ENGINE WAS BUILT FROM OTHER C (${short(engineStampOf(root)!)}; '
          'this checkout holds ${short(source)}) — every native result '
          'describes that C. $rebuild',
    EngineProvenance.unstamped =>
      '⚠️the engine does not say which C it was built from — native results '
          'may describe other C. $rebuild',
  };
}

/// Says out loud when tests were skipped, and what usually causes it here.
void _reportSkips(int skipped) {
  if (skipped == 0) return;
  _report('⚠️$skipped test(s) SKIPPED — a skip is not a pass.');
  // 🪦IT USED TO SAY 「every skip in this tree is a native-engine gate」 and
  // hand over two cmake lines. That was true, then it was half true, and on
  // 2026-09-08 it stopped being true at all — the last native gate that
  // could skip on a built machine was a WIRING bug, not a missing binary
  // (two resolvers for「where is the engine」; see
  // `native_engine_present_test`). A hint that names the wrong cause is
  // worse than none: it was read, followed, and the real cause sat behind
  // it for a round.
  //
  // 🧪Measured after that fix, whole suite, no environment variable: 16
  // skips, and every one of them is deliberate — 15 benchmarks tagged out
  // of the default run, and the CI-only engine pin.
  _report('  Name them. The reasons print beside each one (`Skip: …`), and '
      'the two');
  _report('  that are FINE are the benchmarks (--tags benchmark) and the '
      'CI-only');
  _report('  engine pin. Anything else is a pin that is not running.');
  _report('  A native pin skipping usually means no binary. Build one, '
      'stamped with the C');
  _report('  it came from: bash tool/lane.sh engine');
  _report('  ⛔But a built binary can skip too — that is a resolver that '
      'cannot see it,');
  _report('  and `native_engine_present_test` is the pin that says so.');
}

class _BatchResult {
  const _BatchResult(this.exitCode, this.ranTests, this.skipped);
  final int exitCode;
  final bool ranTests;

  /// How many tests the run SKIPPED. See [lastSkipCount].
  final int skipped;
}

/// The skip count in `flutter test` output, or null if it says none.
///
/// 🚨★★★A SKIP IS NOT A PASS, AND THIS IS THE ONLY PLACE THAT SAYS SO.
///
/// `flutter test` prints `00:03 +42 ~2: All tests passed!` — the tilde is
/// two tests that did not run, and the sentence beside it still says passed.
/// The counter is cumulative, so the LAST tilde in a batch is that batch is
/// total.
///
/// 🧪This exists because knowing was not enough. The memory file
/// `affected-tests-not-full-suite.md` has said since 2026-08-28 that a
/// missing native engine turns every parity pin into an empty stub, and told
/// the reader to check the tilde. On 2026-09-01 I read that line, saw `~2`,
/// wrote 「a known local condition」 and carried on — and the fix was one
/// paragraph further down the same file. A note that has to be obeyed is not
/// a rule; this is the mechanism.
/// ⚠️IT IS THE COUNTER, NOT EVERY TILDE. The pattern was a bare `~(\d+)`
/// until 2026-09-08, and a test whose NAME contains one — 「a bare Row
/// overflowed at the ~100px a drop-zone preview shrinks to」 — was read as
/// a hundred skipped tests. The run it landed in reported 105 where the
/// truth was 5, which is the same failure mode this whole function exists
/// to prevent, pointing the other way: a gate that cries wolf is a gate
/// the next reader learns to wave through.
///
/// The counter is flutter's own progress line, `+<passed> ~<skipped>:`,
/// and once a test has failed `+<passed> ~<skipped> -<failed>:` — so that
/// is what this asks for.
///
/// 🚨THE SECOND SHAPE WAS MISSING until 2026-09-23. A run that failed once
/// stopped matching at that failure, and the count froze there: a
/// whole-suite gate that skipped 22 reported 「12 test(s) SKIPPED」 — every
/// skip after its one red went unsaid, which is this function's whole
/// failure mode once more.
int? lastSkipCount(String text) {
  int? found;
  for (final m in RegExp(r'\+\d+ ~(\d+)(?: -\d+)?:').allMatches(text)) {
    found = int.parse(m.group(1)!);
  }
  return found;
}

/// `flutter test` writes its counter and its verdict in English whatever
/// the machine's locale is, because they come from Dart. Anything cmd.exe
/// says does not — which is why this looks for the shape of a test result
/// rather than for the shape of an error.
final _testOutput = RegExp(r'\+\d+|All tests passed|Some tests failed');

/// Passed through to this terminal as it arrives rather than buffered: a
/// suite takes tens of minutes, and a tool that says nothing until it
/// finishes is a tool nobody trusts is still alive. Copied rather than
/// inherited so the same bytes can answer one question on the way past —
/// did any test actually run?
Future<_BatchResult> _flutterTest(List<String> files) async {
  // --no-pub because resolving again buys nothing between two runs of the
  // same checkout, and on a loaded machine every process launch is felt.
  final process = await Process.start(
    Platform.isWindows ? 'flutter.bat' : 'flutter',
    <String>['test', '--no-pub', ...files],
    runInShell: true,
  );
  var ranTests = false;
  var skipped = 0;
  final pumped = <Future<void>>[
    process.stdout.map((chunk) {
      // latin1 never throws on malformed bytes; a mojibake launch error
      // must not take the tool down with it.
      final text = latin1.decode(chunk);
      if (!ranTests && _testOutput.hasMatch(text)) {
        ranTests = true;
      }
      final skips = lastSkipCount(text);
      if (skips != null) skipped = skips;
      return chunk;
    }).forEach(stdout.add),
    process.stderr.forEach(stderr.add),
  ];
  final code = await process.exitCode;
  await Future.wait(pumped);
  return _BatchResult(code, ranTests, skipped);
}
