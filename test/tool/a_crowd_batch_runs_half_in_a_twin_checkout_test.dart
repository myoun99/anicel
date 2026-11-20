@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/affected_tests.dart'
    show
        BatchKind,
        gcTagMarker,
        gpuTagMarker,
        impellerTagMarker,
        realtimeTagMarker,
        runInBatches,
        twinRefusal;

/// 🆕2026-11-20 (card the-wide-check-takes-five-hours, 유저 「최대한
/// 줄이고싶어」): `flutter test` compiles one file at a time, and the wide
/// check's light files ran at that one compiler's pace. Another checkout
/// of the same commit runs half of each crowd batch beside it, with a
/// compiler of its own — 251 s as one run, 188 · 203 s as two, on 200
/// light files at eight suites.
void main() {
  // Five minutes of work a file: a batch at n suites holds about n files.
  const fiveMinutes = 300000;

  /// What a run of [files] did, in order — `take`, `put down`, and each
  /// batch as `<here|twin> <kind> @<suites>` when it starts and
  /// `<here|twin> ended` when it ends — and the files each side ran.
  Future<({List<String> events, List<String> here, List<String> twin})>
  runOf(
    List<String> files, {
    required List<int> suites,
    bool withTwin = true,
    Map<String, String> tree = const {},
    bool hereThrows = false,
  }) async {
    final events = <String>[];
    final ran = {'here': <String>[], 'twin': <String>[]};
    var turn = 0;
    Future<void> Function(List<String>, int, {required BatchKind kind})
    side(String where) => (batch, suites, {required kind}) async {
      events.add('$where ${kind.name} @$suites');
      ran[where]!.addAll(batch);
      await Future<void>.delayed(Duration.zero);
      events.add('$where ended');
      if (hereThrows && where == 'here') throw StateError('red launch');
    };
    try {
      await runInBatches(
        files,
        known: {for (final file in files) file: fiveMinutes},
        inTheLine: true,
        read: (path) => tree[path] ?? '',
        take: (left) async {
          events.add('take');
          return suites[turn++ % suites.length];
        },
        run: side('here'),
        runInTwin: withTwin ? side('twin') : null,
        putDown: () => events.add('put down'),
      );
    } on StateError {
      events.add('threw');
    }
    return (events: events, here: ran['here']!, twin: ran['twin']!);
  }

  List<String> named(String prefix, int count) => [
    for (var i = 0; i < count; i++) '${prefix}_${i}_test.dart',
  ];

  group('a crowd take, given a twin', () {
    test('is cut in two at half its suites each; the halves run at once, '
        'and the suites go back once both have ended', () async {
      final files = named('a', 8);
      final run = await runOf(files, suites: const [4]);
      expect(run.events, [
        for (var round = 0; round < 2; round++) ...[
          'take',
          'here crowd @2',
          'twin crowd @2',
          'here ended',
          'twin ended',
          'put down',
        ],
      ]);
      expect([...run.here, ...run.twin]..sort(), files);
      expect(run.here.toSet().intersection(run.twin.toSet()), isEmpty);
    });

    test('an odd take keeps the larger half here', () async {
      final run = await runOf(named('b', 10), suites: const [5]);
      expect(run.events.take(6), [
        'take',
        'here crowd @3',
        'twin crowd @2',
        'here ended',
        'twin ended',
        'put down',
      ]);
    });

    test('when the half here holds every file left, nothing runs beside it '
        'and it keeps the whole take', () async {
      final run = await runOf(named('c', 2), suites: const [8]);
      expect(run.events, [
        'take',
        'here crowd @8',
        'here ended',
        'put down',
      ]);
      expect(run.twin, isEmpty);
    });

    test('a take of one suite cannot be halved', () async {
      final run = await runOf(named('d', 3), suites: const [1]);
      expect(run.twin, isEmpty);
      expect(run.here, hasLength(3));
    });

    test('a batch that throws still hands its suites back — after its twin '
        'has ended', () async {
      final run = await runOf(
        named('e', 8),
        suites: const [4],
        hereThrows: true,
      );
      expect(run.events, [
        'take',
        'here crowd @2',
        'twin crowd @2',
        'here ended',
        'twin ended',
        'put down',
        'threw',
      ]);
    });
  });

  test('the batches that run apart are never paired — what they are apart '
      'from is company', () async {
    final tree = {
      for (final file in named('gc', 6)) file: gcTagMarker,
      for (final file in named('gpu', 6)) file: gpuTagMarker,
      for (final file in named('imp', 6)) file: impellerTagMarker,
      for (final file in named('rt', 2)) file: realtimeTagMarker,
    };
    final run = await runOf(
      tree.keys.toList(),
      suites: const [8],
      tree: tree,
    );
    expect(run.twin, isEmpty);
    expect(run.here, hasLength(tree.length));
  });

  test('given no twin, a take runs as one batch, as before', () async {
    final run = await runOf(named('f', 8), suites: const [4], withTwin: false);
    expect(run.events, [
      for (var round = 0; round < 2; round++) ...[
        'take',
        'here crowd @4',
        'here ended',
        'put down',
      ],
    ]);
  });

  group('a checkout is a twin', () {
    const head = 'c0ffee';
    String? refusal({
      String? there = '/b',
      String? hereHead = head,
      String? thereHead = head,
      bool hereClean = true,
      bool thereClean = true,
    }) => twinRefusal(
      here: '/a',
      there: there,
      hereHead: hereHead,
      thereHead: thereHead,
      hereClean: hereClean,
      thereClean: thereClean,
    );

    test('when it is another checkout at this commit, neither holding a '
        'change nobody committed', () {
      expect(refusal(), isNull);
    });

    test('and not otherwise — what it finds green is kept as this '
        "checkout's", () {
      expect(refusal(there: null), 'it is not a git checkout');
      expect(refusal(there: '/a'), 'it is this checkout');
      expect(
        refusal(thereHead: 'decade'),
        'it is at decade, this checkout at c0ffee',
      );
      expect(refusal(hereHead: null), contains('(no commit)'));
      expect(
        refusal(hereClean: false),
        'this checkout holds changes nobody committed',
      );
      expect(refusal(thereClean: false), 'it holds changes nobody committed');
    });
  });

  test('the twin runs in its own checkout, and its reports are read from '
      'there — where each is said', () {
    // The halves above are what is run; this is that the second runs, and
    // is read, where it is.
    final source = File('tool/affected_tests.dart').readAsStringSync();
    expect(source, contains('final twin = twinAsked == null ? null : '
        '_twinAt(twinAsked);'));
    expect(source, contains('launch(batch, suites, kind, checkout: twin)'));
    expect(source, contains('RunTemp.take(where: checkout)'));
    expect(source, contains('workingDirectory: checkout,'));
    expect(
      source,
      contains('record(i, report, result, checkout ?? '
          'Directory.current.path)'),
    );
    expect(
      source,
      contains('runsOf[i] = _recordBatch(report, cache, root: root);'),
    );
    expect(source, contains('slow.addAll(_slowIn(report, root: root));'));
    expect(
      source,
      contains('again.addAll(_recordBatch(report, null, root: root));'),
    );
    // The wide run is given the twin lane, at the commit it checks; the
    // walk back runs one compiler.
    final check = File('tool/master_check.dart').readAsStringSync();
    expect(
      check,
      contains('final twin = await _laneAt(root, head, name: kTwinLane);'),
    );
    expect(
      check.replaceAll('\r\n', '\n'),
      contains("    checked,\n    '--twin',\n    twin,\n"),
    );
    expect(check, contains('final at = await _laneAt(root, landings[i].sha);'));
  });
}
