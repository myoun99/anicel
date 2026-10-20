@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

import '../../tool/affected_tests.dart'
    show
        gcTag,
        gcTagMarker,
        kBatchWall,
        nextBatch,
        partitionByGcTag,
        runInBatches;

/// 🚨★★★**A PIN THAT WAITS FOR THE COLLECTOR CANNOT RUN IN A CROWD.**
///
/// `flutter test` runs a batch's files in concurrent isolates, and a full
/// collection under a hundred of them is scheduled when the machine gets
/// round to it. A pin that reads a [WeakReference] then gives up on a
/// bounded wait and reports what it sees — which under that load is 「still
/// alive」 for a holder that has already let go.
///
/// 🔬Measured on two different files: `tile_images_are_counted` lost one
/// tile's 64 bytes inside a parity batch and was green alone (2026-09-11),
/// and `a_parked_transform_lets_go_of_its_picture` went red in an 822-test
/// batch while green alone AND green across its own 476-test directory
/// (2026-09-18) — the second time blocking a landing.
///
/// ⛔**THE LEDGER IS THE POINT.** A rule the gate applies silently is one
/// nobody can see change, and this one moves coverage out of the main run:
/// so the files carrying the tag are named here, and adding one means
/// saying so.
void main() {
  group('the split', () {
    ({List<String> crowd, List<String> alone}) split(
      Map<String, String> tree,
    ) => partitionByGcTag(tree.keys.toList(), (path) => tree[path]!);

    test('a file carrying the marker goes alone', () {
      final result = split({
        'a_test.dart': 'void main() {}',
        'b_test.dart': '$gcTagMarker\nlibrary;\nvoid main() {}',
      });
      expect(result.alone, ['b_test.dart']);
      expect(result.crowd, ['a_test.dart']);
    });

    test('⛔and nothing else does — the marker is the whole rule', () {
      // A file that merely TALKS about the tag (this one does, and so does
      // the tool) must not be pulled out of the crowd by the word.
      final result = split({
        'a_test.dart': "// about ['gc'] tags, and about @Tags generally",
        'b_test.dart': "@Tags(['benchmark'])\nlibrary;",
      });
      expect(result.alone, isEmpty);
      expect(result.crowd, hasLength(2));
    });

    test('the order of the crowd is kept', () {
      final result = split({
        'a_test.dart': '',
        'b_test.dart': '$gcTagMarker\n',
        'c_test.dart': '',
      });
      expect(result.crowd, ['a_test.dart', 'c_test.dart']);
    });
  });

  group('the run', () {
    const tree = {
      'a_test.dart': 'void main() {}',
      'b_test.dart': '$gcTagMarker\nlibrary;\nvoid main() {}',
      'c_test.dart': 'void main() {}',
    };

    /// The batches a run of [files] makes, in order, as `(its files by a
    /// space, suites, pins)`, the line handing each batch [suites] in turn
    /// — and what each ask stood in line for.
    Future<(List<(String, int, bool)>, List<List<String>>)> batchesOf(
      List<String> files, {
      List<int> suites = const [5],
      Map<String, int> known = const {},
    }) async {
      final ran = <(String, int, bool)>[];
      final asked = <List<String>>[];
      var turn = 0;
      await runInBatches(
        files,
        known: known,
        // A file the tree does not hold is a plain one.
        read: (path) => tree[path] ?? '',
        take: (left) async {
          asked.add(left);
          return suites[turn++ % suites.length];
        },
        run: (batch, suites, {required pins}) async =>
            ran.add((batch.join(' '), suites, pins)),
      );
      return (ran, asked);
    }

    test('🚨a run splits by file: the pins alone and last, the rest in '
        'batches — the whole suite too, which names its files like any '
        'selection', () async {
      // 2026-09-23: a config change sent the gate to the whole suite, which
      // was one command with the pins in it — and the parked-transform pin
      // went red in that crowd for the third time.
      final (ran, _) = await batchesOf(tree.keys.toList());
      expect(ran, [
        ('a_test.dart c_test.dart', 5, false),
        ('b_test.dart', 5, true),
      ]);
    });

    test('⛔a selection of nothing but pins runs no crowd — an empty command '
        'is the whole suite', () async {
      final (ran, _) = await batchesOf(const ['b_test.dart']);
      expect(ran, [
        ('b_test.dart', 5, true),
      ]);
    });

    test('🚨each batch is cut to the suites the line gave it — five minutes '
        'of them — and stands in line for what is still to run', () async {
      // 유저 10-20: 「계속 10줄 중 … 6개만쓴다거나 이런거 안일어나게」. The
      // line hands a run what is left, so a batch cut before the run began
      // would hold two suites for as long as five were meant to.
      expect(kBatchWall, 300);
      final known = {
        for (final f in ['a_test.dart', 'c_test.dart', 'd_test.dart'])
          f: 300000,
      };
      final (ran, asked) = await batchesOf(
        const ['a_test.dart', 'c_test.dart', 'd_test.dart'],
        suites: const [1, 2],
        known: known,
      );
      // Five minutes at one suite is one of the three; at two, the other two.
      expect([
        for (final (files, suites, _) in ran) (files.split(' ').length, suites),
      ], [
        (1, 1),
        (2, 2),
      ]);
      expect(asked.map((left) => left.length), [3, 2]);
      expect(
        nextBatch(known.keys.toList(), known, suites: 10, fits: (_) => true),
        hasLength(3),
      );
    });

    test('the tag the pins carry is one the suite declares', () {
      expect(
        File('dart_test.yaml').readAsStringSync(),
        contains('\n  $gcTag:'),
        reason: "a file's @Tags names a tag; one dart_test.yaml does not "
            'declare is a warning in every run that loads the file',
      );
    });
  });

  test('🚨THE LEDGER: these are the files that wait for the collector', () {
    final root = Directory.current.path;
    final tagged = <String>[];
    for (final entity in dartFilesUnder('$root/test')) {
      if (!entity.path.endsWith('_test.dart')) continue;
      if (!entity.readAsStringSync().contains(gcTagMarker)) continue;
      tagged.add(
        entity.path.substring(root.length + 1).replaceAll(r'\', '/'),
      );
    }
    tagged.sort();
    expect(
      tagged,
      [
        'test/native/native_upload_cache_test.dart',
        'test/services/brush_stroke_accumulation_guard_test.dart',
        'test/ui/canvas/a_parked_transform_lets_go_of_its_picture_test.dart',
        'test/ui/canvas/tile_images_are_counted_test.dart',
        // I-57 ㉣ (10-13): a berth that leaves must let go of the row it
        // kept, and only the collector can say it did.
        'test/ui/timeline/a_berth_that_leaves_lets_go_of_its_row_test.dart',
      ],
      reason:
          'Adding the tag takes a file OUT of the main run — cheap to do by '
          'accident and invisible afterwards. If this list grew on purpose, '
          'say so here; if it grew because a pin was flaky for some other '
          "reason, the tag is the wrong fix and the flake's cause is the "
          'work.',
    );
  });
}
