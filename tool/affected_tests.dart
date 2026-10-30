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
// ↩️The one thing CI does take from it is HOW a list of files is run
// (`--files-from`, [filesListed]) — never WHICH: that list comes from
// elsewhere, so no assumption of the graph's rides along with it.
//
// Where it refuses to guess, it runs everything. That is the only safe
// direction for a tool like this to be wrong in.
//
// 🗣️유저 2026-10-20 (tests-crowd-the-machine-Q8 「나눈다」): before a lane
// lands it runs the tests NEAR its change — no more than [kNearImports]
// imports away, what reads the changed paths as text, and every suite only
// for the test config file itself (Q11 「설정 파일 자신만」). Every landing
// since the last check is then run WIDE together, once, by `master_check`,
// which walks a red back to the landing that made it; a red it put on a
// landing this checkout carries holds no verdict back here.
//
// Usage:
//   bash tool/run.sh affected_tests            # the tests near the change
//   bash tool/run.sh affected_tests --wide     # every test that reaches it
//   bash tool/run.sh affected_tests --list     # print them, run nothing
//   bash tool/run.sh affected_tests --all      # the escape hatch
//   bash tool/run.sh affected_tests --base HEAD~3     # master when not given
//   bash tool/run.sh affected_tests test/x_test.dart  # and these files too
//   bash tool/run.sh affected_tests --concurrency 4   # fewer than its turn gives
//   bash tool/run.sh affected_tests --no-cache        # run the record's greens too
//   bash tool/run.sh affected_tests --reds-to <file>  # write the reds there
//   bash tool/run.sh affected_tests --first-in-line   # the wide check's own
//   bash tool/run.sh affected_tests --files-from parity.txt  # a given list
//   bash tool/run.sh affected_tests --files-from parity.txt --outside-the-line
//
// A file green on this machine with byte-for-byte the inputs it has now is
// not run again, and a red file is run once more: green the second time
// with what it reads unchanged, it is flaky — quarantined until anything it
// reads changes, and on the board (`test_results.dart`, 유저
// tests-crowd-the-machine-Q4).
//
// Exit code is flutter test's own, or 0 when nothing needed running.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'bash_executable.dart';
import 'import_graph.dart';
import 'master_check.dart';
import 'native_engine_provenance.dart';
import 'test_queue.dart';
import 'test_results.dart';
import 'test_seconds.dart';

/// Changing one of these means the graph cannot answer, so we do not ask it:
/// what every suite reads without naming it — the green record's own list
/// ([kEveryTestReads], [kEveryTestReadsUnder]) — and the analysis options.
///
/// Dependencies and toolchain change what every file compiles to; the native
/// sources (`packages/`) sit behind FFI where no import edge reaches them,
/// and the assets and shaders the pubspec bundles reach every suite the same
/// way; and `test/flutter_test_config.dart` is loaded by flutter_test before
/// every suite in the tree while nothing imports it — an edge the graph
/// cannot see because it does not exist in the source. ↩️Until 10-20 this
/// was a list of its own that left `assets/` and `shaders/` out, while the
/// green record already ran every suite again for them.
///
/// ↩️THE PLATFORM FOLDERS ARE NO LONGER HERE (유저 10-20,
/// tests-crowd-the-machine-Q6 「전부」). `android/ ios/ linux/ macos/
/// windows/` stood in this list from 08-13 because 「they decide what the
/// app links against」 — the app's, never a suite's: `flutter test` runs
/// `flutter_tester`, which loads none of them, and the engine the suites
/// load is the one [_engineCaveat] names. 🧪That day a lane that touched
/// only `windows/runner/` ran all 2,561 files — eighty minutes of five
/// suites, with eleven runs waiting behind it. A suite that reads a
/// platform file as text is still chosen, by [selectTests], like any scan.
const _runEverything = <String>[
  ...kEveryTestReads,
  ...kEveryTestReadsUnder,
  'analysis_options.yaml',
];

/// The tag [gcTagMarker] writes, as `dart_test.yaml` declares it.
const gcTag = 'gc';

/// The marker a file writes to say 「my assertion waits for the garbage
/// collector」 — see [partitionByTag].
const gcTagMarker = "@Tags(['$gcTag'])";

/// The tag [gpuTagMarker] writes, as `dart_test.yaml` declares it.
const gpuTag = 'gpu';

/// The marker a file writes to say 「I draw with Flutter GPU, so I need the
/// Impeller engine」 — see [partitionByTag].
const gpuTagMarker = "@Tags(['$gpuTag'])";

/// The tag [impellerTagMarker] writes, as `dart_test.yaml` declares it.
const impellerTag = 'impeller';

/// The marker a file writes to say 「I need the Impeller tester」 — see
/// [partitionByTag].
const impellerTagMarker = "@Tags(['$impellerTag'])";

/// Whether [source]'s `@Tags` lists [tag]. A file carries ONE such
/// annotation (test_core refuses a second), so a file with two of the tags
/// above lists both in it — `@Tags(['gc', 'gpu'])`, which neither marker
/// spells.
bool carriesTag(String source, String tag) =>
    RegExp("@Tags\\(\\[[^\\]]*'$tag'").hasMatch(source);

/// The batch a test file runs in, by the tag its library carries
/// ([kindOf]), and what that batch tells the engine.
///
/// ⚠️THE ORDER IS THE ANSWER for a file listing two of these tags: it goes
/// to the first. A file that needs an engine cannot run without its flags
/// at all, and Flutter GPU's flags include Impeller's; a batch of its own
/// keeps a collector pin out of the crowd as well as the pins' batch does.
enum BatchKind {
  /// [gpuTagMarker]: batches of their own, on Impeller with Flutter GPU.
  gpu(gpuTag, ['--enable-impeller', '--enable-flutter-gpu']),

  /// [impellerTagMarker]: batches of their own, on Impeller.
  impeller(impellerTag, ['--enable-impeller']),

  /// [gcTagMarker]: one batch of their own, after every other.
  collector(gcTag, []),

  /// No tag that moves it: cut into batches with the rest.
  crowd(null, []);

  const BatchKind(this.tag, this.engineFlags);

  /// The tag that puts a file here; null for the files no tag moves.
  final String? tag;

  /// What `flutter test` is told about the engine for this batch.
  final List<String> engineFlags;
}

/// The order a run goes in ([runInBatches]), and a list prints in: the
/// crowd first, the files on another engine next, the collector's pins
/// last and alone.
const kRunOrder = [
  BatchKind.crowd,
  BatchKind.gpu,
  BatchKind.impeller,
  BatchKind.collector,
];

