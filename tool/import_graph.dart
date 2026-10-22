// What does this file depend on? One answer, in one place.
//
// 🚨★★★THE EDGE LAW LIVES HERE AND NOWHERE ELSE.
//
// This started as `tool/affected_tests.dart`'s private graph — the one the
// merge gate already trusts to decide which tests a change can have broken.
// `tool/code_map.dart` then needed the same question answered and grew its
// own version, written to "the same shape". Two spellings of one law is
// exactly the split this repo bans: they agree on the day they are written
// and nothing tells you when they stop. So the law moved here and both read
// it. ⛔Do not answer 「what does this import」 anywhere else.
//
// The behaviour is `affected_tests`', unchanged, because that is the one that
// has been in the gate. Anything the other version did differently was the
// copy being wrong, not a second opinion worth keeping.
import 'dart:io';

/// A directive: `import`, `export` or `part`.
final _directive = RegExp(
  '''^\\s*(?:import|export|part)\\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// A `lib/…` path written as a STRING rather than imported.
///
/// A few tests read a lib file off disk instead of importing it — they check
/// its source text rather than its behaviour. There is no import edge to
/// follow, but there is still a dependency, and the file they name is right
/// there in the string.
///
/// ⚠️CORRECTED 2026-09-01. This used to claim 「none of them scans a
/// directory, they all name one file」, and that stopped being true: the
/// contract tests under `test/architecture/` walk `Directory('lib')` whole
/// and name nothing. Such a walk is no edge of this graph — there is no file
/// named for it to find — and since 2026-09-23 the selection reaches it
/// another way ([pathsReadAsText]). The heuristic below is still exact for
/// the tests that DO name a file.
final _sourceReference = RegExp('''['"](lib/[A-Za-z0-9_/.\\-]*\\.dart)['"]''');

/// Every path under a root a test reads ([kTextRoots]) that [source]
/// spells as a string: a directory a scan walks (`'lib'`, `'test'`,
/// `'lib/src/ui'`, the static head of `'lib/src/$layer'`) or a file it reads
/// (`'tool/lane.sh'`, a fixture). What is there is read as TEXT, so a change
/// under it is a change to what the test reads.
///
/// 🚨THE GAP IT CLOSES (2026-09-23). A contract test that walks
/// `Directory('lib')` has no import edge to anything it reads, so the
/// selection could never pick it, and CLAUDE.md told the reader to run such
/// tests by hand — `test/architecture/` whole, which the landing does. The
/// frame-axis law lives in `test/ui/canvas/` instead: F-28 landed a second
/// reader of `framesRunVertically`, nothing selected the one test that
/// forbids it, and master stayed red until an unrelated change ran it.
///
/// 🚨AND THE SAME GAP ONE ROOT OVER (2026-09-24). It read `lib` alone: a test
/// that spawned `attrib` went green through a 1,100-file selection, because
/// `tests_do_not_race_the_code_test` walks `dartFilesUnder('test')` and a
/// changed TEST file never selected it — the landing's gate caught it
/// instead. A file read by name went unseen the same way whatever its root:
/// the test reading `tool/lane.sh` never ran for a change to the script.
/// One law now — any root, a directory or a file, any extension.
///
/// 🚨AND THE PLATFORM FOLDERS (2026-10-20). The roots were `lib`, `test`
/// and `tool` while any change under `windows/` and the rest ran the whole
/// suite; when that blanket went (유저 tests-crowd-the-machine-Q6), the
/// tests that read `windows/runner/flutter_window.cpp` and the like would
/// have gone unselected for the very change they read.
///
/// ⚠️A PREFIX, NOT A PARSE. Any literal that starts the way a source path
/// does counts, whatever it is handed to — `Directory(…)`, `File(…)`, the
/// shared `dartFilesUnder(…)`, a `const` for any of them — and an
/// interpolation ends it where its static part ends. Wrong only ever by
/// selecting MORE, the one safe direction for a selection to be wrong in:
/// `{'tool': 'eraser'}` names a map key, and a change under `tool/` runs that
/// test too. A path assembled behind a variable (`'$root/lib'`) is not read;
/// no scan builds one today.
///
/// ⛔NOT AN EDGE: [importsOf] stays what it was. A walk depends on what the
/// files say, not on where one of them lives, so `code_map`'s question —
/// 「who would notice if this moved」 — is not its question.
Set<String> pathsReadAsText(String source) => {
  for (final match in _sourcePathLiteral.allMatches(source)) match.group(1)!,
};

/// The roots a test reads a file under by spelling its path
/// ([pathsReadAsText]): the Dart sources, and the platform folders the
/// app's shells live in.
const kTextRoots = [
  'lib', 'test', 'tool', //
  'android', 'ios', 'linux', 'macos', 'windows',
];

final _sourcePathLiteral = RegExp(
  '''['"]((?:${kTextRoots.join('|')})(?:/[A-Za-z0-9_/.\\-]*)?)'''
  r'''(?:\$[^'"]*)?['"]''',
);

/// The repo-relative Dart files [source] (living at [from]) depends on.
///
/// `dart:` is not a file. Third-party `package:` targets are not ours to
/// track. `package:anicel/x` and a relative path both resolve into `lib/…`.
Set<String> importsOf(String from, String source) {
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
      out.add(normalisePath('${dirOf(from)}/$target'));
    }
  }
  return out;
}

