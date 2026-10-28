// WHAT A TEST FILE WAS GREEN WITH ON THIS MACHINE — so a run with the same
// inputs does not run it again — and the files that went red and then
// green with the same inputs, which hold no verdict back until they change.
//
// 🗣️유저 2026-10-19, tests-crowd-the-machine-Q4 「결과 캐시 + 불안정 테스트
// 격리」. a: 「테스트 파일 하나의 「입력」 — 그 파일과 그것이 import 하는 모든
// 파일의 내용, 텍스트로 읽는 경로(affected_tests 가 이미 고르는 그 경로),
// pubspec.lock, Flutter 버전, 네이티브 엔진 도장 — 이 이 기계에서 이미
// 초록이었던 것과 바이트까지 같으면 다시 안 돌리고 「캐시 초록」으로 보고한다.
// 하나라도 다르면 돈다」, with 「캐시를 안 쓰고 다 돌기」 스위치. b: 「같은
// 입력으로 한 번 빨갛고 다시 돌려 초록인 테스트를 「불안정」으로 표시해 따로
// 모으고 보드에 올린다」 — at the cost 「격리된 테스트는 고칠 때까지 게이트를
// 안 막으니 그 사이 진짜 버그를 놓칠 수 있다」.
//
// WHERE: [machineCacheFolder], beside the times — per machine, shared by
// every worktree on it, so a lane whose files are byte for byte what
// another lane already ran green does not run them again. ⛔CI keeps none
// of this and runs everything; so does a run with --no-cache.
//
// ⚠️WHAT THE KEY CANNOT SEE: a file a test reads by a path assembled behind
// a variable — the same blind spot the selection has (CLAUDE.md's 머지
// 게이트) — and anything outside the checkout but Flutter and the engine.
// A green that should have been red there is CI's to catch.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'import_graph.dart';
import 'native_engine_provenance.dart';
import 'test_seconds.dart';

/// Raised when what goes into a key changes shape, so every green kept
/// before it is run again.
const kResultsVersion = 1;

/// What every test reads without naming it: the package and its lock, the
/// test configuration, and every test's own `flutter_test_config.dart`
/// (whose imports [inputsOf] follows like a test's).
const kEveryTestReads = [
  'pubspec.yaml',
  'pubspec.lock',
  'dart_test.yaml',
  kTestConfig,
];

/// Folders every test may read without naming them: the assets and shaders
/// the pubspec bundles into every test, and the native package the engine
/// is built from.
const kEveryTestReadsUnder = ['assets/', 'shaders/', 'packages/'];

const kTestConfig = 'test/flutter_test_config.dart';

/// The board card the flaky files are put on.
const kFlakyCard = 'flaky-tests';

/// The records in [machineCacheFolder]: the green files and the flaky files,
/// each by the key of what it read ([ResultCache.keyFor]).
File? greenRecord(Map<String, String> environment) =>
    _record(environment, 'test_greens.tsv');

File? flakyRecord(Map<String, String> environment) =>
    _record(environment, 'test_flaky.tsv');

File? _record(Map<String, String> environment, String name) {
  final folder = machineCacheFolder(environment);
  return folder == null ? null : File('$folder/$name');
}

/// The checkout files a test file's result can depend on, each test asked
/// once ([of]).
class Inputs {
  Inputs({
    required this.imports,
    required this.files,
    required this.read,
  });

  final Map<String, Set<String>> imports;

  /// Every file in the checkout, by its path with `/`.
  final Iterable<String> files;
  final String Function(String path) read;

  late final _reaches = Reaches(imports, read);
  final _under = <String, List<String>>{};

  /// What every test reads ([kEveryTestReads], [kEveryTestReadsUnder]) —
  /// keyed once for the whole run, not once a test.
  late final Set<String> everyTest = {
    ...kEveryTestReads,
    for (final folder in kEveryTestReadsUnder) ..._filesUnder(folder),
    ...of(kTestConfig),
  };

  /// The files of [test]'s [Reach], and every file under a path it reads.
  Set<String> of(String test) {
    final reach = _reaches.of(test);
    return {
      ...reach.files,
      for (final prefix in reach.prefixes) ..._filesUnder(prefix),
    };
  }

  List<String> _filesUnder(String prefix) => _under.putIfAbsent(
    prefix,
    () => [for (final file in files) if (file.startsWith(prefix)) file],
  );
}

/// One id for [inputs] as they are now ([ids] — a file missing from them
/// is gone, and says so) together with what lies outside the checkout
/// ([outside]): a test file the green record holds under this id was green
/// with exactly these bytes.
///
/// 64-bit FNV-1a over the sorted list: a record of a few thousand files,
/// where two inputs meeting by chance is not the risk worth a package.
String keyOf(
  Iterable<String> inputs,
  Map<String, String> ids, {
  required String outside,
}) {
  var hash = 0xcbf29ce484222325;
  void add(String text) {
    for (final unit in utf8.encode(text)) {
      hash ^= unit;
      hash *= 0x100000001b3;
    }
  }

  add('v$kResultsVersion\n$outside\n');
  for (final path in inputs.toList()..sort()) {
    add('$path\u0000${ids[path] ?? 'gone'}\n');
  }
  String half(int bits) => bits.toRadixString(16).padLeft(8, '0');
  return half((hash >> 32) & 0xffffffff) + half(hash & 0xffffffff);
}