/// The batch a file whose source is [source] runs in: the first kind, in
/// [BatchKind]'s order, whose tag it carries.
BatchKind kindOf(String source) => BatchKind.values.firstWhere(
  (kind) => kind.tag == null || carriesTag(source, kind.tag!),
);

/// Splits the run by the batch each file runs in ([kindOf]) — every kind
/// named, each in the order [files] gave.
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
/// 🖥️**A FILE THAT DRAWS WITH FLUTTER GPU CANNOT RUN ON SKIA**
/// (gpu-pins-run-in-a-batch-of-their-own, 2026-10-24). `flutter_gpu` is
/// Impeller's alone: a plain `flutter test` runs the Skia tester, which has
/// no GPU context to hand it, and the pin can only skip. With
/// [BatchKind.gpu]'s flags the tester draws through Vulkan — green on the
/// Surface Pro 11 the day the first such pin was written. The flags change
/// the engine for EVERY file in the command, so they cannot be put on the
/// crowd: its pins measure what Skia draws (CI's engine), and the canvas
/// suite under Impeller once came back 174 red (impeller-sweep-canvas-reds).
/// A pin that needs the Impeller TESTER but not Flutter GPU — a shader
/// filter Skia does not have — carries its own tag, [impellerTag], and runs
/// on `--enable-impeller` alone (브러시/렌더링, 10-24: one tag answering
/// 「does it draw with Flutter GPU」 and 「does it need Impeller」 would be
/// one flag answering two questions).
///
/// ⚠️It is a whole-FILE question because the tag is a library annotation,
/// so partitioning by file is exact — no `--exclude-tags` pass that could
/// come back 「no tests match」 and read as a failure to start.
Map<BatchKind, List<String>> partitionByTag(
  List<String> files,
  String Function(String path) read,
) {
  final split = {for (final kind in BatchKind.values) kind: <String>[]};
  for (final file in files) {
    split[kindOf(read(file))]!.add(file);
  }
  return split;
}

/// How many imports from a test a change may stand and still choose it
/// before a lane lands — the near run. 🗣️유저 2026-10-20,
/// tests-crowd-the-machine-Q8 「나눈다」: 「처음엔 두 단계 안 — 착지 뒤
/// 검사에서 놓친 빨강의 거리를 기록해 조정」. The wide run after landing
/// (`master_check`) asks every import and keeps how far each red it finds
/// stood (`near_misses.tsv`): this number is set by that record.
/// ↩️Two until 10-21 — 🗣️tests-crowd-the-machine-Q12 「1단계 — 바뀐 파일을
/// 직접 import 하는 테스트까지」, before that record had any: the 21 lanes
/// standing in the line that night chose 400 to 1,600 files each at two
/// steps, 6,126 machine-minutes together (ten hours of ten suites), and
/// 1,922 at one; the timeline's code is imported widely enough that a
/// second step reaches a thousand tests, the same thousand for every lane.
const kNearImports = 1;

/// How many imports from [kTestConfig] a change may stand and still be
/// every suite's in the near run: none — the config file alone, which
/// [forcesFullRun] already runs everything for. 🗣️유저 2026-10-20,
/// tests-crowd-the-machine-Q11 「설정 파일 자신만」. The config imports
/// `app_strings.dart` one step away, so a string changed made every suite
/// run at two steps: 🧪over that day's 120 landings two steps saved 20% of
/// the wide run's machine-hours, the config alone 32%. What the config
/// reaches is still every suite's in the wide run (`master_check`).
const kNearConfigImports = 0;