/// file -> the repo-relative Dart files it imports directly, for every
/// `.dart` file under [roots].
Map<String, Set<String>> buildImportGraph({
  List<String> roots = const ['lib', 'test'],
}) {
  final graph = <String, Set<String>>{};
  for (final dir in roots) {
    final directory = Directory(dir);
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      graph[path] = importsOf(path, entity.readAsStringSync());
    }
  }
  return graph;
}

/// The roots the import graph is walked from, for the selection and the
/// result records alike. `tool/` too: a tool test reaches what its tool
/// imports — until 2026-10-19 the walk stopped at the tool a test named,
/// and a change to `tool/flutter_room.dart` selected none of the line's
/// tests that run through `tool/test_queue.dart`.
const kGraphRoots = ['lib', 'test', 'tool'];

/// Everything [start] can reach through [graph] — however far away, or no
/// more than [within] imports from it.
///
/// ⚠️Excludes [start] itself unless something it reaches imports it back.
Set<String> closureOf(
  String start,
  Map<String, Set<String>> graph, {
  int? within,
}) {
  final seen = <String>{};
  var step = [start];
  for (var away = 1; step.isNotEmpty; away++) {
    if (within != null && away > within) break;
    step = [
      for (final current in step)
        for (final next in graph[current] ?? const <String>{})
          if (seen.add(next)) next,
    ];
  }
  return seen;
}

/// What a file reads: the file and every file its imports reach, and every
/// path one of those spells to read as text ([pathsReadAsText]).
typedef Reach = ({Set<String> files, Set<String> prefixes});

/// The [Reach] of each file asked — one law for what a test depends on,
/// asked by the selection (`selectTests`) and by the green record
/// (`Inputs.of`). ↩️Until 10-20 each walked it on its own: the record read
/// the helpers' text reads and the selection read only the test's, so a
/// test whose helper reads `tool/lane.sh` was keyed on the script and never
/// chosen by a change to it.
class Reaches {
  Reaches(this.imports, this.read, {this.within});

  final Map<String, Set<String>> imports;
  final String Function(String path) read;

  /// How many imports from a file its reach goes — every one when null:
  /// the selection before a lane lands asks the near ones only
  /// (`kNearImports`), the green record and the wide check every one.
  final int? within;

  final _texts = <String, Set<String>>{};
  final _of = <String, Reach>{};

  /// ⛔A file under `lib/` reads no path: it is the app's code, run where
  /// no checkout exists, and a literal there is a word — the `'tool'` key
  /// of `tool_choice.dart` once made every test that reaches it read all
  /// of `tool/` (10-20, 392 files for a change to one tool).
  Reach of(String start) => _of.putIfAbsent(start, () {
    final files = {start, ...closureOf(start, imports, within: within)};
    return (
      files: files,
      prefixes: {
        for (final file in files)
          if (!file.startsWith('lib/')) ..._textsOf(file),
      },
    );
  });

