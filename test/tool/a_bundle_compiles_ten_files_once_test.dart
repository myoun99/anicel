@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_bundles.dart';
import '../../tool/test_seconds.dart';

/// 🗣️유저 2026-11-20, card the-wide-check-takes-five-hours-Q3 「a 묶는다 —
/// 혼자 서야 하는 파일만 따로」: a crowd batch's files run as entries of up
/// to ten, each file a group named by its path — one compile for ten files.
void main() {
  group('a file stands alone', () {
    test('when it starts a binding of its own — an isolate holds one', () {
      expect(
        whyAlone('class _Paced extends AutomatedTestWidgetsFlutterBinding {}\n'
            'void main() {}'),
        contains('binding of its own'),
      );
      expect(
        whyAlone('void main() {\n  LookTestBinding.ensureInitialized();\n}'),
        contains('LookTestBinding'),
      );
    });

    test('when its main is async, or there is none a group can call', () {
      expect(whyAlone('Future<void> main() async {}'), contains('async'));
      expect(whyAlone('void main() async {}'), contains('async'));
      expect(whyAlone('void helper() {}'), contains('no main'));
    });

    test("and not for flutter_test's own binding, nor what a comment says",
        () {
      expect(
        whyAlone('void main() {\n'
            '  TestWidgetsFlutterBinding.ensureInitialized();\n'
            '  // LookTestBinding.ensureInitialized() is not this file.\n'
            '}'),
        isNull,
      );
      expect(whyAlone('void main() => guideShots(AppLanguage.en);'), isNull);
      expect(
        whyAlone('void main() {\n'
            "  expect(whyAlone('class _P extends AutomatedTestWidgetsFlutter"
            "Binding {}'), isNotNull);\n"
            "  print('LookTestBinding.ensureInitialized()');\n"
            '}'),
        isNull,
        reason: 'what a string says is not the file',
      );
    });
  });

  group("a file's library annotations are its entry's", () {
    test('read as written, each on one line — what follows `library;` is '
        'no longer the library', () {
      const source = "@TestOn('vm')\n"
          '@Timeout(\n  Duration(minutes: 3),\n)\n'
          '// a comment\n'
          '@Skip()\n'
          'library;\n'
          '\n'
          '@Timeout(Duration(minutes: 9))\n'
          'void main() {}\n';
      expect(libraryAnnotations(source), [
        "@TestOn('vm')",
        '@Timeout( Duration(minutes: 3), )',
        '@Skip()',
      ]);
      expect(libraryAnnotations('// a comment\nvoid main() {}'), isEmpty);
    });

    test('🪦an entry carries them as its own, and hands a group nothing a '
        'flutter_test group cannot take — it takes a skip and a retry', () {
      final source = entrySource(
        ['test/a_test.dart', 'test/b_test.dart'],
        (path) => "@TestOn('vm')\n@Timeout(Duration(minutes: 5))\nlibrary;\n"
            'void main() {}',
        toRoot: '../../..',
      );
      expect(
        source,
        contains("@TestOn('vm')\n@Timeout(Duration(minutes: 5))\nlibrary;\n"
            "import 'package:flutter_test/flutter_test.dart';\n"),
      );
      expect(source, contains("  group('test/a_test.dart', () {"));
      expect(source, contains("  group('test/b_test.dart', () {"));
    });

    test('so a file shares an entry only with files of its own annotations',
        () {
      String sourceOf(String path) => path.contains('slow')
          ? '@Timeout(Duration(minutes: 3))\nlibrary;\nvoid main() {}'
          : 'void main() {}';
      final files = [
        for (var i = 0; i < 12; i++)
          // Dealt in turn as one lot, every second file would share a
          // bundle: a third of them slow puts slow and plain in each.
          if (i % 3 == 0)
            'test/slow${i}_test.dart'
          else
            'test/plain${i}_test.dart',
      ];
      final cut = bundlesOf(files, read: sourceOf);
      expect(cut.alone, isEmpty);
      for (final bundle in cut.bundles) {
        expect(
          {
            for (final file in bundle)
              libraryAnnotations(sourceOf(file)).join('\n'),
          },
          hasLength(1),
          reason: '$bundle',
        );
      }
      expect(cut.bundles.expand((bundle) => bundle).toSet(), {...files});
    });
  });

  group("a font once loaded is the isolate's", () {
    const sources = {
      'test/helpers/faces.dart': "import 'package:flutter/services.dart';\n"
          "Future<void> faces() => FontLoader('BIZ UDPGothic').load();",
      'test/helpers/through.dart': "export 'faces.dart';",
      'test/helpers/plain.dart': 'void nothing() {}',
      'test/a/direct_test.dart': "void main() { FontLoader('x'); }",
      'test/a/helped_test.dart': "import '../helpers/through.dart';\n"
          'void main() {}',
      'test/a/plain_test.dart': "import '../helpers/plain.dart';\n"
          '// FontLoader( is what a comment says\n'
          "void main() { print('FontLoader('); }",
      'test/a/planted_test.dart': 'void main() {\n'
          "  const planted = '''\n"
          "import '../helpers/faces.dart';\n"
          "import '../nowhere.dart';\n"
          "''';\n"
          '}',
      'test/a/broken_test.dart': "import 'gone.dart';\nvoid main() {}",
    };
    String read(String path) => sources[path] ??
        (throw PathNotFoundException(path, const OSError('not there', 2)));

    test('a file loads one by its own hand or through a test file it uses, '
        'at any depth — not by what a comment or a string says', () {
      expect(loadsFonts('test/a/direct_test.dart', read: read), isTrue);
      expect(loadsFonts('test/a/helped_test.dart', read: read), isTrue);
      expect(loadsFonts('test/a/plain_test.dart', read: read), isFalse);
    });

    test('what it uses is what its directives name — not an import a scan '
        'test plants in a string, nor a file that is not there', () {
      expect(loadsFonts('test/a/planted_test.dart', read: read), isFalse);
      expect(loadsFonts('test/a/broken_test.dart', read: read), isFalse);
    });

    test('and is bundled only with files that load one too', () {
      final cut = bundlesOf([
        'test/a/direct_test.dart',
        'test/a/plain_test.dart',
        'test/a/helped_test.dart',
      ], read: read);
      expect(cut.alone, isEmpty);
      expect(
        cut.bundles.map((bundle) => bundle.toSet()),
        unorderedEquals([
          {'test/a/direct_test.dart', 'test/a/helped_test.dart'},
          {'test/a/plain_test.dart'},
        ]),
      );
    });
  });

  group("a binding once started is the isolate's", () {
    const sources = {
      'test/helpers/on_screen.dart':
          "import 'package:flutter_test/flutter_test.dart';\n"
          'void testOnScreen(String name) =>\n'
          '    testWidgets(name, (tester) async {});',
      'test/b/widget_test.dart':
          "void main() { testWidgets('x', (tester) async {}); }",
      'test/b/bound_test.dart':
          'void main() { TestWidgetsFlutterBinding.ensureInitialized(); }',
      'test/b/helped_test.dart': "import '../helpers/on_screen.dart';\n"
          'void main() {}',
      'test/b/bare_test.dart': '// testWidgets( is what a comment says\n'
          "void main() { test('testWidgets(', () {}); }",
    };
    String read(String path) => sources[path] ??
        (throw PathNotFoundException(path, const OSError('not there', 2)));

    test('a file starts one by its own hand or through a test file it uses '
        '— not by what a comment or a string says', () {
      expect(startsABinding('test/b/widget_test.dart', read: read), isTrue);
      expect(startsABinding('test/b/bound_test.dart', read: read), isTrue);
      expect(startsABinding('test/b/helped_test.dart', read: read), isTrue);
      expect(startsABinding('test/b/bare_test.dart', read: read), isFalse);
    });

    test('and is bundled only with files that start one too', () {
      final cut = bundlesOf([
        'test/b/widget_test.dart',
        'test/b/bare_test.dart',
        'test/b/bound_test.dart',
        'test/b/helped_test.dart',
      ], read: read);
      expect(cut.alone, isEmpty);
      expect(
        cut.bundles.map((bundle) => bundle.toSet()),
        unorderedEquals([
          {
            'test/b/widget_test.dart',
            'test/b/bound_test.dart',
            'test/b/helped_test.dart',
          },
          {'test/b/bare_test.dart'},
        ]),
      );
    });
  });

  group('a bundled file starts from what a file alone starts from', () {
    test('its group sets it again before its first test, by the code the '
        'config sets it with', () {
      const files = ['test/a_test.dart', 'test/b_test.dart'];
      final source = entrySource(
        files,
        (path) => 'void main() {}',
        toRoot: '../../..',
      );
      expect(
        source,
        contains("import '../../../test/flutter_test_config.dart' "
            'show startATestFile;'),
      );
      for (final (i, file) in files.indexed) {
        expect(
          source,
          contains("  group('$file', () {\n"
              '    setUpAll(startATestFile);\n'
              '    f$i.main();\n'
              '  });'),
        );
      }
    });

    test('and the config sets nothing a file starts from but by that code',
        () {
      final config = File('test/flutter_test_config.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      final head = config.indexOf('Future<void> testExecutable(');
      final body = config.substring(head, config.indexOf('\n}\n', head));
      expect(
        [
          for (final set in RegExp(
            r'^  ([A-Za-z_][\w.]*)\s*=[^=>]',
            multiLine: true,
          ).allMatches(body))
            set[1],
        ],
        ['_documents'],
        reason: 'a value testExecutable sets is set once an entry — in a '
            'bundle, the second file starts from what the first left. It '
            "belongs in startATestFile; the run's own temp and the Documents "
            "home in it are the run's, once",
      );
      expect(
        body.indexOf('startATestFile();'),
        allOf(
          greaterThan(body.indexOf('giveTheRunItsOwnTemp()')),
          lessThan(body.indexOf('await testMain()')),
        ),
      );
    });
  });

  group('a batch is cut into bundles', () {
    String sourceOf(String path) => path.contains('own')
        ? 'void main() { ScaledTestBinding.ensureInitialized(); }'
        : 'void main() {}';
    List<String> named(int count) => [
      for (var i = 0; i < count; i++) 'test/f${'$i'.padLeft(2, '0')}_test.dart',
    ];

    test('of ten at most, dealt in turn from the longest, the files that '
        'cannot share left as they are', () {
      final files = [...named(23), 'test/own_test.dart'];
      final cut = bundlesOf(files, read: sourceOf);
      expect(cut.alone, ['test/own_test.dart']);
      expect(cut.bundles.map((bundle) => bundle.length), [8, 8, 7]);
      expect(cut.bundles.first.take(3), [
        'test/f00_test.dart',
        'test/f03_test.dart',
        'test/f06_test.dart',
      ]);
      expect(cut.bundles.expand((bundle) => bundle).toSet(), {...named(23)});
    });

    test('the census reverses each bundle, and no more', () {
      final forward = bundlesOf(named(12), read: sourceOf);
      final back = bundlesOf(named(12), read: sourceOf, reversed: true);
      expect(back.bundles, [
        for (final bundle in forward.bundles) bundle.reversed.toList(),
      ]);
    });

    test('an entry imports its files and runs each as a group named by its '
        'path', () {
      final source = entrySource(
        ['test/a_test.dart', 'test/b_test.dart'],
        (path) => 'void main() {}',
        toRoot: '../../..',
      );
      expect(source, isNot(contains('library;')));
      expect(source, contains("import '../../../test/a_test.dart' as f0;"));
      expect(source, contains("  group('test/a_test.dart', () {"));
      expect(source, contains("  group('test/b_test.dart', () {"));
      expect(
        bundleConfigSource('../../..'),
        "export '../../../test/flutter_test_config.dart';\n",
      );
    });
  });

  group("a bundle's report is read file by file", () {
    const entry = 'C:/r/.dart_tool/test_bundles/batch0/bundle000_test.dart';

    /// A json report of one entry that ran [files] — each `(path, results)`,
    /// a result a test of it, `open` one that never finished — loading in
    /// [load] ms, every test 100 ms.
    String reportOf(
      List<(String, List<String>)> files, {
      int load = 1000,
      bool loaded = true,
      bool ended = true,
      String suite = entry,
      bool tornDownRed = false,
    }) {
      final lines = <Object>[];
      var time = 0;
      var id = 10;
      lines
        ..add({
          'suite': {'id': 0, 'platform': 'vm', 'path': suite},
          'type': 'suite',
          'time': time,
        })
        ..add({
          'test': {
            'id': 1,
            'name': 'loading $suite',
            'suiteID': 0,
            'groupIDs': <int>[],
          },
          'type': 'testStart',
          'time': time,
        });
      time += load;
      lines.add({
        'testID': 1,
        'result': loaded ? 'success' : 'error',
        'hidden': true,
        'type': 'testDone',
        'time': time,
      });
      if (loaded) {
        lines.add({
          'group': {'id': 2, 'suiteID': 0, 'parentID': null, 'name': ''},
          'type': 'group',
          'time': time,
        });
        for (final (path, results) in files) {
          final group = id++;
          lines.add({
            'group': {'id': group, 'suiteID': 0, 'parentID': 2, 'name': path},
            'type': 'group',
            'time': time,
          });
          for (final result in results) {
            final test = id++;
            lines.add({
              'test': {
                'id': test,
                'name': '$path a test',
                'suiteID': 0,
                'groupIDs': [2, group],
              },
              'type': 'testStart',
              'time': time,
            });
            time += 100;
            if (result == 'open') continue;
            lines.add({
              'testID': test,
              'result': result,
              'hidden': false,
              'type': 'testDone',
              'time': time,
            });
          }
        }
      }
      if (tornDownRed) {
        lines
          ..add({
            'test': {
              'id': 9,
              'name': '(tearDownAll)',
              'suiteID': 0,
              'groupIDs': [2],
            },
            'type': 'testStart',
            'time': time,
          })
          ..add({
            'testID': 9,
            'result': 'failure',
            'hidden': true,
            'type': 'testDone',
            'time': time + 10,
          });
      }
      if (ended) lines.add({'success': true, 'type': 'done', 'time': time});
      return lines.map(jsonEncode).join('\n');
    }

    test('each file by its group, with an even share of the one load', () {
      final runs = suiteRuns(
        reportOf([
          ('test/a_test.dart', ['success', 'success']),
          ('test/b_test.dart', ['success', 'failure']),
        ]),
        root: 'C:/r',
      );
      expect(runs, containsAll([
        (path: 'test/a_test.dart', ms: 200 + 500, green: true),
        (path: 'test/b_test.dart', ms: 200 + 500, green: false),
        (
          path: '.dart_tool/test_bundles/batch0/bundle000_test.dart',
          ms: 1000,
          green: true,
        ),
      ]));
      expect(
        redTests(reportOf([
          ('test/b_test.dart', ['success', 'failure']),
        ]), root: 'C:/r'),
        [(path: 'test/b_test.dart', name: 'test/b_test.dart a test')],
      );
    });

    test('an entry that failed to load makes each of its files red; one '
        'that never ended leaves them unknown', () {
      const entries = {
        '.dart_tool/test_bundles/batch0/bundle000_test.dart': [
          'test/a_test.dart',
          'test/b_test.dart',
        ],
      };
      expect(
        runsOfFiles(
          suiteRuns(reportOf(const [], loaded: false), root: 'C:/r'),
          entries,
        ),
        [
          (path: 'test/a_test.dart', ms: null, green: false),
          (path: 'test/b_test.dart', ms: null, green: false),
        ],
      );
      final cut = runsOfFiles(
        suiteRuns(
          reportOf([
            ('test/a_test.dart', ['success']),
            ('test/b_test.dart', ['failure']),
          ], ended: false),
          root: 'C:/r',
        ),
        entries,
      );
      expect(cut.map((run) => (run.path, run.green)), [
        ('test/a_test.dart', null),
        ('test/b_test.dart', null),
      ]);
    });

    test('a cut names the files that stood — by their own paths, not the '
        "entry's — and no file that ended", () {
      // 🔬PR 1503's Linux shard 4 (2026-11-23): two bundles stood in their
      // first files; each runs again alone (affected_tests, stoodInCut).
      expect(
        stoodFiles(
          reportOf([
            ('test/a_test.dart', ['success', 'open']),
            ('test/b_test.dart', ['success']),
            ('test/c_test.dart', ['open']),
          ], ended: false),
          root: 'C:/r',
        ),
        {'test/a_test.dart', 'test/c_test.dart'},
      );
      expect(
        stoodFiles(reportOf(const [], loaded: false), root: 'C:/r'),
        isEmpty,
        reason: 'a file whose load failed stood in no test of its own',
      );
    });

    test("an entry whose own test went red — the config's after its "
        'files — makes every file of it red, its green ones too', () {
      // Which file left what the config's last check found is not said:
      // each runs again alone, where the check is its own.
      expect(
        runsOfFiles(
          suiteRuns(
            reportOf([
              ('test/a_test.dart', ['success']),
            ], tornDownRed: true),
            root: 'C:/r',
          ),
          const {
            '.dart_tool/test_bundles/batch0/bundle000_test.dart': [
              'test/a_test.dart',
            ],
          },
        ).map((run) => (run.path, run.green)),
        [('test/a_test.dart', false)],
      );
    });

    test('a green entry stands for a file that declared no test', () {
      expect(
        runsOfFiles(
          suiteRuns(reportOf([
            ('test/a_test.dart', ['success']),
          ]), root: 'C:/r'),
          const {
            '.dart_tool/test_bundles/batch0/bundle000_test.dart': [
              'test/a_test.dart',
              'test/empty_test.dart',
            ],
          },
        ).map((run) => (run.path, run.green)),
        [('test/a_test.dart', true), ('test/empty_test.dart', true)],
      );
    });

    test('a file of its own is read as ever — its groups are its own', () {
      expect(
        suiteRuns(
          reportOf([
            ('a group of it', ['success', 'failure']),
          ], suite: 'C:/r/test/a_test.dart'),
          root: 'C:/r',
        ),
        [(path: 'test/a_test.dart', ms: 1200, green: false)],
      );
      expect(isBundleEntry('C:/r/test/a_test.dart'), isFalse);
      expect(isBundleEntry(entry), isTrue);
      expect(isBundleEntry(r'.dart_tool\test_bundles\batch1\b_test.dart'),
          isTrue);
    });
  });

  // 🔬2026-11-23 (⑮): the wide run's log named the 12 files that lost their
  // isolation and neither their place nor the file before them — what a
  // ledger line says (placeInBundle has why).
  test('a file that lost its isolation is said with its place in its bundle '
      'and the file before it', () {
    const bundle = [
      'test/a_test.dart',
      'test/b_test.dart',
      'test/c_test.dart',
    ];
    expect(placeInBundle('test/a_test.dart', bundle), '1/3 in its bundle, '
        'first');
    expect(placeInBundle('test/c_test.dart', bundle), '3/3 in its bundle, '
        'after test/b_test.dart');
    expect(placeInBundle('test/d_test.dart', bundle), 'not in its bundle');
    final source = File('tool/affected_tests.dart').readAsStringSync()
        .replaceAll('\r\n', '\n');
    // Every file of a bundled batch is kept with its bundle as it ran…
    expect(
      source,
      contains('for (final files in entries.values) {\n'
          '          for (final file in files) {\n'
          '            bundleOf[file] = files;'),
    );
    // …and said where the census reads.
    expect(
      source,
      contains('_sayLostIsolation(\n'
          '    lostIsolation,\n'
          '    bundledReds,\n'
          '    bundleOf,\n'
          '    stood: stoodInCut,\n'
          '  );'),
    );
    expect(
      source,
      contains("final place = bundle == null ? '' : "
          "' (\${placeInBundle(file, bundle)})';"),
    );
  });

  test('a bundled run says what its bundles did where they are read — and '
      'keeps its times, and no green till the census', () {
    final source = File('tool/affected_tests.dart').readAsStringSync()
        .replaceAll('\r\n', '\n');
    // Only the first pass bundles, only the crowd; the reds run alone.
    expect(
      source,
      contains('final made = bundle != null && bundled && kind == '
          'BatchKind.crowd'),
    );
    expect(source, contains('await runAll(selected, bundled: true, ('));
    expect(
      source,
      contains('await runAll(reds.toList()..sort(), (i, report, result, '
          'root, _) {'),
    );
    expect(
      source,
      contains('final runs = runsOf[i] = _bundledRuns(report, entries, '
          'root: root);'),
    );
    // Red in a bundle, green alone: no flake, and forgiven.
    expect(
      source,
      contains('flaky.addAll(split.flaky.where((file) => '
          '!redInBundle.contains(file)));'),
    );
    expect(
      source,
      contains('lostIsolation.addAll(split.flaky.where(redInBundle.contains));'),
    );
    expect(
      source,
      contains('if (flaky.contains(file) || lostIsolation.contains(file)) '
          'return true;'),
    );
    // 🗣️관제 2026-11-23 (가): a bundle's file that stood when its batch was
    // cut runs once more alone, as a red one does — named lost if green.
    expect(
      source,
      contains('        if (result.cut) {\n'
          '          final stood = _stoodIn(\n'
          '            report,\n'
          '            root: root,\n'
          '          ).where(bundleOf.containsKey);\n'
          '          stoodInCut.addAll(stood);\n'
          '          redInBundle.addAll(stood);\n'
          '        }'),
    );
    expect(
      source,
      contains('          if (run.green == false) run.path,\n'
          '      ...stoodInCut,\n'
          '    };'),
    );
    expect(source, contains('    cut: cut != null,\n'));
    // Its entries are handed over in the batch's place, and taken away.
    expect(source, contains('made?.args ?? batch,'));
    expect(source, contains('made?.end();'));
    final bundledRuns = source.substring(
      source.indexOf('List<SuiteRun> _bundledRuns('),
      source.indexOf('List<({String path, String name})> _redTestsIn('),
    );
    expect(bundledRuns, isNot(contains('_keep(')));
    // A time skips no run, and the CI shards deal by it (_bundledRuns).
    expect(bundledRuns, contains('_keepTimes(runs);'));
  });
}
