// Where should the audit go first?
//
// Crosses `tool/code_map.dart` (how big, how forked, how much state) with the
// import graph (how central, and whether any test can even see it), so the
// order of work comes out of the tree rather than out of a hunch.
//
// 🚨★★★WHAT THE TWO REACH COLUMNS MEAN, AND WHAT THEY DO NOT
//
// `reach` is the number of test FILES that can arrive here by following
// imports at any distance. `direct` is how many name this file in an import
// of their own. Neither says 「tested」; both are sound in one direction only:
//
//   reach == 0   →  NO test can execute a line of this file. Certain.
//   reach  > 0   →  UNKNOWN. A test that reaches a file may only be building
//                   a widget three layers above it, asserting nothing here.
//
// 🧪MEASURED, AND THE FIRST ANSWER WAS USELESS. `reach` was the whole tool at
// first, and it came back saturated: 808 of 809 files are transitively
// reachable, the exception being a dev entry point nothing imports. In a tree
// this connected, 「a test can get here」 is true of everything and ranks
// nothing. `direct` was added because it is the sharp version of the same
// question — a test that names a file is far more likely to be about it —
// and it is the column to sort by when deciding where mutation time goes.
//
// ⛔Neither measures 「is it tested」 and neither may be printed as if it did.
// They measure 「could it possibly be」, which is the cheap half: one graph
// walk instead of 809 mutation runs. Whether a test actually goes red is what
// mutation answers, and this decides which files are worth spending it on.
//
// ⚠️And `reach == 0` is sound only for files reachable by an IMPORT. The
// contract tests under `test/architecture/` read `lib/` off disk with no
// import edge, so a file only they touch reads as unreached here. That gap is
// named in `tool/import_graph.dart` and pinned by its test.
//
// ## Usage
//
//   dart run tool/audit_rank.dart                # the tables
//   dart run tool/audit_rank.dart --by direct    # lines|fanin|complexity|reach|direct
//   dart run tool/audit_rank.dart --top 40
//   dart run tool/audit_rank.dart --unreached    # only what no test reaches
//   dart run tool/audit_rank.dart --json
import 'dart:convert';
import 'dart:io';

import 'code_map.dart';
import 'import_graph.dart';

/// The ranking the tool prints and the tests read: every lib file with
/// how many suites can reach it and how many test files name it.
({List<_Row> rows, int testFiles}) _rank() {
  final map = CodeMap.walk('lib');
  if (map.unreadable.isNotEmpty) {
    stderr.writeln('⛔${map.unreadable.length} file(s) did not parse — the '
        'ranking below is missing them:');
    map.unreadable.forEach((p, why) => stderr.writeln('  $p: $why'));
  }

  final graph = buildImportGraph(roots: ['lib', 'test']);
  final testFiles = graph.keys
      .where((f) => f.startsWith('test/') && f.endsWith('_test.dart'))
      .toList()
    ..sort();
  final reached = reachedBy(testFiles, graph);

  /// Distance 1: the test code that NAMES this file. See the header — `reach`
  /// came back saturated and this is the column that discriminates.
  ///
  /// ⚠️EVERYTHING UNDER `test/`, not just `_test.dart`. A helper that imports
  /// a file is test code naming it, one hop from the suite that uses the
  /// helper. 🧪Measured: counting only `_test.dart` called 118 lib files
  /// unnamed, counting all of `test/` calls it 117 — one file, out of 24
  /// non-suite files under `test/`. Small, and the smallness is the reason to
  /// write down which one was chosen rather than leave it to be re-derived.
  final namers = graph.keys.where((f) => f.startsWith('test/'));
  final direct = <String, int>{};
  for (final namer in namers) {
    for (final target in graph[namer] ?? const <String>{}) {
      direct[target] = (direct[target] ?? 0) + 1;
    }
  }

  final rows = [
    for (final file in map.files.values)
      _Row(
        file: file,
        // ⛔A MISSING KEY IS ZERO, not "unknown" — see `reachedBy`'s doc.
        reach: (reached[file.path] ?? const <String>{}).length,
        direct: direct[file.path] ?? 0,
        biggestType: _biggestTypeIn(map, file.path),
        worstComplexity: _worstComplexityIn(map, file.path),
      ),
  ];
  return (rows: rows, testFiles: testFiles.length);
}

/// The `--json` report, callable in-process — a test reads it from here
/// instead of spawning `dart run` (the no-process law in
/// tests_do_not_race_the_code_test).
Map<String, dynamic> auditRankReportJson() {
  final (:rows, :testFiles) = _rank();
  return {
    'testFiles': testFiles,
    'rows': [for (final r in rows) r.toJson()],
  };
}

