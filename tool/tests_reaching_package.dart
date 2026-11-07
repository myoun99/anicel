// THE TESTS THAT REACH A PACKAGE — for a CI job that cannot run what the
// package runs.
//
//   dart run tool/tests_reaching_package.dart <package>
//
// Prints, one path a line, every test file that imports `package:<package>/…`
// or whose imports, however far away, reach a file that does — through the
// one graph of what a file depends on (tool/import_graph.dart). Run from the
// repository root.
//
// 🗣️유저 gpu-engine-skeleton-Q16 (2026-11-07) 「윈도 샤드는 엔진에 닿는 시험을
// 리눅스에 맡긴다」: a Windows runner has no GPU, and the one adapter it
// opens, WARP, never finishes the engine's optimised shaders — so ci.yml's
// Windows shards leave the tests that reach package:gpu_engine to the Linux
// shards, which run them on lavapipe (.github/actions/test-shard,
// `leave-out-package`).
import 'dart:io';

import 'import_graph.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln(
      'usage: dart run tool/tests_reaching_package.dart <package>',
    );
    exit(2);
  }
  final graph = buildImportGraph(roots: kGraphRoots);
  final importers = {
    for (final path in graph.keys)
      if (importsPackage(File(path).readAsStringSync(), args.single)) path,
  };
  for (final test in testsReaching(importers, graph).toList()..sort()) {
    stdout.writeln(test);
  }
}