/// What lies outside the checkout that every result depends on — Flutter
/// as `flutter.version.json` describes it, and the engine's stamp — or
/// null when either cannot be read. ⛔Then nothing is taken from the
/// record: a key that cannot see Flutter change would keep its greens
/// across an upgrade.
String? outsideInputs(String root, Map<String, String> environment) {
  final flutter = _flutterVersion(environment);
  final engine = engineStampOf(root);
  return flutter == null || engine == null
      ? null
      : 'flutter $flutter\nengine $engine';
}

String? _flutterVersion(Map<String, String> environment) {
  final roots = [
    ?environment['FLUTTER_ROOT'],
    for (final folder in (environment['PATH'] ?? environment['Path'] ?? '')
        .split(Platform.isWindows ? ';' : ':'))
      if (folder.isNotEmpty &&
          File('$folder/flutter${Platform.isWindows ? '.bat' : ''}')
              .existsSync())
        Directory(folder).parent.path,
  ];
  for (final root in roots) {
    final version = File('$root/bin/cache/flutter.version.json');
    try {
      final about = jsonDecode(version.readAsStringSync());
      if (about is Map &&
          about['frameworkRevision'] is String &&
          about['engineRevision'] is String) {
        return '${about['frameworkRevision']} ${about['engineRevision']}';
      }
    } on Object {
      continue;
    }
  }
  return null;
}

/// Every file a test can read in the checkout at [root] ([canBeAnInput]),
/// by its path with `/`, to an id of its bytes as they are now — git's
/// blob id, taken from the index for a file the work tree has not changed
/// and hashed for one it has or that git does not track. Null when git
/// cannot say.
Map<String, String>? contentIds(
  String root, {
  ProcessResult Function(List<String> args)? git,
  bool Function(String path)? exists,
}) {
  git ??= (args) =>
      Process.runSync('git', ['-C', root, ...args], stdoutEncoding: utf8);
  exists ??= (path) => File('$root/$path').existsSync();
  final staged = git(['ls-files', '--stage', '-z']);
  final changed = git([
    'ls-files', '--modified', '--others', '--exclude-standard', '-z', //
  ]);
  if (staged.exitCode != 0 || changed.exitCode != 0) return null;
  final ids = stagedIds(staged.stdout as String)
    ..removeWhere((path, _) => !canBeAnInput(path));
  final present = <String>[];
  for (final path in nulSeparated(changed.stdout as String)) {
    ids.remove(path);
    if (canBeAnInput(path) && exists(path)) {
      present.add(path);
    }
  }
  // In bites well under Windows' command line, which git's own exe gets.
  for (var start = 0; start < present.length; start += 200) {
    final bite = present.sublist(start, math.min(start + 200, present.length));
    final hashed = git(['hash-object', '--', ...bite]);
    if (hashed.exitCode != 0) return null;
    final lines = const LineSplitter().convert(hashed.stdout as String);
    if (lines.length != bite.length) return null;
    for (var i = 0; i < bite.length; i++) {
      ids[bite[i]] = lines[i];
    }
  }
  return ids;
}

/// Whether a test can read [path] at all: under the roots a text read can
/// name ([pathsReadAsText]) or every test reads. Untracked folders a user
/// keeps in the checkout are never hashed.
bool canBeAnInput(String path) =>
    kEveryTestReads.contains(path) ||
    [
      for (final root in kTextRoots) '$root/',
      ...kEveryTestReadsUnder,
    ].any(path.startsWith);

/// `git ls-files --stage -z`: `<mode> <id> <stage>\t<path>` per entry.
Map<String, String> stagedIds(String output) => {
  for (final entry in nulSeparated(output))
    if (entry.split('\t') case [final head, final path]
        when head.split(' ').length == 3)
      path: head.split(' ')[1],
};

List<String> nulSeparated(String output) => [
  for (final part in output.split('\u0000'))
    if (part.isNotEmpty) part,
];

/// The test files among [files] the [greens] record holds under the key
/// [keys] gives them now.
Set<String> stillGreen(
  Iterable<String> files,
  Map<String, String> greens,
  String? Function(String file) keys,
) => {
  for (final file in files)
    if (greens[file] case final kept? when kept == keys(file)) file,
};

