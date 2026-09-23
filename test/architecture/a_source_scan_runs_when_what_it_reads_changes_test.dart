@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/affected_tests.dart' show scansReaching, selectTests;
import '../../tool/import_graph.dart' show pathsReadAsText;

/// 🚨★★★A SOURCE SCAN RUNS WHEN WHAT IT READS CHANGES.
///
/// A contract test that walks `Directory('lib')` reads every file there as
/// TEXT and imports none of them, so the import graph the selection walks
/// never reaches it. CLAUDE.md answered that with a rule to remember — run
/// the scans by hand — and on 2026-09-23 the rule was not enough: F-28 put a
/// second reader of `framesRunVertically` on master, the one test that
/// forbids it (`test/ui/canvas/the_frame_axis_is_asked_in_one_place_test`)
/// was never selected, and master stayed red until an unrelated change ran
/// it. The landing runs `test/architecture/` whole; that test lives outside.
///
/// ⛔A rule I have to remember is the failure mode this project keeps
/// hitting — so the selection reads the scans itself.
///
/// 🚨2026-09-24, one root over: the selection read `lib` alone, so a test
/// that spawned a process went green through it — the law that forbids that
/// walks `test/`, and a changed test never selected it.
void main() {
  group('what a scan reads', () {
    test('a walk of the whole tree reads all of lib', () {
      expect(pathsReadAsText("Directory('lib').listSync()"), {'lib'});
    });

    test('a walk handed to the shared helper, or split over lines', () {
      expect(
        pathsReadAsText("dartFilesUnder('lib/src/ui')"),
        {'lib/src/ui'},
      );
      expect(pathsReadAsText("Directory(\n  'lib',\n)"), {'lib'});
    });

    test('an interpolated path reads as far as its static part', () {
      expect(
        pathsReadAsText(r"Directory('lib/src/$layer')"),
        {'lib/src/'},
      );
    });

    test('🚨every source root is read — the tests and the tools as much as '
        'the code', () {
      expect(pathsReadAsText("dartFilesUnder('test')"), {'test'});
      expect(pathsReadAsText("Directory('tool')"), {'tool'});
    });

    test('a file read by name is read too, whatever its root or extension', () {
      expect(
        pathsReadAsText("File('tool/lane.sh').readAsStringSync()"),
        {'tool/lane.sh'},
      );
      expect(
        pathsReadAsText("File('lib/src/ui/text/app_strings.dart')"),
        {'lib/src/ui/text/app_strings.dart'},
      );
    });

    test('⛔what only looks like a root is not one', () {
      expect(
        pathsReadAsText("import 'package:anicel/src/ui/x.dart';"),
        isEmpty,
      );
      expect(pathsReadAsText("'library'"), isEmpty);
      expect(pathsReadAsText("'testing' 'tools' 'toolbar'"), isEmpty);
    });
  });

  group('the selection', () {
    const scanAll = 'test/a_test.dart';
    const scanServices = 'test/b_test.dart';
    const plain = 'test/c_test.dart';
    const scanTests = 'test/d_test.dart';
    const readsScript = 'test/e_test.dart';
    final sources = {
      scanAll: "for (final f in Directory('lib').listSync()) {}",
      scanServices: "dartFilesUnder('lib/src/services')",
      plain: "import 'package:anicel/src/ui/x.dart';",
      scanTests: "for (final f in dartFilesUnder('test')) {}",
      readsScript: "File('tool/lane.sh').readAsStringSync()",
    };
    List<String> reaching(Set<String> changed) =>
        scansReaching(changed, sources.keys, (path) => sources[path]!);

    test('a change under a walked directory selects the scan', () {
      expect(reaching({'lib/src/ui/canvas/flip_hud_overlay.dart'}), [scanAll]);
      expect(
        reaching({'lib/src/services/x.dart'}),
        [scanAll, scanServices],
      );
    });

    test('🚨a changed TEST selects the scans that walk the tests', () {
      expect(reaching({'test/helpers/x.dart'}), [scanTests]);
    });

    test('🚨a changed file that is not Dart selects what reads it', () {
      expect(reaching({'tool/lane.sh'}), [readsScript]);
    });

    test('⛔a change nothing reads selects no scan', () {
      expect(reaching({'docs/index.html'}), isEmpty);
    });

    test('🚨the run is handed the scans beside what the imports reach', () {
      final selected = selectTests(
        changed: {'lib/src/ui/x.dart', 'tool/lane.sh'},
        tests: sources.keys.toList(),
        imports: {
          plain: {'lib/src/ui/x.dart'},
        },
        read: (path) => sources[path]!,
      );
      expect(selected, {scanAll, plain, readsScript});
    });
  });

  test('🚨the scan that escaped is selected by the change that broke it', () {
    const law = 'test/ui/canvas/the_frame_axis_is_asked_in_one_place_test.dart';
    expect(
      scansReaching(
        {'lib/src/ui/canvas/flip_hud_overlay.dart'},
        [law],
        (path) => File(path).readAsStringSync(),
      ),
      [law],
    );
  });

  test('🚨and the one that escaped a day later, by the test that broke it', () {
    const law = 'test/architecture/tests_do_not_race_the_code_test.dart';
    expect(
      scansReaching(
        {'test/services/persistence/save_failure_test.dart'},
        [law],
        (path) => File(path).readAsStringSync(),
      ),
      [law],
    );
  });
}