void main(List<String> args) {
  final top = int.tryParse(_flag(args, '--top') ?? '') ?? 25;
  final by = _flag(args, '--by') ?? 'lines';

  final (:rows, :testFiles) = _rank();

  if (args.contains('--json')) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'testFiles': testFiles,
      'rows': [for (final r in rows) r.toJson()],
    }));
    return;
  }

  final unreached = rows.where((r) => r.reach == 0).toList()
    ..sort((a, b) => b.file.lines.compareTo(a.file.lines));

  _headline(rows, unreached, testFiles);

  if (args.contains('--unreached')) {
    _table('NO TEST REACHES THESE — biggest first', unreached, unreached.length);
    return;
  }

  _table('NO TEST REACHES THESE — biggest first', unreached, top);

  final sorted = rows.toList()..sort(_comparatorFor(by));
  _table('RANKED BY ${by.toUpperCase()}', sorted, top);
}

String? _flag(List<String> args, String name) {
  final i = args.indexOf(name);
  return i < 0 || i + 1 >= args.length ? null : args[i + 1];
}

int Function(_Row, _Row) _comparatorFor(String by) {
  switch (by) {
    case 'fanin':
      return (a, b) => b.file.fanIn.compareTo(a.file.fanIn);
    case 'complexity':
      return (a, b) => b.worstComplexity.compareTo(a.worstComplexity);
    case 'reach':
      return (a, b) => a.reach.compareTo(b.reach);
    case 'direct':
      // Fewest first, biggest file breaking the tie — the worklist order.
      return (a, b) => a.direct == b.direct
          ? b.file.lines.compareTo(a.file.lines)
          : a.direct.compareTo(b.direct);
    case 'lines':
      return (a, b) => b.file.lines.compareTo(a.file.lines);
    default:
      stderr.writeln('unknown --by「$by」; using lines. '
          'Known: lines · fanin · complexity · reach · direct');
      return (a, b) => b.file.lines.compareTo(a.file.lines);
  }
}

TypeFact? _biggestTypeIn(CodeMap map, String path) {
  TypeFact? best;
  for (final t in map.types) {
    if (t.file != path) continue;
    if (best == null || t.lines > best.lines) best = t;
  }
  return best;
}

int _worstComplexityIn(CodeMap map, String path) {
  var worst = 0;
  for (final f in map.functions) {
    if (f.file == path) worst = worst > f.complexity ? worst : f.complexity;
  }
  return worst;
}

class _Row {
  _Row({
    required this.file,
    required this.reach,
    required this.direct,
    required this.biggestType,
    required this.worstComplexity,
  });

  final FileFact file;
  final int reach;

  /// How many test files import this one BY NAME.
  final int direct;
  final TypeFact? biggestType;
  final int worstComplexity;

  Map<String, dynamic> toJson() => {
        'path': file.path,
        'layer': file.layer,
        'lines': file.lines,
        'fanIn': file.fanIn,
        'reach': reach,
        'direct': direct,
        'worstComplexity': worstComplexity,
        if (biggestType != null) 'biggestType': biggestType!.name,
      };
}

void _headline(List<_Row> rows, List<_Row> unreached, int testFiles) {
  final total = rows.fold<int>(0, (a, r) => a + r.file.lines);
  final dark = unreached.fold<int>(0, (a, r) => a + r.file.lines);
  final percent = total == 0 ? 0 : (dark * 100 / total).round();
  stdout.writeln('AUDIT RANK');
  stdout.writeln('  lib files          ${rows.length}');
  stdout.writeln('  test files         $testFiles');
  stdout.writeln('  reached by none    ${unreached.length} files, '
      '$dark lines ($percent% of lib)');

  final unnamed = rows.where((r) => r.direct == 0).toList();
  final unnamedLines = unnamed.fold<int>(0, (a, r) => a + r.file.lines);
  final unnamedPercent =
      total == 0 ? 0 : (unnamedLines * 100 / total).round();
  stdout.writeln('  named by no test   ${unnamed.length} files, '
      '$unnamedLines lines ($unnamedPercent% of lib)');
  stdout.writeln('');
  stdout.writeln('  ⚠️Both columns say 「could a test possibly see this」, not '
      '「is it tested」.');
  stdout.writeln('     reach 0 is certain and rare. `dir` 0 — no test even '
      'names the file — is the');
  stdout.writeln('     column that discriminates, and it is where mutation '
      'time is worth spending.');
  stdout.writeln('');
}

void _table(String title, List<_Row> rows, int top) {
  stdout.writeln('$title  (${rows.length} total)');
  stdout.writeln('   lines  fanIn  reach  dir  cx  path');
  for (final r in rows.take(top)) {
    stdout.writeln('  ${r.file.lines.toString().padLeft(6)}'
        '${r.file.fanIn.toString().padLeft(7)}'
        '${r.reach.toString().padLeft(7)}'
        '${r.direct.toString().padLeft(5)}'
        '${r.worstComplexity.toString().padLeft(4)}  ${r.file.path}');
  }
  stdout.writeln('');
}