/// The green record after a run: every file [runs] says was green kept
/// under its key now, and every one it says was red dropped.
Map<String, String> greensAfter(
  Map<String, String> greens,
  List<SuiteRun> runs,
  String? Function(String file) keys,
) {
  final after = {...greens};
  for (final run in runs) {
    final key = keys(run.path);
    if (run.green == true && key != null) {
      after[run.path] = key;
    } else if (run.green == false) {
      after.remove(run.path);
    }
  }
  return after;
}

/// Whether a batch that went red holds the verdict back: unless its report
/// said what every file in it did ([runs]) and every red one is [forgiven]
/// — flaky in this run, or quarantined.
bool holdsVerdictBack(
  List<SuiteRun> runs,
  bool Function(String file) forgiven,
) {
  if (runs.isEmpty || runs.any((run) => run.green == null)) return true;
  final reds = [
    for (final run in runs)
      if (run.green == false) run.path,
  ];
  return reds.isEmpty || !reds.every(forgiven);
}

/// Whether [file] is quarantined in the [flaky] record: kept there under
/// the key of everything it reads ([keys]), and none of that changed since
/// — 🗣️「고칠 때까지」, and a fix to a flaky test is a change to something
/// it reads.
///
/// ↩️It was the file's own id (card a-fixed-red-is-quarantined-as-flaky,
/// 10-28). A fix lands in a helper or in the code under test as often as in
/// the test, so a file once taken for flaky kept every red it went on to
/// have from holding a verdict back, whatever changed beneath it — and the
/// master_check reads the same record.
bool quarantined(
  String file,
  Map<String, String> flaky,
  String? Function(String file) keys,
) => flaky[file] != null && flaky[file] == keys(file);

/// [greenAgain] — files red in a run and green when run once more — told
/// apart by whether what each reads was the same when the run began
/// ([before]) and after the second run ([after]): the same, it is flaky;
/// changed, or a key either side cannot give, its red stands.
///
/// 🗣️Q4 b is 「같은 입력으로 한 번 빨갛고 다시 돌려 초록인 테스트」 — the same
/// inputs, measured, not assumed. 🧪2026-10-28 (card
/// a-fixed-red-is-quarantined-as-flaky): a landing fixed a helper in the
/// checkout while affected_tests ran there, the two reds it fixed went
/// green on the second run, and both were quarantined as flaky — the keys
/// had been taken when the run began and nothing measured them again.
({Set<String> flaky, Set<String> moved}) splitGreenAgain(
  Iterable<String> greenAgain, {
  required String? Function(String file)? before,
  required String? Function(String file)? after,
}) {
  final flaky = <String>{};
  final moved = <String>{};
  for (final file in greenAgain) {
    final was = before?.call(file);
    final same = was != null && was == after?.call(file);
    (same ? flaky : moved).add(file);
  }
  return (flaky: flaky, moved: moved);
}

/// This machine's records for the checkout at [root], keyed as the
/// checkout is now.
class ResultCache {
  ResultCache._(this.greens, this.flaky, this.ids, this.inputs, this._shared);

  /// The cache for the checkout at [root] whose Dart files import each
  /// other as [imports] — or null when no key can be made: no machine
  /// folder, git that cannot say, or Flutter or the engine unread.
  static ResultCache? open(
    String root,
    Map<String, String> environment,
    Map<String, Set<String>> imports,
  ) {
    final greens = greenRecord(environment);
    final flaky = flakyRecord(environment);
    final outside = outsideInputs(root, environment);
    if (greens == null || flaky == null || outside == null) return null;
    final ids = contentIds(root);
    if (ids == null) return null;
    final inputs = Inputs(
      imports: imports,
      files: ids.keys,
      read: (path) => File('$root/$path').readAsStringSync(),
    );
    final every = keyOf(inputs.everyTest, ids, outside: '');
    return ResultCache._(greens, flaky, ids, inputs, '$outside\n$every');
  }

  final File greens;
  final File flaky;
  final Map<String, String> ids;
  final Inputs inputs;
  final String _shared;
  final _keys = <String, String>{};

  String keyFor(String test) => _keys.putIfAbsent(
    test,
    () => keyOf(inputs.of(test), ids, outside: _shared),
  );

  Map<String, String> _read(File record) {
    try {
      return record.existsSync()
          ? readPairs(record.readAsStringSync())
          : const {};
    } on FileSystemException {
      return const {};
    }
  }

  /// The [files] green on this machine with the inputs they have now.
  Set<String> stillGreenAmong(Iterable<String> files) =>
      stillGreen(files, _read(greens), keyFor);

  /// Lays what [runs] say over the green record ([greensAfter]).
  void keep(List<SuiteRun> runs) =>
      updatePairs(greens, (known) => greensAfter(known, runs, keyFor));

  bool isQuarantined(String file) => quarantined(file, _read(flaky), keyFor);

  /// Quarantines [files] under the key of what they read now.
  void quarantine(Iterable<String> files) => updatePairs(flaky, (known) => {
    ...known,
    for (final file in files) file: keyFor(file),
  });
}
