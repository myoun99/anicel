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

  final imports = _importGraph();
  // The graph covers everything under test/ — helpers, fixtures and
  // flutter_test_config.dart included, because tests reach their changed
  // dependencies through those. Only files flutter test will actually run
  // as a suite may be handed back, though: passing it the config would ask
  // it to run a file that defines no tests.
  final tests = imports.keys
      .where((f) => f.startsWith('test/') && f.endsWith('_test.dart'))
      .toList()
    ..sort();

  final changedDart = changed.where((f) => f.endsWith('.dart')).toSet();
  final selected = <String>{};

  // A changed test runs because it changed, whatever it imports.
  selected.addAll(
    changedDart.where((f) => f.startsWith('test/') && f.endsWith('_test.dart')),
  );

  // Everything that can reach a changed file, however far away.
  for (final test in tests) {
    if (_closure(test, imports).any(changedDart.contains)) selected.add(test);
  }

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

/// file -> the repo-relative Dart files it imports directly.
Map<String, Set<String>> _importGraph() {
  final graph = <String, Set<String>>{};
  for (final dir in ['lib', 'test']) {
    final directory = Directory(dir);
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      graph[path] = _importsOf(path, entity.readAsStringSync());
    }
  }
  return graph;
}

final _directive = RegExp(
  '''^\\s*(?:import|export|part)\\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// A few tests read a lib file off disk instead of importing it — they check
/// its source text rather than its behaviour. There is no import edge to
/// follow, but there is still a dependency, and the file they name is right
/// there in the string. Treating that as an edge is exact: none of them
/// scans a directory, they all name one file.
final _sourceReference = RegExp('''['"](lib/[A-Za-z0-9_/.\\-]*\\.dart)['"]''');

Set<String> _importsOf(String from, String source) {
  final out = <String>{};
  for (final match in _sourceReference.allMatches(source)) {
    out.add(match.group(1)!);
  }
  for (final match in _directive.allMatches(source)) {
    final target = match.group(1)!;
    if (target.startsWith('dart:')) continue;
    if (target.startsWith('package:anicel/')) {
      out.add('lib/${target.substring('package:anicel/'.length)}');
    } else if (target.startsWith('package:')) {
      continue; // third-party: not ours to track
    } else {
      out.add(_normalise('${_dirOf(from)}/$target'));
    }
  }
  return out;
}

String _dirOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '.' : path.substring(0, i);
}

String _normalise(String path) {
  final parts = <String>[];
  for (final part in path.split('/')) {
    if (part == '.' || part.isEmpty) continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  return parts.join('/');
}

Set<String> _closure(String start, Map<String, Set<String>> graph) {
  final seen = <String>{};
  final queue = <String>[start];
  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    for (final next in graph[current] ?? const <String>{}) {
      if (seen.add(next)) queue.add(next);
    }
  }
  return seen;
}


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
  if (listOnly) {
    if (files.isEmpty) {
      stdout.writeln('(the whole suite)');
    } else {
      files.forEach(stdout.writeln);
    }
    return 0;
  }

  final batches = files.isEmpty ? [<String>[]] : _batches(files);
  if (batches.length > 1) {
    _report('${files.length} files exceed the command-line budget: '
        'running them in ${batches.length} batches. Each batch pays the '
        'resident compiler\'s cold start again.');
  }

  var worst = 0;
  final failed = <int>[];
  final neverRan = <int>[];
  for (var i = 0; i < batches.length; i++) {
    if (batches.length > 1) _report('batch ${i + 1} of ${batches.length}');
    final result = await _flutterTest(batches[i]);
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
  return worst;
}

class _BatchResult {
  const _BatchResult(this.exitCode, this.ranTests);
  final int exitCode;
  final bool ranTests;
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
  final pumped = <Future<void>>[
    process.stdout.map((chunk) {
      // latin1 never throws on malformed bytes; a mojibake launch error
      // must not take the tool down with it.
      if (!ranTests && _testOutput.hasMatch(latin1.decode(chunk))) {
        ranTests = true;
      }
      return chunk;
    }).forEach(stdout.add),
    process.stderr.forEach(stderr.add),
  ];
  final code = await process.exitCode;
  await Future.wait(pumped);
  return _BatchResult(code, ranTests);
}
