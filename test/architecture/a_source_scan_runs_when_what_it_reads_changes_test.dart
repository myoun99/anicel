@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/affected_tests.dart'
    show forcesFullRun, kNearConfigImports, kNearImports, selectTests;
import '../../tool/import_graph.dart'
    show buildImportGraph, kGraphRoots, pathsReadAsText;

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
    const config = 'test/flutter_test_config.dart';
    final sources = {
      scanAll: "for (final f in Directory('lib').listSync()) {}",
      scanServices: "dartFilesUnder('lib/src/services')",
      plain: "import 'package:anicel/src/ui/x.dart';",
      scanTests: "for (final f in dartFilesUnder('test')) {}",
      readsScript: "File('tool/lane.sh').readAsStringSync()",
    };
    Set<String> select(
      Set<String> changed, {
      Map<String, Set<String>> imports = const {},
      Map<String, String> more = const {},
    }) => selectTests(
      changed: changed,
      tests: [...sources.keys, ...more.keys.where((f) => f.endsWith('_test.dart'))],
      imports: imports,
      read: (path) => sources[path] ?? more[path] ?? '',
    );

    test('a change under a walked directory selects the scan', () {
      expect(select({'lib/src/ui/canvas/flip_hud_overlay.dart'}), {scanAll});
      expect(select({'lib/src/services/x.dart'}), {scanAll, scanServices});
    });

    test('🚨a changed TEST selects the scans that walk the tests', () {
      expect(select({'test/helpers/x.dart'}), {scanTests});
    });

    test('🚨a changed file that is not Dart selects what reads it', () {
      expect(select({'tool/lane.sh'}), {readsScript});
    });

    test('⛔a change nothing reads selects no scan', () {
      expect(select({'docs/index.html'}), isEmpty);
    });

    test('🚨the run is handed the scans beside what the imports reach', () {
      expect(
        select(
          {'lib/src/ui/x.dart', 'tool/lane.sh'},
          imports: {
            plain: {'lib/src/ui/x.dart'},
          },
        ),
        {scanAll, plain, readsScript},
      );
    });

    test('🚨a path a helper reads selects the tests that import the helper',
        () {
      // Until 10-20 the selection read only the test's own text, while the
      // green record read the helpers' too.
      const usesHelper = 'test/f_test.dart';
      const helper = 'test/helpers/lane_script.dart';
      expect(
        select(
          {'tool/lane.sh'},
          imports: {
            usesHelper: {helper},
          },
          more: {usesHelper: '', helper: "File('tool/lane.sh')"},
        ),
        {readsScript, usesHelper},
      );
    });

    test("⛔a word in the app's code is no path it reads", () {
      const usesBrush = 'test/g_test.dart';
      const brush = 'lib/src/ui/brush/tool_choice.dart';
      expect(
        select(
          {'tool/x.dart'},
          imports: {
            usesBrush: {brush},
          },
          more: {usesBrush: '', brush: "json['tool']"},
        ),
        isEmpty,
      );
    });

    test('🗣️Q8: before landing a change is asked near — what stands further '
        'is the wide run\'s', () {
      // plain → helper (1) → lib/a (2) → lib/b (3)
      const helper = 'test/helpers/h.dart';
      final imports = {
        plain: {helper},
        helper: {'lib/a.dart'},
        'lib/a.dart': {'lib/b.dart'},
      };
      Set<String> chosen(String changed, {int? within}) => selectTests(
        changed: {changed},
        tests: [plain],
        imports: imports,
        read: (_) => '',
        within: within,
      );
      expect(kNearImports, 2);
      expect(chosen('lib/a.dart', within: kNearImports), {plain});
      expect(chosen('lib/b.dart', within: kNearImports), isEmpty);
      expect(chosen('lib/b.dart'), {plain});
    });

    test('🗣️Q11: before landing the config is its file alone — what it '
        'imports is every suite\'s only in the wide run', () {
      const sandbox = 'lib/src/services/persistence/session_scratch.dart';
      final imports = {
        config: {sandbox},
      };
      expect(kNearConfigImports, 0);
      expect(select({sandbox}, imports: imports), sources.keys.toSet());
      // The scans that read the path are chosen at any distance.
      expect(
        selectTests(
          changed: {sandbox},
          tests: sources.keys.toList(),
          imports: imports,
          read: (path) => sources[path] ?? '',
          within: kNearImports,
          configWithin: kNearConfigImports,
        ),
        {scanAll, scanServices},
      );
    });

    test('🚨what the test config reaches is every suite\'s — and what it '
        'does not reach is not', () {
      const sandbox = 'lib/src/services/persistence/session_scratch.dart';
      final imports = {
        config: {sandbox},
        plain: {'lib/src/ui/x.dart'},
      };
      expect(select({sandbox}, imports: imports), sources.keys.toSet());
      // Not every suite's: what reaches it, and the scan that walks lib.
      expect(
        select({'lib/src/ui/x.dart'}, imports: imports),
        {scanAll, plain},
      );
    });
  });

  test('🚨the scan that escaped is selected by the change that broke it', () {
    const law = 'test/ui/canvas/the_frame_axis_is_asked_in_one_place_test.dart';
    expect(
      selectTests(
        changed: {'lib/src/ui/canvas/flip_hud_overlay.dart'},
        tests: [law],
        imports: const {},
        read: (path) => File(path).readAsStringSync(),
      ),
      {law},
    );
  });

  test('🚨and the one that escaped a day later, by the test that broke it', () {
    const law = 'test/architecture/tests_do_not_race_the_code_test.dart';
    expect(
      selectTests(
        changed: {'test/services/persistence/save_failure_test.dart'},
        tests: [law],
        imports: const {},
        read: (path) => File(path).readAsStringSync(),
      ),
      // The changed test too: it runs because it changed.
      {law, 'test/services/persistence/save_failure_test.dart'},
    );
  });

  test('🚨a platform folder runs no whole suite — the tests that read it are '
      'chosen like any scan', () {
    // 유저 10-20 (tests-crowd-the-machine-Q6): a lane that touched only
    // `windows/runner/` ran all 2,561 files, and the roots a scan could name
    // were lib, test and tool — so without the blanket, the tests that read
    // the shells would have gone unchosen.
    for (final shell in [
      'windows/runner/flutter_window.cpp',
      'android/app/build.gradle.kts',
      'ios/Runner/AppDelegate.swift',
      'linux/runner/my_application.cc',
      'macos/Runner/MainFlutterWindow.swift',
    ]) {
      expect(forcesFullRun(shell), isFalse, reason: shell);
    }
    for (final blanket in [
      'pubspec.yaml',
      'pubspec.lock',
      'analysis_options.yaml',
      'dart_test.yaml',
      'packages/qa_native/src/brush.c',
      'test/flutter_test_config.dart',
      // What the pubspec bundles into every suite, as the green record has
      // always keyed it (10-20).
      'assets/fonts/BIZUDPGothic-Regular.ttf',
      'shaders/x.frag',
    ]) {
      expect(forcesFullRun(blanket), isTrue, reason: blanket);
    }
    const reader = 'test/ui/the_close_button_asks_the_app_test.dart';
    expect(
      selectTests(
        changed: {'windows/runner/flutter_window.cpp'},
        tests: [reader],
        imports: const {},
        read: (path) => File(path).readAsStringSync(),
      ),
      {reader},
    );
    expect(
      pathsReadAsText("File('android/app/build.gradle.kts')"),
      {'android/app/build.gradle.kts'},
    );
  });

  test('🚨a tool a test runs through is walked into — what that tool '
      'imports selects it too', () {
    // Until 2026-10-19 the walk stopped at the tool a test named: a change
    // to flutter_room selected none of the line's tests.
    const line =
        'test/tool/a_test_run_waits_its_turn_in_the_machines_line_test.dart';
    final graph = buildImportGraph(roots: kGraphRoots);
    expect(
      selectTests(
        changed: {'tool/flutter_room.dart'},
        tests: [line],
        imports: graph,
        read: (path) => File(path).readAsStringSync(),
      ),
      {line},
    );
  });
}
