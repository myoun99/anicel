@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/import_graph.dart';

/// 🚨★★★ONE ANSWER TO 「WHAT DOES THIS FILE DEPEND ON」.
///
/// `tool/affected_tests.dart` decides which tests a change can have broken;
/// `tool/code_map.dart` ranks files by how many others would notice if they
/// moved. Both ask the same question, and for a while both answered it with
/// their own code — written to 「the same shape」, which is how two laws start
/// agreeing and stop without telling anyone. The law moved into
/// `tool/import_graph.dart` and this pins it.
///
/// ⚠️Extraction parity was measured, not assumed: the whole graph was dumped
/// before and after the move (1,940 lines) and diffed to zero, and
/// `code_map`'s own tables were identical either side.
///
/// ⚠️It lives in `test/architecture/` and not `test/tool/` for the reason
/// given in `the_code_map_counts_what_is_there_test.dart`: the pre-push hook
/// treats `test/tool/` as board-only.
void main() {
  group('the premise', () {
    test('a plain import of a sibling is an edge at all', () {
      // ⛔Without this, every 「X is not an edge」 case below would also pass
      // on a function that returned an empty set for everything.
      expect(
        importsOf('lib/a.dart', "import 'b.dart';"),
        {'lib/b.dart'},
      );
    });
  });

  group('what is an edge', () {
    test('a relative path resolves against the importing file', () {
      expect(
        importsOf('lib/src/ui/a.dart', "import '../models/b.dart';"),
        {'lib/src/models/b.dart'},
      );
    });

    test("this package's own `package:` URI is the same file", () {
      // ⚠️Both spellings must land on ONE node or the graph counts a file
      // twice and reaches it through neither.
      expect(
        importsOf('lib/a.dart', "import 'package:anicel/src/x.dart';"),
        {'lib/src/x.dart'},
      );
    });

    test('export and part are edges, not just import', () {
      expect(
        importsOf('lib/a.dart', "export 'b.dart';\npart 'c.dart';"),
        {'lib/b.dart', 'lib/c.dart'},
      );
    });

    test('a lib path written as a STRING is an edge', () {
      // Some tests read a file off disk and check its source text. There is
      // no import to follow and the dependency is real.
      expect(
        importsOf(
          'test/x_test.dart',
          "final f = File('lib/src/ui/thing.dart');",
        ),
        {'lib/src/ui/thing.dart'},
      );
    });

    test('a file addressed from the ROOT keeps it', () {
      // 🚨The walk keys every file by the path it was listed at, so an edge
      // that dropped the leading slash pointed at a node no walk ever made:
      // the import was simply not counted, and neither was the fan-in from
      // it. Only machines whose paths START at the root could show it —
      // on Windows a drive is an ordinary first segment (Linux CI,
      // 2026-09-21).
      expect(
        importsOf('/tmp/build/a.dart', "import 'sub/../b.dart';"),
        {'/tmp/build/b.dart'},
      );
    });
  });

  group('what is not an edge', () {
    test('dart: is not a file', () {
      expect(importsOf('lib/a.dart', "import 'dart:io';"), isEmpty);
    });

    test('a third-party package is not ours to track', () {
      // ⚠️An edge to `package:flutter/material.dart` would out-rank every
      // real file on the fan-in table while answering nothing.
      expect(
        importsOf('lib/a.dart', "import 'package:flutter/material.dart';"),
        isEmpty,
      );
    });

    test('a test that scans a DIRECTORY names no file, so it has no edge', () {
      // 🚨★★★A KNOWN GAP, PINNED ON PURPOSE — not a behaviour anyone wants.
      //
      // The contract tests under `test/architecture/` walk `Directory('lib')`
      // whole. No edge exists for the graph to find, so `affected_tests`
      // cannot select them, which is exactly why CLAUDE.md says 「소스를 훑는
      // 계약 테스트는 이게 못 잡는다」 and tells you to run them by hand.
      //
      // ⛔The comment beside `_sourceReference` used to claim the opposite
      // (「none of them scans a directory」). It was true when written and
      // quietly stopped being true. If you are here to close the gap, close
      // it — and delete this test with the claim it was guarding.
      expect(
        importsOf(
          'test/architecture/x_test.dart',
          "for (final e in Directory('lib').listSync(recursive: true)) {}",
        ),
        isEmpty,
      );
    });
  });

  group('reachability', () {
    final graph = {
      'test/a_test.dart': {'lib/a.dart'},
      'test/b_test.dart': {'lib/b.dart'},
      'lib/a.dart': {'lib/shared.dart'},
      'lib/b.dart': {'lib/shared.dart'},
      'lib/shared.dart': <String>{},
      'lib/orphan.dart': <String>{},
    };

    test('a closure follows edges as far as they go', () {
      expect(
        closureOf('test/a_test.dart', graph),
        {'lib/a.dart', 'lib/shared.dart'},
      );
    });

    test('every start that reaches a file is recorded, not just the first', () {
      final reached = reachedBy(
        ['test/a_test.dart', 'test/b_test.dart'],
        graph,
      );
      expect(reached['lib/shared.dart'], {
        'test/a_test.dart',
        'test/b_test.dart',
      });
      expect(reached['lib/a.dart'], {'test/a_test.dart'});
    });

    test('a file nothing reaches has NO key, which means zero', () {
      // ⛔The distinction callers get wrong: a missing key is 「no test
      // reaches this」, which is the finding — not 「not measured」.
      final reached = reachedBy(['test/a_test.dart'], graph);
      expect(reached.containsKey('lib/orphan.dart'), isFalse);
      expect(reached['lib/orphan.dart'] ?? const <String>{}, isEmpty);
    });

    test('a cycle terminates', () {
      final cyclic = {
        'lib/a.dart': {'lib/b.dart'},
        'lib/b.dart': {'lib/a.dart'},
      };
      expect(closureOf('lib/a.dart', cyclic), {'lib/a.dart', 'lib/b.dart'});
    });
  });

  group('walking a tree', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('import_graph_fx'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('only the named roots are walked', () {
      Directory('${dir.path}/lib').createSync();
      Directory('${dir.path}/test').createSync();
      File('${dir.path}/lib/a.dart').writeAsStringSync("import 'b.dart';");
      File('${dir.path}/lib/b.dart').writeAsStringSync('');
      File('${dir.path}/test/a_test.dart').writeAsStringSync('');

      final previous = Directory.current;
      Directory.current = dir;
      try {
        expect(buildImportGraph(roots: ['lib']).keys, hasLength(2));
        expect(buildImportGraph(roots: ['lib', 'test']).keys, hasLength(3));
        // ⚠️A root that is not there is skipped, not an error — the tool runs
        // in checkouts that do not have every directory.
        expect(buildImportGraph(roots: ['nope']).keys, isEmpty);
      } finally {
        Directory.current = previous;
      }
    });
  });
}
