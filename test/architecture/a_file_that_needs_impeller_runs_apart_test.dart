@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/affected_tests.dart'
    show
        BatchKind,
        flutterTestArguments,
        gcTag,
        gcTagMarker,
        gpuTag,
        gpuTagMarker,
        impellerTag,
        impellerTagMarker,
        kNoTesterContext,
        kRunOrder,
        partitionByTag,
        ranNowhere,
        runInBatches,
        saysNoTesterContext;
import '../../tool/native_engine_provenance.dart' show engineStampPath;

/// 🖥️**A FILE THAT NEEDS IMPELLER RUNS ON IT, APART.**
///
/// gpu-pins-run-in-a-batch-of-their-own (2026-10-24): `flutter_gpu` is
/// Impeller's alone, and a plain `flutter test` runs the Skia tester — so a
/// pin that draws with it can only skip there. `--enable-impeller
/// --enable-flutter-gpu` gives it a context, and changes the engine for
/// every file in the command: the rest of the suite measures what Skia
/// draws, so the files carrying the tag run in batches of their own —
/// locally ([runInBatches]) and in each CI shard alike. A pin that needs
/// the Impeller tester but not Flutter GPU carries `impeller` and runs on
/// `--enable-impeller` alone (impeller-sweep-canvas-reds, the same day).
///
/// ⚠️This file never writes a marker out whole: a file that holds one IS
/// such a file, to the split here and to CI's.
void main() {
  Map<BatchKind, List<String>> split(Map<String, String> tree) =>
      partitionByTag(tree.keys.toList(), (path) => tree[path]!);

  test('a file carrying the gpu marker goes to the gpu files — not the '
      'crowd, not the pins', () {
    final kinds = split({
      'a_test.dart': 'void main() {}',
      'b_test.dart': '$gpuTagMarker\nlibrary;\nvoid main() {}',
      'c_test.dart': '$gcTagMarker\nlibrary;\nvoid main() {}',
    });
    expect(kinds[BatchKind.crowd], ['a_test.dart']);
    expect(kinds[BatchKind.gpu], ['b_test.dart']);
    expect(kinds[BatchKind.collector], ['c_test.dart']);
  });

  test('a file carrying the impeller marker goes to its own — not the gpu '
      'files', () {
    final kinds = split({
      'a_test.dart': '$impellerTagMarker\nlibrary;',
      'b_test.dart': '$gpuTagMarker\nlibrary;',
    });
    expect(kinds[BatchKind.impeller], ['a_test.dart']);
    expect(kinds[BatchKind.gpu], ['b_test.dart']);
  });

  test('🚨a file listing two tags goes where the first in BatchKind says — '
      'a file has one @Tags, and without its engine it cannot run at all',
      () {
    final kinds = split({
      'a_test.dart': "@Tags(['$gcTag', '$gpuTag'])\nlibrary;",
      'b_test.dart': "@Tags(['$gpuTag', '$gcTag'])\nlibrary;",
      'c_test.dart': "@Tags(['$impellerTag', '$gpuTag'])\nlibrary;",
      'd_test.dart': "@Tags(['$gcTag', '$impellerTag'])\nlibrary;",
      'e_test.dart': "// about '$gpuTag', and @Tags(['benchmark'])",
    });
    expect(kinds[BatchKind.gpu], [
      'a_test.dart',
      'b_test.dart',
      'c_test.dart',
    ]);
    expect(kinds[BatchKind.impeller], ['d_test.dart']);
    expect(kinds[BatchKind.collector], isEmpty);
    expect(kinds[BatchKind.crowd], ['e_test.dart']);
  });

  group('the run', () {
    /// The batches a run of [tree] makes, in order, as `(its files by a
    /// space, kind)`, the line handing each batch [suites] in turn.
    Future<List<(String, BatchKind)>> batchesOf(
      Map<String, String> tree, {
      List<int> suites = const [5],
      Map<String, int> known = const {},
      bool inTheLine = true,
    }) async {
      final ran = <(String, BatchKind)>[];
      var turn = 0;
      await runInBatches(
        tree.keys.toList(),
        known: known,
        inTheLine: inTheLine,
        read: (path) => tree[path]!,
        take: (left) async => suites[turn++ % suites.length],
        run: (batch, suites, {required kind}) async =>
            ran.add((batch.join(' '), kind)),
      );
      return ran;
    }

    test('the crowd first, then the files on another engine, then the '
        'collector pins — still last', () async {
      final ran = await batchesOf({
        'a_test.dart': '',
        'b_test.dart': '$impellerTagMarker\n',
        'c_test.dart': '$gcTagMarker\n',
        'd_test.dart': '',
        'e_test.dart': '$gpuTagMarker\n',
      });
      expect(ran, [
        ('a_test.dart d_test.dart', BatchKind.crowd),
        ('e_test.dart', BatchKind.gpu),
        ('b_test.dart', BatchKind.impeller),
        ('c_test.dart', BatchKind.collector),
      ]);
      expect(kRunOrder.toSet(), BatchKind.values.toSet());
    });

    for (final kind in [BatchKind.gpu, BatchKind.impeller]) {
      test('the ${kind.name} files are cut to the suites the line gives, as '
          'the crowd is — they are not one batch like the pins', () async {
        // Five minutes of work at one suite is one file; at two, the other
        // two. A tag a whole directory may come to carry
        // (impeller-sweep-canvas-reds) must not become one command.
        final tagged = {
          for (final name in ['a_test.dart', 'b_test.dart', 'c_test.dart'])
            name: "@Tags(['${kind.tag}'])\n",
        };
        final ran = await batchesOf(
          tagged,
          suites: const [1, 2],
          known: {for (final name in tagged.keys) name: 300000},
        );
        expect(
          [for (final (files, kind) in ran) (files.split(' ').length, kind)],
          [(1, kind), (2, kind)],
        );
      });
    }

    test('⚙️outside the line nothing decides between batches, so a batch is '
        'all that fits — a CI shard pays one start, not one per wall',
        () async {
      final plain = {
        for (final name in ['a_test.dart', 'b_test.dart', 'c_test.dart'])
          name: '',
      };
      final ran = await batchesOf(
        plain,
        suites: const [1],
        known: {for (final name in plain.keys) name: 300000},
        inTheLine: false,
      );
      expect(ran, [('a_test.dart b_test.dart c_test.dart', BatchKind.crowd)]);
    });
  });

  group('a tester that cannot make the context', () {
    // The line the engine's tester logs (shell/testing/tester_main.cc), as
    // `flutter test` hands it on.
    const said = 'Shell: [ERROR:flutter/shell/testing/tester_main.cc(329)] '
        'Could not create tester context.\n';

    test('is heard in the output — even when a chunk ends inside the line',
        () {
      expect(saysNoTesterContext('', said).said, isTrue);
      expect(saysNoTesterContext('', '00:01 +3: All tests passed!').said,
          isFalse);
      final cut = said.indexOf('tester context');
      final first = saysNoTesterContext('', said.substring(0, cut));
      expect(first.said, isFalse);
      expect(saysNoTesterContext(first.carry, said.substring(cut)).said,
          isTrue);
      expect(first.carry.length, lessThan(kNoTesterContext.length));
    });

    test('leaves its batch neither red nor green — but only a batch that '
        'failed', () {
      expect(ranNowhere(exitCode: 1, noContext: true), isTrue);
      expect(ranNowhere(exitCode: 1, noContext: false), isFalse);
      expect(ranNowhere(exitCode: 0, noContext: true), isFalse);
    });
  });

  test('each engine batch tells the engine what it needs — and no other '
      'batch tells it anything', () {
    List<String> asked(BatchKind kind) =>
        flutterTestArguments(['test/a_test.dart'], kind: kind);
    expect(asked(BatchKind.gpu), [
      'test',
      '--no-pub',
      '--enable-impeller',
      '--enable-flutter-gpu',
      'test/a_test.dart',
    ]);
    expect(asked(BatchKind.impeller), [
      'test',
      '--no-pub',
      '--enable-impeller',
      'test/a_test.dart',
    ]);
    for (final kind in [BatchKind.crowd, BatchKind.collector]) {
      expect(
        asked(kind),
        ['test', '--no-pub', 'test/a_test.dart'],
        reason: '$kind runs on the engine CI runs',
      );
    }
  });

  for (final tag in [gpuTag, impellerTag]) {
    test('the $tag tag is one the suite declares — and does not skip', () {
      final config = File('dart_test.yaml').readAsStringSync();
      expect(
        config,
        matches(RegExp('\\n  $tag:[ \\t]*\\r?\\n')),
        reason: "a file's @Tags names a tag; one dart_test.yaml does not "
            'declare is a warning in every run that loads the file',
      );
      expect(
        config,
        isNot(matches(RegExp('\\n  $tag:[ \\t]*\\r?\\n    skip:'))),
        reason: 'the tag says on what these run, not whether',
      );
    });
  }

  group('CI', () {
    test('🚨each shard runs its slice by the plan, outside the line, at the '
        'suites package:test gave it — in the step it already has', () {
      // ci-shards-crowd-the-collector-pins (10-24): one `flutter test` for
      // the slice put the collector's pins in the crowd and every file on
      // Skia, under a command-line limit copied from the plan. The
      // suspension of 2026-08-31 came from CI usage, and a job is usage.
      final shard = _read('.github/actions/test-shard/action.yml');
      expect(
        shard,
        contains('        half=\$(( cores / 2 ))\n'
            '        [ "\$half" -ge 1 ] || half=1\n'
            '        dart run tool/affected_tests.dart \\\n'
            '          --files-from "\$RUNNER_TEMP/shard_tests.txt" \\\n'
            '          --outside-the-line --concurrency "\$half"\n'),
      );
      expect(shard, isNot(contains('xargs -0 -s')));
    });

    test('⛔no step runs `flutter test` itself — every run goes by the '
        'plan', () {
      final runs = <String>[];
      for (final file in Directory('.github').listSync(recursive: true)) {
        if (file is! File) continue;
        final lines = file.readAsStringSync().replaceAll('\r\n', '\n');
        for (final line in lines.split('\n')) {
          final code = line.trimLeft();
          if (code.startsWith('#')) continue;
          if (RegExp(r'\bflutter test\b').hasMatch(code)) {
            runs.add('${file.path}: $code');
          }
        }
      }
      expect(runs, isEmpty);
    });

    test("the engine it builds says which C it came from — as lane.sh's "
        'do', () {
      // Without the stamp every run of the plan there said it could not
      // tell, and told the reader to rebuild with lane.sh.
      final engine = _read('.github/actions/native-engine/action.yml');
      expect(
        engine,
        contains(r'named=$(dart tool/native_engine_provenance.dart check . '
            '|| true)'),
      );
      expect(
        engine,
        contains(r'''printf '%s\n' "$id" > ''' '$engineStampPath'),
      );
    });
  });
}

/// A file as the repository holds it — a Windows checkout hands it back
/// with CRLF.
String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');
