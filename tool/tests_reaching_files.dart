// THE TESTS THAT REACH A FILE — for a CI shard that weighs the files it deals.
//
//   dart tool/tests_reaching_files.dart <path> [<path> …]
//
// Prints, one path a line, every test file whose imports, however far away,
// reach one of the named files — through the one graph of what a file
// depends on (tool/import_graph.dart), the walk tests_reaching_package.dart
// takes from a package's importers. Run from the repository root.
//
// .github/actions/test-shard weighs the tests that open the app this way
// (ci-takes-an-hour-on-lavapipe, 2026-11-17). ⛔A named file that is not
// there is an error, not an empty list: a rename would otherwise leave the
// weight on nothing, and a slow shard looks exactly like a normal one.
import 'dart:io';

import 'import_graph.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart tool/tests_reaching_files.dart <path> …');
    exit(2);
  }
  final missing = [
    for (final path in args)
      if (!File(path).existsSync()) path,
  ];
  if (missing.isNotEmpty) {
    stderr.writeln('no such file: ${missing.join(', ')}');
    exit(2);
  }
  final graph = buildImportGraph(roots: kGraphRoots);
  for (final test in testsReaching(args.toSet(), graph).toList()..sort()) {
    stdout.writeln(test);
  }
}
