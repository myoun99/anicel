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
        partitionByTag,
        runInBatches;

/// 🖥️**A FILE THAT DRAWS WITH FLUTTER GPU RUNS ON IMPELLER, APART.**
///
/// gpu-pins-run-in-a-batch-of-their-own (2026-10-24): `flutter_gpu` is
/// Impeller's alone, and a plain `flutter test` runs the Skia tester — so a
/// pin that draws with it can only skip there. `--enable-impeller
/// --enable-flutter-gpu` gives it a context, and changes the engine for
/// every file in the command: the rest of the suite measures what Skia
/// draws, so the files carrying the tag run in batches of their own —
/// locally ([runInBatches]) and in each CI shard alike.
///
/// ⚠️This file never writes the marker out whole: a file that holds it IS
/// a gpu file, to the split here and to CI's.
void main() {
  test('a file carrying the marker goes to the gpu files — not the crowd, '
      'not the pins', () {
    const tree = {
      'a_test.dart': 'void main() {}',
      'b_test.dart': '$gpuTagMarker\nlibrary;\nvoid main() {}',
      'c_test.dart': '$gcTagMarker\nlibrary;\nvoid main() {}',
    };
    final split = partitionByTag(tree.keys.toList(), (path) => tree[path]!);
    expect(split.crowd, ['a_test.dart']);
    expect(split.gpu, ['b_test.dart']);
    expect(split.alone, ['c_test.dart']);
  });

  test('🚨a file listing both tags is a gpu file — a file has one @Tags, '
      'and without the flags it cannot run at all', () {
    final tree = {
      'a_test.dart': "@Tags(['$gcTag', '$gpuTag'])\nlibrary;",
      'b_test.dart': "@Tags(['$gpuTag', '$gcTag'])\nlibrary;",
      'c_test.dart': "// about '$gpuTag', and @Tags(['benchmark'])",
    };
    final split = partitionByTag(tree.keys.toList(), (path) => tree[path]!);
    expect(split.gpu, ['a_test.dart', 'b_test.dart']);
    expect(split.alone, isEmpty);
    expect(split.crowd, ['c_test.dart']);
  });

  group('the run', () {
    /// The batches a run of [tree] makes, in order, as `(its files by a
    /// space, kind)`, the line handing each batch [suites] in turn.
    Future<List<(String, BatchKind)>> batchesOf(
      Map<String, String> tree, {
      List<int> suites = const [5],
      Map<String, int> known = const {},
    }) async {
      final ran = <(String, BatchKind)>[];
      var turn = 0;
      await runInBatches(
        tree.keys.toList(),
        known: known,
        read: (path) => tree[path]!,
        take: (left) async => suites[turn++ % suites.length],
        run: (batch, suites, {required kind}) async =>
            ran.add((batch.join(' '), kind)),
      );
      return ran;
    }

    test('the crowd first, then the gpu files on their engine, then the '
        'collector pins — still last', () async {
      final ran = await batchesOf({
        'a_test.dart': '',
        'b_test.dart': '$gpuTagMarker\n',
        'c_test.dart': '$gcTagMarker\n',
        'd_test.dart': '',
      });
      expect(ran, [
        ('a_test.dart d_test.dart', BatchKind.crowd),
        ('b_test.dart', BatchKind.gpu),
        ('c_test.dart', BatchKind.collector),
      ]);
    });

    test('the gpu files are cut to the suites the line gives, as the crowd '
        'is — they are not one batch like the pins', () async {
      // Five minutes of work at one suite is one file; at two, the other
      // two. A tag a whole directory may come to carry
      // (impeller-sweep-canvas-reds) must not become one command.
      final gpu = {
        for (final name in ['a_test.dart', 'b_test.dart', 'c_test.dart'])
          name: '$gpuTagMarker\n',
      };
      final ran = await batchesOf(
        gpu,
        suites: const [1, 2],
        known: {for (final name in gpu.keys) name: 300000},
      );
      expect(
        [for (final (files, kind) in ran) (files.split(' ').length, kind)],
        [(1, BatchKind.gpu), (2, BatchKind.gpu)],
      );
    });
  });

  test('the gpu batch tells the engine — and no other batch does', () {
    expect(
      flutterTestArguments(['test/a_test.dart'], kind: BatchKind.gpu),
      [
        'test',
        '--no-pub',
        '--enable-impeller',
        '--enable-flutter-gpu',
        'test/a_test.dart',
      ],
    );
    for (final kind in [BatchKind.crowd, BatchKind.collector]) {
      expect(
        flutterTestArguments(['test/a_test.dart'], kind: kind),
        ['test', '--no-pub', 'test/a_test.dart'],
        reason: '$kind runs on the engine CI runs',
      );
    }
  });

  test('the tag is one the suite declares — and does not skip', () {
    final config = File('dart_test.yaml').readAsStringSync();
    expect(
      config,
      matches(RegExp('\\n  $gpuTag:[ \\t]*\\r?\\n')),
      reason: "a file's @Tags names a tag; one dart_test.yaml does not "
          'declare is a warning in every run that loads the file',
    );
    expect(
      config,
      isNot(matches(RegExp('\\n  $gpuTag:[ \\t]*\\r?\\n    skip:'))),
      reason: 'the tag says on what these run, not whether',
    );
  });

  test('🚨each CI shard splits its files the same way — the same marker, '
      'the same flags, in the step it already has', () {
    // The suspension of 2026-08-31 came from CI usage, and a job is usage:
    // the split lives in the shard's own step.
    final shard = _shardStep();
    // carriesTag's expression, as awk writes it inside a shell string.
    expect(
      shard,
      contains(r'xargs -0 awk "/@Tags\\(\\[[^]]*' "'$gpuTag'" '/ {'),
    );
    expect(
      shard,
      contains(
        'flutter test --no-pub ${BatchKind.gpu.engineFlags.join(' ')}',
      ),
    );
    expect(
      shard,
      contains('"\$RUNNER_TEMP/shard_rest.txt" \\\n'
          '            | xargs -0 -s "\$limit" flutter test --no-pub\n'),
      reason: 'the rest of the shard runs without the flags',
    );
    expect(
      shard,
      isNot(contains('"\$RUNNER_TEMP/shard_tests.txt" \\\n'
          '            | xargs -0 -s "\$limit" flutter test')),
      reason: 'a run of the whole slice would put the gpu files on Skia',
    );
  });

  test('⛔in CI, only a runner the tester cannot make a context on goes '
      'green without them — and says so', () {
    final shard = _shardStep();
    expect(shard, contains("grep -q 'Could not create tester context'"));
    expect(shard, contains('echo "::notice title=Flutter GPU files not run'));
    expect(shard, contains('exit "\$gpu_exit"'));
  });
}

/// The shard action as the repository holds it — a Windows checkout hands
/// it back with CRLF.
String _shardStep() => File(
  '.github/actions/test-shard/action.yml',
).readAsStringSync().replaceAll('\r\n', '\n');