/// The files a list run names (`--files-from <file>`: one path a line, from
/// the repository root, as `tool/native_parity_tests.sh` prints them) — or
/// why there is nothing to run.
///
/// 🚨THE PARITY RUNS GO IN BATCHES TOO ([runInBatches]; parity-runs-crowd-
/// the-collector-pins, 2026-10-17). Five places run the native parity list —
/// `lane.sh native` and the TestFlight, Mac, Linux and Windows ARM64 builds —
/// and each ran it as ONE `xargs flutter test`, its collector pins in the very
/// crowd the plan keeps them out of: `tile_images_are_counted` lost its 64
/// bytes inside a parity batch (2026-09-11). They hand the list here instead,
/// so how a list is run is written once.
///
/// ⛔A list naming nothing is REFUSED, never run: to `flutter test` an empty
/// selection is the whole suite, and a list that came back empty would turn
/// a parity check into all of it. A path that is not there is refused too —
/// `flutter test` would stop on it after the crowd had run.
({List<String> files, String? refusal}) filesListed(
  String? text, {
  required bool Function(String path) exists,
}) {
  if (text == null) {
    return (files: const <String>[], refusal: 'the list is not there');
  }
  final files = [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  if (files.isEmpty) {
    return (
      files: const <String>[],
      refusal: 'the list names no file, and an empty run is the whole suite',
    );
  }
  final missing = [
    for (final file in files)
      if (!exists(file)) file,
  ];
  if (missing.isNotEmpty) {
    return (
      files: const <String>[],
      refusal: 'the list names ${missing.length} file(s) that are not there '
          '— ${missing.first}',
    );
  }
  return (files: files, refusal: null);
}

/// Whether a run asked with [args] takes its turn in the machine's line
/// (`test_queue.dart`) — or why it was asked wrongly.
///
/// 🗣️A LAND'S GATES TAKE NO PLACE IN IT. `tool/lane.sh` runs the native
/// parity list among the gates a landing stands behind, beside its analyze
/// and architecture tests, and those run at once, never in the line (유저
/// 10-08, a-sent-lane-is-gated-once-Q1 「착지 게이트는 이 넷에 세지 않는다」;
/// 10-18, tests-crowd-the-machine-Q2). A land waiting in the line would hold
/// the land's turn all the while, and every other lane's land behind it. So
/// the gates say `--outside-the-line` — ⛔for a list run only: any other run
/// is a session's, and stands in the line.
///
/// ⚙️NOR DOES A CI SHARD (ci-shards-crowd-the-collector-pins, 10-24): its
/// runner holds one job, so there is no line to share — and on Windows the
/// line waits for the room `flutter_room` measures, which a small runner
/// may never show. It runs its slice as a list, so it says the same.
///
/// A run that says `--first-in-line` stands at its head — the build's wide
/// check, which `master_check` asks for (유저 10-22, tests-crowd-the-machine-
/// Q18; `waitingInTurn` has why).
({bool inTheLine, bool first, String? refusal}) lineFor(List<String> args) {
  final first = args.contains('--first-in-line');
  if (!args.contains('--outside-the-line')) {
    return (inTheLine: true, first: first, refusal: null);
  }
  if (!args.contains('--files-from')) {
    return (
      inTheLine: true,
      first: first,
      refusal: "--outside-the-line is a land's gates' and a CI shard's, "
          'for a --files-from list',
    );
  }
  return (inTheLine: false, first: first, refusal: null);
}

/// What a change to [changed] — every changed file, Dart or not — can have
/// broken, out of [tests]: what reaches a changed file ([Reaches]) — by its
/// imports, however far away or no more than [within] of them, or by a path
/// it or anything it imports reads as text ([pathsReadAsText] has the
/// rounds those reads were missing from) — the green record's own question.
///
/// 🚨flutter_test loads [kTestConfig] before every suite, and all it
/// reaches with it — however far away or no more than [configWithin] of its
/// imports — so a change the config reaches is every suite's. Until 10-20
/// the selection asked each test alone: a change to the session sandbox the
/// config sets up chose only the few tests that import it — 15% of that
/// month's lib changes touched what the config reaches.
Set<String> selectTests({
  required Set<String> changed,
  required List<String> tests,
  required Map<String, Set<String>> imports,
  required String Function(String path) read,
  int? within,
  int? configWithin,
}) {
  final reaches = Reaches(imports, read, within: within);
  final everySuite = reachesAny(
    Reaches(imports, read, within: configWithin).of(kTestConfig),
    changed,
  );
  return {
    // A changed test runs because it changed, whatever it imports.
    ...changed.where((f) => f.startsWith('test/') && f.endsWith('_test.dart')),
    for (final test in tests)
      if (everySuite || reachesAny(reaches.of(test), changed)) test,
  };
}

Future<void> main(List<String> args) async {
  final listOnly = args.contains('--list');
  final runAll = args.contains('--all');
  final wide = args.contains('--wide');
  final within = wide ? null : kNearImports;
  final configWithin = wide ? null : kNearConfigImports;
  // ↩️`origin/master` until 10-20. Since PRs go up in bundles (08-31) the
  // local master runs days ahead of origin — 454 commits that day — and a
  // run given no base ran every landing since the last PR as its own. A
  // lane's change is what it holds over master (🗣️Q8 「착지 전엔 가까운
  // 테스트」); what landed is the wide check's (`master_check`).
  final base = _flagValue(args, '--base') ?? 'master';
  final named = [
    for (final arg in args)
      if (arg.endsWith('_test.dart')) arg.replaceAll('\\', '/'),
  ];
  final redsTo = _flagValue(args, '--reds-to');
  final listed = _flagValue(args, '--files-from');
  // Where the caller stands, before the run moves to the repository root.
  final list = listed == null ? null : File(listed).absolute;
  final asked = _flagValue(args, '--concurrency');
  final concurrency = asked == null ? null : int.tryParse(asked);
  if (asked != null && (concurrency == null || concurrency < 1)) {
    stderr.writeln('--concurrency takes a whole number of suites, 1 or more.');
    exit(2);
  }
  final useCache = !args.contains('--no-cache');
  final turn = lineFor(args);
  if (turn.refusal != null) {
    stderr.writeln('${turn.refusal}.');
    exit(2);
  }
  _atIdle();

  final root = _repoRoot();
  if (root == null) {
    stderr.writeln('not inside a git checkout.');
    exit(2);
  }
  Directory.current = root;

  Future<Never> run(
    List<String> files, [
    Map<String, Set<String>>? imports,
  ]) async => exit(
    await _runTests(
      files,
      listOnly: listOnly,
      concurrency: concurrency,
      cache: _openCache(imports),
      useCache: useCache,
      redsTo: redsTo,
      inTheLine: turn.inTheLine,
      firstInLine: turn.first,
    ),
  );

  if (list != null) {
    final given = filesListed(
      list.existsSync() ? list.readAsStringSync() : null,
      exists: (path) => File(path).existsSync(),
    );
    final refusal = given.refusal;
    if (refusal != null) {
      stderr.writeln('--files-from $listed: $refusal.');
      exit(2);
    }
    _report('${given.files.length} file(s) from $listed.');
    await run(given.files);
  }

  if (runAll) {
    _report('--all: running the whole suite.');
    await run(_wholeSuite());
  }

  final changed = _changedFiles(base);
  if (changed.isEmpty && named.isEmpty) {
    _report('nothing has changed against $base — nothing to run.');
    _sayReds(redsTo, const []);
    exit(0);
  }

  final blanket = changed
      .where((path) => forcesFullRun(path, near: !wide))
      .toList()
    ..sort();
  if (blanket.isNotEmpty) {
    _report('running everything: ${blanket.first} changed'
        '${blanket.length > 1 ? ' (and ${blanket.length - 1} more like it)' : ''}.');
    await run(_wholeSuite());
  }
  final engine = changed.where(changesTheEngine).toList()..sort();
  final parity = wide || engine.isEmpty ? const <String>[] : parityTests();
  if (parity == null) {
    _report('running everything: ${engine.first} changed and '
        'tool/native_parity_tests.sh chose no test that exercises the '
        'engine.');
    await run(_wholeSuite());
  }

  final imports = buildImportGraph(roots: kGraphRoots);
  final tests = _suitesIn(imports);

  final selected = {
    ...selectTests(
      changed: changed,
      tests: tests,
      imports: imports,
      read: (path) => File(path).readAsStringSync(),
      within: within,
      configWithin: configWithin,
    ),
    ...parity,
    ...named,
  };
  if (parity.isNotEmpty) {
    _report('${engine.first} is the engine\'s C — near, that is the '
        '${parity.length} test(s) that exercise the engine '
        '(tool/native_parity_tests.sh); every suite runs against it in the '
        'wide check after landing.');
  }

  final present = selected.where((f) => File(f).existsSync()).toList()..sort();
  if (present.isEmpty) {
    _report('no test reaches the ${changed.length} changed file(s).');
    _sayReds(redsTo, const []);
    exit(0);
  }

  _report('${present.length} of ${tests.length} test files reach the '
      '${changed.length} changed file(s)'
      '${within == null ? '' : ' within $within import(s) — --wide asks every one'}'
      '${named.isEmpty ? '' : ', with the ${named.length} named'}.');
  final known = _knownTimes();
  _report('longest first, by this machine\'s times '
      '(${present.where(known.containsKey).length} of ${present.length} '
      'files timed before).');
  await run(longestFirst(present, known), imports);
}

/// What `master_check` reads a run by: the files red in [batches] but those
/// [setAside] — flaky in this run, or quarantined — or null when a batch
/// that went [red] did not say what each of its files did.
List<String>? redsOf(
  Map<int, List<SuiteRun>> batches,
  Iterable<int> red,
  bool Function(String file) setAside,
) {
  final told = red.every((i) {
    final runs = batches[i] ?? const <SuiteRun>[];
    return runs.isNotEmpty && runs.every((run) => run.green != null);
  });
  if (!told) return null;
  return [
    for (final runs in batches.values)
      for (final run in runs)
        if (run.green == false && !setAside(run.path)) run.path,
  ]..sort();
}

/// Writes [reds] to the file [to] names, one a line — what `master_check`
/// reads a run's verdict from — or nothing when none is named.
void _sayReds(String? to, Iterable<String> reds) {
  if (to == null) return;
  File(to).writeAsStringSync([for (final red in reds) '$red\n'].join());
}

/// This machine's result records for this checkout ([ResultCache]), keyed
/// through [imports] — the whole graph from [kGraphRoots] when not given.
ResultCache? _openCache([Map<String, Set<String>>? imports]) {
  final cache = ResultCache.open(
    Directory.current.path,
    Platform.environment,
    imports ?? buildImportGraph(roots: kGraphRoots),
  );
  if (cache == null) {
    _report('no result record this time — the machine folder, git, Flutter '
        "or the engine's stamp could not be read — so every file runs.");
  }
  return cache;
}

/// The file [machineCacheFolder] keeps the times in.
File? _timesFile() {
  final folder = machineCacheFolder(Platform.environment);
  return folder == null ? null : File('$folder/test_times.tsv');
}

Map<String, int> _knownTimes() {
  try {
    final file = _timesFile();
    return file != null && file.existsSync()
        ? readTimes(file.readAsStringSync())
        : const {};
  } on FileSystemException {
    return const {};
  }
}

/// What a batch's [report] says of each file ([suiteRuns]), with its times
/// and greens laid over the machine's records ([updatePairs]).
List<SuiteRun> _recordBatch(File report, ResultCache? cache) {
  if (!report.existsSync()) return const [];
  final List<SuiteRun> runs;
  try {
    runs = suiteRuns(report.readAsStringSync(), root: Directory.current.path);
  } on FileSystemException catch (e) {
    _report('the report of this batch could not be read: ${e.message}');
    return const [];
  }
  final file = _timesFile();
  final measured = timesOf(runs);
  try {
    if (file != null && measured.isNotEmpty) {
      updatePairs(file, (known) => merged(timesIn(known), measured));
    }
  } on FileSystemException catch (e) {
    _report('what this batch said was not kept: ${e.message}');
  }
  _keep(cache, runs);
  return runs;
}

/// Lays [runs] over the green record of [cache] ([ResultCache.keep]).
void _keep(ResultCache? cache, List<SuiteRun> runs) {
  try {
    cache?.keep(runs);
  } on FileSystemException catch (e) {
    _report('what this batch said was not kept: ${e.message}');
  }
}

/// The key of what each test reads in this checkout as it is NOW — the
/// bytes and the imports measured again ([ResultCache.open]) — or null when
/// no key can be made.
String? Function(String file)? _keysNow() => ResultCache.open(
  Directory.current.path,
  Platform.environment,
  buildImportGraph(roots: kGraphRoots),
)?.keyFor;

String? _flagValue(List<String> args, String name) {
  final i = args.indexOf(name);
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}

void _report(String message) => stdout.writeln('[affected] $message');

/// 🗣️유저 2026-09-24 「PC 굳히지 말 것」: every suite this launches runs at
/// Idle, whoever launched the tool. `lane.sh` lowers its own shell before
/// its gates; a run started straight from a shell lowered nothing, and on
/// 2026-10-15 two of them at Normal starved the user's release build of
/// its AOT compile. Lowered here, the tool hands Idle to everything it
/// launches — Windows gives an Idle parent's class to its children.
void _atIdle() {
  if (!Platform.isWindows) {
    return;
  }
  try {
    Process.runSync('powershell.exe', idleArguments(pid));
  } on ProcessException {
    // No PowerShell to ask: the run goes on at the class it was given.
  }
}

/// What PowerShell is asked to run process [processId] at Idle with.
List<String> idleArguments(int processId) => [
  '-NoProfile',
  '-NonInteractive',
  '-Command',
  "(Get-Process -Id $processId).PriorityClass = 'Idle'",
];

Directory? _repoRoot() {
  final result = Process.runSync('git', ['rev-parse', '--show-toplevel']);
  if (result.exitCode != 0) return null;
  return Directory((result.stdout as String).trim());
}

/// Committed changes against the merge base, plus whatever is still in the
/// working tree — the edit-run loop is mostly the latter.
/// Whether this checkout holds the commit [sha] — a landing that
/// `master_check` named.
bool _carries(String sha) =>
    Process.runSync('git', ['merge-base', '--is-ancestor', sha, 'HEAD'])
        .exitCode ==
    0;

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

/// Whether a change to [path] is one the graph cannot answer
/// ([_runEverything]), so the whole suite runs — but in a [near] run, never
/// for the engine's own sources ([changesTheEngine]).
///
/// 🗣️유저 2026-10-21, tests-crowd-the-machine-Q14 「C 레인도 착지 전엔
/// 가까운 것만」: a lane that changed the C ran all 2,500 files before it
/// landed — two such lanes were 1,256 of the line's 4,000 waiting
/// machine-minutes that evening. Narrowing by the graph buys nothing (2,041
/// of 2,625 suites reach `lib/src/native/`), so a near run takes the tests
/// that exercise the engine instead ([parityTests]) — the list the land's
/// gate runs with the C tests — and the wide check after landing
/// (`master_check`) runs every suite against that C, as it does for Dart.
bool forcesFullRun(String path, {bool near = false}) =>
    !(near && changesTheEngine(path)) &&
    _runEverything.any(
      (prefix) =>
          prefix.endsWith('/') ? path.startsWith(prefix) : path == prefix,
    );

/// Whether [path] is one of the engine's sources — the C behind FFI that no
/// import edge reaches.
bool changesTheEngine(String path) => path.startsWith(kEngineSources);

/// Where the engine's sources live.
const kEngineSources = 'packages/';

/// The tests that exercise the engine: `tool/native_parity_tests.sh`'s
/// answer, asked rather than copied (the one answer — its header), or null
/// when it gives none.
List<String>? parityTests() {
  final result = Process.runSync(
    bashExecutable,
    ['tool/native_parity_tests.sh'],
  );
  if (result.exitCode != 0) return null;
  final files = const LineSplitter()
      .convert(result.stdout as String)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  return files.isEmpty ? null : files;
}

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

/// Every suite there is, named — what `--all` and a blanket file run.
List<String> _wholeSuite() =>
    _suitesIn(buildImportGraph(roots: const ['test']));


/// How many characters of arguments one invocation may carry.
///
/// `flutter` is a .bat, so on Windows the whole command line goes through
/// cmd.exe's ~8191-character buffer whatever launched it. A selection of
/// 214 files is about 9,800 characters, and the failure is not subtle —
/// "コマンド ラインが長すぎます", exit 1, no tests run. The CI shard action
/// carried `xargs -0 -s 6000` against this exact wall from the day it was
/// written (measured there: 182 paths, 8284 characters, died in 598ms; 91
/// paths, 4105 characters, fine) — a second copy of this rule until its
/// shards ran their slices through here (ci-shards-crowd-the-collector-
/// pins, 10-24). This tool shipped without it and was caught the first
/// time somebody changed a widely-imported file.
///
/// 6000 keeps 2k of daylight below the real ceiling. Elsewhere ARG_MAX is
/// megabytes and one batch is always enough.
const _argBudget = 6000;

/// Whether [batch] fits one invocation's budget — off Windows any batch
/// does. A file that is somehow longer than the whole budget still goes out
/// alone ([timedBatches] ends at one file a batch) rather than being dropped
/// — failing loudly beats running less than we said we would.
bool _fitsTheCommandLine(List<String> batch) =>
    !Platform.isWindows ||
    batch.fold(0, (length, file) => length + file.length + 1) <= _argBudget;

/// How long a batch should run at the suites the line gave it, in seconds
/// — what [nextBatch] cuts to.
///
/// 🗣️유저 10-20: 「계속 10줄 중 아까 낮처럼 2개쓴다거나 지금처럼 6개만쓴다거나
/// 이런거 안일어나게 하고싶어」. The line now hands a run what is left of its
/// share (`suitesToRun`), which may be two suites where it wanted five; a
/// batch cut to a fixed work would then hold those two for twenty minutes.
/// Cut to the suites it was given, every batch runs about this long however
/// many it got, and the run asks again — for more, once more stand free.
/// ⚖️Five minutes against the 5~15s a `flutter test` takes to start: the
/// line decides again at least that often, for a few percent.
/// ↩️It was forty machine-minutes a batch (`kBatchWork`, 유저 10-20 Q6),
/// cut before the run began.
const kBatchWall = 300;

/// The batch to run next out of [left] at [suites] suites: as much work as
/// they do in [kBatchWall], dealt the way every batch is ([timedBatches]) —
/// so it starts on heavy files and ends on light ones — and never past
/// [fits].
///
/// 🚨THE WHOLE SUITE IS CUT LIKE ANY SELECTION. An empty command is the
/// whole suite, so the whole suite once went out as one command with the
/// collector's pins in it ([partitionByTag]) — and the parked-transform
/// pin went red in that crowd a third time (2026-09-23, 「16 tiles, 16 still
/// alive」, green in its own batch). Since 유저 10-20 Q6 a whole suite names
/// its files ([_wholeSuite]), and ⛔no batch is ever empty.
///
/// ⚙️OUTSIDE THE LINE ([inTheLine] false) a batch is all of [left] that
/// fits: the wall is how long the line goes without deciding again, and
/// there no line decides. A CI shard of five hundred untimed files cut to
/// it at one suite would pay a `flutter test` start every thirty files.
List<String> nextBatch(
  List<String> left,
  Map<String, int> known, {
  required int suites,
  required bool inTheLine,
  bool Function(List<String> batch) fits = _fitsTheCommandLine,
}) => timedBatches(
  left,
  known,
  work: inTheLine ? suites * kBatchWall : workOf(left, known) + 1,
  fits: fits,
).first;

/// Runs [files] batch by batch ([partitionByTag]), kind by kind in
/// [kRunOrder]: each cut as it goes to the suites each batch is given
/// ([nextBatch]), but the pins that wait for the collector as one batch of
/// their own. [take] stands in the line for the files still to run and says
/// how many suites the next batch has; [run] runs the batch at them, on the
/// engine its [BatchKind] names.
Future<void> runInBatches(
  List<String> files, {
  required Map<String, int> known,
  required bool inTheLine,
  required String Function(String path) read,
  required Future<int> Function(List<String> left) take,
  required Future<void> Function(
    List<String> batch,
    int suites, {
    required BatchKind kind,
  })
  run,
}) async {
  final split = partitionByTag(files, read);
  for (final kind in kRunOrder) {
    var left = split[kind]!;
    if (kind == BatchKind.collector) {
      if (left.isNotEmpty) await run(left, await take(left), kind: kind);
      continue;
    }
    while (left.isNotEmpty) {
      final suites = await take(left);
      final batch = nextBatch(
        left,
        known,
        suites: suites,
        inTheLine: inTheLine,
      );
      await run(batch, suites, kind: kind);
      final ran = batch.toSet();
      left = [for (final file in left) if (!ran.contains(file)) file];
    }
  }
}

/// The console reporter every batch asks for, whatever machine it runs on.
///
/// 🚨★★★THE CONSOLE IS READ, SO ITS SHAPE IS NAMED. Three readers take the
/// batch's output as it passes — whether any test ran ([_testOutput]), how
/// many were skipped ([lastSkipCount]) and when one last finished
/// ([BatchSilence]) — and all three read the counter `+N ~N -N:`. Left
/// unnamed, package:test picks `expanded` here (a pipe, on Windows) but
/// `github` inside GitHub Actions, which prints `✅ <path>: <name>` and no
/// counter at all. 🧪2026-10-28, bundle PR #1485 (card
/// ci-silent-batch-cut-reads-no-counter): the first CI to run its shards
/// through this tool cut all three at exactly fifteen minutes — 25,643 log
/// lines and not one counter, so the silence watch never saw a test finish.
const kReporter = '--reporter=expanded';

/// What one batch hands `flutter test`: [files], and at most [concurrency]
/// suites at once when one is given.
///
/// --no-pub because resolving again buys nothing between two runs of the
/// same checkout, and on a loaded machine every process launch is felt.
///
/// 🗣️[concurrency] because the machine is someone's (유저 2026-09-24:
/// 「부하 좀 강도? 낮출수없나. pc가 너무느린데」): left out, `flutter test`
/// runs as many suites as there are cores, and a run of a thousand files
/// takes the whole machine for half an hour.
///
/// [report] is where the batch leaves a JSON report beside its console —
/// the times [longestFirst] orders the next run by. The console a session
/// reads is the same.
///
/// [kind] names the engine the batch runs on ([BatchKind.engineFlags]).
List<String> flutterTestArguments(
  List<String> files, {
  int? concurrency,
  String? report,
  required BatchKind kind,
}) => [
  'test',
  '--no-pub',
  kReporter,
  ...kind.engineFlags,
  if (concurrency != null) '--concurrency=$concurrency',
  if (report != null) '--file-reporter=json:$report',
  ...files,
];

Future<int> _runTests(
  List<String> files, {
  required bool listOnly,
  int? concurrency,
  ResultCache? cache,
  bool useCache = true,
  String? redsTo,
  bool inTheLine = true,
  bool firstInLine = false,
}) async {
  final selected = useCache && cache != null
      ? _withoutStillGreen(files, cache)
      : files;
  if (selected == null) {
    _report(listOnly
        ? 'nothing to run — every file was green with these inputs.'
        : 'PASSED (no batch — every file was green with these inputs, '
            'exit 0)');
    if (!listOnly) _sayReds(redsTo, const []);
    return 0;
  }
  // The collector-waiting pins go last and by themselves.
  final split = partitionByTag(selected, (path) => File(path).readAsStringSync());
  if (listOnly) {
    for (final kind in kRunOrder) {
      split[kind]!.forEach(stdout.writeln);
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

  for (final kind in kRunOrder) {
    final those = split[kind]!;
    final apart = switch (kind) {
      BatchKind.crowd => null,
      BatchKind.collector =>
        'pin(s) wait for the garbage collector ($gcTagMarker) and run in a '
            'batch of their own — in company they report a holder that has '
            'already let go.',
      BatchKind.gpu =>
        'file(s) draw with Flutter GPU ($gpuTagMarker) and run in batches '
            'of their own, with ${kind.engineFlags.join(' ')} — on Skia '
            'they can only skip.',
      BatchKind.impeller =>
        'file(s) need the Impeller tester ($impellerTagMarker) and run in '
            'batches of their own, with ${kind.engineFlags.join(' ')} — on '
            'Skia they can only skip.',
    };
    if (apart != null && those.isNotEmpty) _report('${those.length} $apart');
  }

  var skipped = 0;
  final exits = <int, int>{};
  final neverRan = <int>[];
  final runsOf = <int, List<SuiteRun>>{};
  final flaky = <String>{};
  final moved = <String>{};
  final unrun = <String>[];
  final reports = Directory.systemTemp.createTempSync('affected-times');
  // ②THE MACHINE'S ONE LINE (`test_queue.dart`, 유저 tests-crowd-the-
  // machine-Q1 · Q3 · Q6): this run keeps one place in it, and every batch
  // takes the suites the line gives it then, by the work still to do. A
  // land's gates take none ([lineFor], [outsideTheLine]).
  final known = _knownTimes();
  var launched = 0;
  Future<void> runBatches(Turn turn) async {
    // Runs every file of [files] in batches ([runInBatches]) and hands
    // [record] each batch's number, report and result.
    Future<void> runAll(
      List<String> files,
      void Function(int i, File report, _BatchResult result) record,
    ) => runInBatches(
      files,
      known: known,
      inTheLine: inTheLine,
      read: (path) => File(path).readAsStringSync(),
      take: (left) =>
          turn.take(files: filesNamed(left), work: workOf(left, known)),
      run: (batch, suites, {required kind}) async {
        final i = launched++;
        _report('batch ${i + 1}: ${batch.length} file(s) at $suites '
            'suite(s)${switch (kind) {
              BatchKind.crowd => '',
              BatchKind.collector => ' — the pins',
              BatchKind.gpu => ' — on Impeller with Flutter GPU',
              BatchKind.impeller => ' — on Impeller',
            }}');
        final report = File('${reports.path}/batch$i.json');
        try {
          final result = await _flutterTest(
            batch,
            concurrency: suites,
            report: report.path,
            kind: kind,
          );
          if (ranNowhere(
            exitCode: result.exitCode,
            noContext: result.noContext,
          )) {
            unrun.addAll(batch);
            _report('⚠️batch ${i + 1} DID NOT RUN — this machine\'s tester '
                'could not make the context ${kind.engineFlags.join(' ')} '
                'asks for ($kNoTesterContext). Its files are neither red '
                'nor green.');
          } else {
            record(i, report, result);
          }
        } finally {
          turn.putDown();
        }
      },
    );

    await runAll(selected, (i, report, result) {
      runsOf[i] = _recordBatch(report, cache);
      skipped += result.skipped;
      if (result.exitCode != 0) {
        exits[i] = result.exitCode;
        if (!result.ranTests) neverRan.add(i + 1);
      }
    });

    // 🗣️Q4 b: a red file runs once more with the same inputs; green the
    // second time, it is flaky.
    final reds = {
      for (final runs in runsOf.values)
        for (final run in runs)
          if (run.green == false) run.path,
    };
    if (reds.isEmpty) return;
    _report('${reds.length} red file(s) — running them once more, to tell a '
        'flaky one from a real red.');
    final again = <SuiteRun>[];
    await runAll(reds.toList()..sort(), (i, report, result) {
      again.addAll(_recordBatch(report, null));
    });
    // ⚠️「The same inputs」 is measured after the second run, not assumed
    // from the keys taken when this run began ([splitGreenAgain]): a
    // landing into this checkout can change them in between.
    final greenAgain = [
      for (final run in again)
        if (run.green == true && reds.contains(run.path)) run.path,
    ];
    final split = splitGreenAgain(
      greenAgain,
      before: cache?.keyFor,
      after: greenAgain.isEmpty ? null : _keysNow(),
    );
    flaky.addAll(split.flaky);
    moved.addAll(split.moved);
    _keep(cache, [
      for (final run in again)
        if (!split.moved.contains(run.path)) run,
    ]);
  }

  // ⚠️No pin reaches this one line, and its mutant lives (10-21): a pin
  // would run a whole list. Each hop beside it is pinned — the gates pass
  // the flag (lane.sh, scanned), [lineFor] answers it, and [outsideTheLine]
  // holds what it asked at once. `first` likewise: master_check asks it
  // ([kWideCheckStandsFirst]), [lineFor] answers it, the line reads it.
  if (inTheLine) {
    await standInLine(
      'affected_tests',
      runBatches,
      say: _report,
      asked: concurrency,
      first: firstInLine,
    );
  } else {
    await outsideTheLine(
      'affected_tests',
      runBatches,
      say: _report,
      asked: concurrency,
    );
  }
  try {
    reports.deleteSync(recursive: true);
  } on FileSystemException {
    // A report still held open is the system temp folder's to clear.
  }

  if (flaky.isNotEmpty) _quarantine(flaky.toList()..sort(), cache);
  if (moved.isNotEmpty) {
    _report('⚠️red, then green — but what they read changed while this run '
        'went on (a landing into this checkout?), so they are no flake and '
        'their red stands: ${(moved.toList()..sort()).join(', ')}. Run them '
        'again.');
  }
  final held = <String>{};
  final onMaster = MasterRecords.of(Platform.environment)?.reds ?? const {};
  final fromMaster = <String, Landing>{};
  bool forgiven(String file) {
    if (flaky.contains(file)) return true;
    if (cache?.isQuarantined(file) ?? false) {
      held.add(file);
      return true;
    }
    if (redOnMaster(file, onMaster, _carries) case final landing?) {
      fromMaster[file] = landing;
      return true;
    }
    return false;
  }

  // A batch that went red is forgiven only when the report said what every
  // file in it did, and every red one was flaky or is quarantined.
  final failed = [
    for (final MapEntry(key: i, value: _) in exits.entries)
      if (holdsVerdictBack(runsOf[i] ?? const [], forgiven)) i + 1,
  ]..sort();
  final worst = failed.isEmpty ? 0 : exits[failed.first - 1]!;
  if (held.isNotEmpty) {
    _report('⚠️quarantined, and red again — flaky before and unchanged '
        'since, so it holds no verdict back: ${(held.toList()..sort()).join(', ')}');
  }
  if (fromMaster.isNotEmpty) {
    _report('⚠️red on master — master_check put it on a landing this '
        "checkout carries, so it is not this change's and holds no verdict "
        'back: ${[
          for (final MapEntry(:key, :value) in fromMaster.entries)
            '$key (${value.name})',
        ].join(', ')}');
  }

  if (redsOf(
        runsOf,
        exits.keys,
        (file) =>
            flaky.contains(file) || (cache?.isQuarantined(file) ?? false),
      )
      case final reds?) {
    _sayReds(redsTo, reds);
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
    _report('PASSED (${runsOf.length} batch(es), exit 0)');
  } else {
    _report('FAILED — batch(es) ${failed.join(', ')} of ${runsOf.length}, '
        'exit $worst');
  }
  _reportSkips(skipped);
  if (unrun.isNotEmpty) {
    _report('⚠️${unrun.length} file(s) DID NOT RUN on this machine — its '
        'tester made no Impeller context for them ($kNoTesterContext). Not '
        'a pass: a machine whose tester makes one sees them. '
        '${unrun.join(', ')}');
  }
  if (engine != null) _report(engine);
  return worst;
}

/// [files] without those green on this machine with the inputs they have
/// now ([ResultCache.stillGreenAmong]), or null when none is left.
List<String>? _withoutStillGreen(List<String> files, ResultCache cache) {
  final green = cache.stillGreenAmong(files);
  if (green.isEmpty) return files;
  _report('${green.length} of ${files.length} file(s) were green on this '
      'machine with the inputs they have now — not run again (--no-cache '
      'runs them).');
  final left = [
    for (final file in files)
      if (!green.contains(file)) file,
  ];
  return left.isEmpty ? null : left;
}

/// Quarantines the [flaky] files on this machine and puts them on the
/// board — 🗣️Q4 b 「「불안정」으로 표시해 따로 모으고 보드에 올린다」.
void _quarantine(List<String> flaky, ResultCache? cache) {
  _report('⚠️FLAKY — red, then green with the same inputs: '
      '${flaky.join(', ')}. Quarantined on this machine until anything it '
      'reads changes: a red from it holds no verdict back.');
  try {
    cache?.quarantine(flaky);
  } on FileSystemException catch (e) {
    _report('the quarantine was not kept: ${e.message}');
  }
  final line = jsonEncode({
    'id': kFlakyCard,
    'note': '⚠️**불안정 — 같은 입력으로 빨강 → 초록**(affected_tests, 기계 '
        '`${Platform.localHostname}`): '
        '${flaky.map((file) => '`$file`').join(' · ')}. 그 파일이 읽는 것'
        '(시험 · import · 도우미 · 읽는 파일 · Flutter · 엔진)이 바뀔 '
        '때까지 이 기계에서 격리 — 빨강이 판정을 안 막는다.',
  });
  final board = Platform.environment['ANICEL_BOARD'];
  if (board == null || board.isEmpty) {
    _report('no board named here — record it with board_say: $line');
    return;
  }
  final lines = File('${Directory.systemTemp.path}/affected-flaky-$pid.jsonl')
    ..writeAsStringSync('$line\n');
  try {
    final said = Process.runSync(bashExecutable, [
      'tool/run.sh', 'board_say', board, lines.path, //
    ]);
    if (said.exitCode != 0) {
      _report('the board did not take it — record it with board_say: $line');
    }
  } finally {
    try {
      lines.deleteSync();
    } on FileSystemException {
      // The temp folder's to clear.
    }
  }
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
  const _BatchResult(
    this.exitCode,
    this.ranTests,
    this.skipped, {
    required this.noContext,
  });
  final int exitCode;
  final bool ranTests;

  /// How many tests the run SKIPPED. See [lastSkipCount].
  final int skipped;

  /// Whether the tester said [kNoTesterContext] — see [ranNowhere].
  final bool noContext;
}

/// What the tester says when it cannot make the Impeller context its batch
/// asked for (`shell/testing/tester_main.cc`, before any suite starts);
/// `flutter test` hands it on as a `Shell:` line, then every suite of the
/// batch fails to load.
const kNoTesterContext = 'Could not create tester context';

/// Hears a batch's output as it comes for [kNoTesterContext] — once said,
/// said for the batch, and a chunk may end inside the line.
class NoContextWatch {
  String _carried = '';
  bool _said = false;

  /// Whether the batch has said [kNoTesterContext] in anything heard yet.
  bool get said => _said;

  /// [text] came from the batch.
  void heard(String text) {
    final seen = _carried + text;
    _said = _said || seen.contains(kNoTesterContext);
    const keep = kNoTesterContext.length - 1;
    _carried = seen.length > keep ? seen.substring(seen.length - keep) : seen;
  }
}

/// Whether a batch that exited [exitCode] having said [kNoTesterContext]
/// ([noContext]) is one this machine could not run at all.
///
/// 🖥️gpu-pins-run-in-a-batch-of-their-own (관제, 10-24): 「a runner with
/// no context says so, with a reason」 — its files are neither red nor
/// green, and the run says so by name. The same answer on every machine:
/// CI's runners were the ones nobody had measured (the tester links
/// SwiftShader's Vulkan, so they may have one), and a desk machine that
/// has none is told the same way. ⚠️If the engine ever words it otherwise
/// the batch comes back red, never green.
bool ranNowhere({required int exitCode, required bool noContext}) =>
    exitCode != 0 && noContext;

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

/// How many tests `flutter test` has finished by the last counter in
/// [text] — passed, skipped and failed together — or null if it shows none.
/// The same counter [lastSkipCount] reads its tilde from; this asks only
/// whether it moved.
int? finishedByCounter(String text) {
  int? found;
  for (final m in RegExp(
    r'\+(\d+)(?: ~(\d+))?(?: -(\d+))?:',
  ).allMatches(text)) {
    found = [1, 2, 3].fold<int>(
      0,
      (sum, group) => sum + int.parse(m.group(group) ?? '0'),
    );
  }
  return found;
}

/// How long a batch may finish no test before it is cut.
///
/// 🗣️유저 2026-10-21, tests-crowd-the-machine-Q17 「15분 동안 끝나는 테스트가
/// 없으면 배치를 끊는다」: that night two lanes' batches stood on one test
/// that never ended — the old `a_flip_reaches_past_the_end_test` walk, on a
/// tree whose frame key stepped nothing — and one of them held nine of the
/// line's eighteen suites for seven hours. A loop that never yields is past
/// any limit of the test's own. ⚖️Fifteen minutes, as measured over 364
/// reports and 120,679 tests: the longest test took 351 s, the longest a
/// batch went between two tests finishing was 164 s, and the slowest first
/// test of a batch finished 192 s after it began.
const kSilentBatch = Duration(minutes: 15);

/// How often a batch's silence is looked at.
const kLookForSilence = Duration(seconds: 30);

/// When one batch last finished a test, as its output says ([heard]) — so
/// one that has finished none for [kSilentBatch] can be told ([isPast]).
/// The batch's start counts as its first finish.
class BatchSilence {
  BatchSilence(this._since);

  DateTime _since;
  int _finished = -1;

  /// [text] came from the batch at [now].
  void heard(String text, DateTime now) {
    final finished = finishedByCounter(text);
    if (finished != null && finished > _finished) {
      _finished = finished;
      _since = now;
    }
  }

  /// Whether no test has finished for [silence] by [now].
  bool isPast(Duration silence, DateTime now) =>
      now.difference(_since) >= silence;
}

/// The tests [report] — a `json` file report — says started and never
/// finished, each as `<test file>: <test name>`; a suite still loading is
/// not one.
List<String> stillRunning(String report) {
  final paths = <int, String>{};
  final open = <int, ({int suite, String name})>{};
  for (final line in const LineSplitter().convert(report)) {
    final Object? event;
    try {
      event = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (event is! Map<String, dynamic>) continue;
    switch (event['type']) {
      case 'suite':
        final suite = event['suite'] as Map<String, dynamic>;
        paths[suite['id'] as int] = '${suite['path']}'.replaceAll('\\', '/');
      case 'testStart':
        final test = event['test'] as Map<String, dynamic>;
        final name = test['name'] as String;
        if (!name.startsWith('loading ')) {
          open[test['id'] as int] = (suite: test['suiteID'] as int, name: name);
        }
      case 'testDone':
        open.remove(event['testID']);
    }
  }
  return [
    for (final test in open.values)
      '${paths[test.suite] ?? '?'}: ${test.name}',
  ];
}

/// Ends the process [pid] and every process under it: `flutter test` runs
/// its testers two and three processes down, and ending the shell alone
/// leaves them holding the machine. ⚠️Off Windows only the shell's own
/// children go with it.
void _cutTree(int pid) {
  if (Platform.isWindows) {
    Process.runSync('taskkill', ['/PID', '$pid', '/T', '/F']);
  } else {
    Process.runSync('pkill', ['-KILL', '-P', '$pid']);
    Process.killPid(pid, ProcessSignal.sigkill);
  }
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
Future<_BatchResult> _flutterTest(
  List<String> files, {
  required int? concurrency,
  required String report,
  required BatchKind kind,
}) async {
  final process = await Process.start(
    Platform.isWindows ? 'flutter.bat' : 'flutter',
    flutterTestArguments(
      files,
      concurrency: concurrency,
      report: report,
      kind: kind,
    ),
    runInShell: true,
  );
  var ranTests = false;
  var skipped = 0;
  final context = NoContextWatch();
  final silence = BatchSilence(DateTime.now());
  var cut = false;
  final look = Timer.periodic(kLookForSilence, (_) {
    if (cut || !silence.isPast(kSilentBatch, DateTime.now())) return;
    cut = true;
    _cutTree(process.pid);
  });
  final pumped = <Future<void>>[
    process.stdout.map((chunk) {
      // latin1 never throws on malformed bytes; a mojibake launch error
      // must not take the tool down with it.
      final text = latin1.decode(chunk);
      if (!ranTests && _testOutput.hasMatch(text)) {
        ranTests = true;
      }
      context.heard(text);
      final skips = lastSkipCount(text);
      if (skips != null) skipped = skips;
      silence.heard(text, DateTime.now());
      return chunk;
    }).forEach(stdout.add),
    process.stderr.forEach(stderr.add),
  ];
  final code = await process.exitCode;
  look.cancel();
  await Future.wait(pumped);
  if (cut) {
    var open = const <String>[];
    try {
      open = stillRunning(File(report).readAsStringSync());
    } on FileSystemException {
      // No report to name them by; the cut is said all the same.
    }
    final named = open.isEmpty ? '(none named)' : open.join(' | ');
    _report('🚨 no test finished for ${kSilentBatch.inMinutes} min — cut the '
        'batch, red. Still running: $named');
  }
  return _BatchResult(
    cut && code == 0 ? 1 : code,
    ranTests,
    skipped,
    noContext: context.said,
  );
}
