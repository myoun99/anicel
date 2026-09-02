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
/// and name nothing. Those tests are therefore INVISIBLE to this graph — no
/// edge exists for it to find — which is precisely the gap CLAUDE.md names
/// when it says 「소스를 훑는 계약 테스트는 이게 못 잡는다」 and tells you to
/// run them by hand. The heuristic below is still exact for the tests that
/// DO name a file; it is just not the whole story any more.
final _sourceReference = RegExp('''['"](lib/[A-Za-z0-9_/.\\-]*\\.dart)['"]''');

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

/// Everything [start] can reach through [graph], however far away.
///
/// ⚠️Excludes [start] itself unless something it reaches imports it back.
Set<String> closureOf(String start, Map<String, Set<String>> graph) {
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
String normalisePath(String path) {
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
