@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/affected_tests.dart' show scansReaching, selectTests;
import '../../tool/import_graph.dart' show libPrefixesReadAsText;

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
void main() {
  group('what a scan reads', () {
    test('a walk of the whole tree reads all of lib', () {
      expect(libPrefixesReadAsText("Directory('lib').listSync()"), {'lib'});
    });

    test('a walk handed to the shared helper, or split over lines', () {
      expect(
        libPrefixesReadAsText("dartFilesUnder('lib/src/ui')"),
        {'lib/src/ui'},
      );
      expect(libPrefixesReadAsText("Directory(\n  'lib',\n)"), {'lib'});
    });

    test('an interpolated path reads as far as its static part', () {
      expect(
        libPrefixesReadAsText(r"Directory('lib/src/$layer')"),
        {'lib/src/'},
      );
    });

    test('⛔one named Dart file is an import edge already, not a walk', () {
      expect(
        libPrefixesReadAsText("File('lib/src/ui/text/app_strings.dart')"),
        isEmpty,
      );
      expect(
        libPrefixesReadAsText("import 'package:anicel/src/ui/x.dart';"),
        isEmpty,
      );
      expect(libPrefixesReadAsText("'library'"), isEmpty);
    });
  });

  group('the selection', () {
    const scanAll = 'test/a_test.dart';
    const scanServices = 'test/b_test.dart';
    const plain = 'test/c_test.dart';
    final sources = {
      scanAll: "for (final f in Directory('lib').listSync()) {}",
      scanServices: "dartFilesUnder('lib/src/services')",
      plain: "import 'package:anicel/src/ui/x.dart';",
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

    test('⛔a change outside lib selects no scan', () {
      expect(reaching({'test/helpers/x.dart'}), isEmpty);
    });

    test('🚨the run is handed the scans beside what the imports reach', () {
      final selected = selectTests(
        changedDart: {'lib/src/ui/x.dart'},
        tests: sources.keys.toList(),
        imports: {
          plain: {'lib/src/ui/x.dart'},
        },
        read: (path) => sources[path]!,
      );
      expect(selected, {scanAll, plain});
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
}