  Set<String> _textsOf(String file) => _texts.putIfAbsent(file, () {
    try {
      return pathsReadAsText(read(file));
    } on FileSystemException {
      // A file an edge names that is gone reads nothing.
      return const {};
    }
  });
}

/// Whether one of [changed] lies in [reach]: one of its files, or under a
/// path it reads.
bool reachesAny(Reach reach, Set<String> changed) => changed.any(
  (file) =>
      reach.files.contains(file) || reach.prefixes.any(file.startsWith),
);

/// For each file in [graph], which of [starts] can reach it.
///
/// ⚠️One pass per start, not per file: the closure of each start is walked
/// once and every file in it gets that start recorded. Asking the question
/// the other way round — 「who reaches this file」 for each of 809 files —
/// walks the graph 809 times to learn the same thing.
///
/// A file no start reaches simply has no entry. ⛔Callers must treat a
/// MISSING key as an empty set and not as 「not measured」: the difference is
/// the whole point of the reachability question.
Map<String, Set<String>> reachedBy(
  Iterable<String> starts,
  Map<String, Set<String>> graph,
) {
  final out = <String, Set<String>>{};
  for (final start in starts) {
    for (final reached in closureOf(start, graph)) {
      out.putIfAbsent(reached, () => <String>{}).add(start);
    }
  }
  return out;
}

String dirOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '.' : path.substring(0, i);
}

/// Collapses `a/b/../c` to `a/c` so two spellings of one file are one node.
///
/// ⛔A POSIX absolute path KEEPS its leading `/`. Dropping it turned
/// `/tmp/x/beta.dart` into `tmp/x/beta.dart` — a different node from the one
/// the walk keyed the file under — so the import edge, and the fan-in counted
/// from it, simply vanished. Windows never showed this: `C:` is an ordinary
/// first segment there (found on Linux CI, 2026-09-21).
String normalisePath(String path) {
  final fromRoot = path.startsWith('/');
  final parts = <String>[];
  for (final part in path.split('/')) {
    if (part == '.' || part.isEmpty) continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  final joined = parts.join('/');
  return fromRoot ? '/$joined' : joined;
}

/// Every set of files in [graph] that import each other around a loop: the
/// strongly connected components with more than one member, each sorted,
/// the list sorted by its first file.
///
/// The compiler links a loop without complaint, so nothing else reports
/// this. What a loop costs is that none of its files can be read, tested or
/// moved without the others — `test/architecture/no_import_cycles_test.dart`
/// keeps the ledger of the loops that are allowed to exist and why.
///
/// Tarjan's algorithm; the recursion is one frame per file on the current
/// path, which for a graph of ~900 shallow files is nowhere near the stack.
List<List<String>> importCycles(Map<String, Set<String>> graph) {
  var next = 0;
  final index = <String, int>{};
  final lowLink = <String, int>{};
  final stack = <String>[];
  final onStack = <String>{};
  final loops = <List<String>>[];

  void visit(String file) {
    index[file] = next;
    lowLink[file] = next;
    next++;
    stack.add(file);
    onStack.add(file);
    for (final target in graph[file] ?? const <String>{}) {
      if (!index.containsKey(target)) {
        visit(target);
        if (lowLink[target]! < lowLink[file]!) lowLink[file] = lowLink[target]!;
      } else if (onStack.contains(target) && index[target]! < lowLink[file]!) {
        lowLink[file] = index[target]!;
      }
    }
    if (lowLink[file] != index[file]) return;
    final component = <String>[];
    String popped;
    do {
      popped = stack.removeLast();
      onStack.remove(popped);
      component.add(popped);
    } while (popped != file);
    if (component.length > 1) loops.add(component..sort());
  }

  for (final file in graph.keys) {
    if (!index.containsKey(file)) visit(file);
  }
  return loops..sort((a, b) => a.first.compareTo(b.first));
}
