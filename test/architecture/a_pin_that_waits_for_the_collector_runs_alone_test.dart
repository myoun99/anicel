@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

import '../../tool/affected_tests.dart'
    show
        BatchKind,
        carriesTag,
        filesListed,
        gcTag,
        gcTagMarker,
        kBatchWall,
        lineFor,
        nextBatch,
        partitionByTag,
        runInBatches;
import '../../tool/master_check.dart' show kWideCheckStandsFirst;
import '../../tool/test_queue.dart' show kMachineSuites, outsideTheLine;

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
    ) {
      final kinds = partitionByTag(tree.keys.toList(), (path) => tree[path]!);
      return (
        crowd: kinds[BatchKind.crowd]!,
        alone: kinds[BatchKind.collector]!,
      );
    }

    test('a file carrying the marker goes alone', () {
      final result = split({
        'a_test.dart': 'void main() {}',
        'b_test.dart': '$gcTagMarker\nlibrary;\nvoid main() {}',
      });
      expect(result.alone, ['b_test.dart']);
      expect(result.crowd, ['a_test.dart']);
    });

    test('so does one listing the tag beside another — a file has one '
        '@Tags', () {
      final result = split({
        'a_test.dart': "@Tags(['slow', '$gcTag'])\nlibrary;",
      });
      expect(result.alone, ['a_test.dart']);
    });

    test('⛔and nothing else does — the annotation is the whole rule', () {
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
        inTheLine: true,
        // A file the tree does not hold is a plain one.
        read: (path) => tree[path] ?? '',
        take: (left) async {
          asked.add(left);
          return suites[turn++ % suites.length];
        },
        run: (batch, suites, {required kind}) async =>
            ran.add((batch.join(' '), suites, kind == BatchKind.collector)),
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
        nextBatch(
          known.keys.toList(),
          known,
          suites: 10,
          inTheLine: true,
          fits: (_) => true,
        ),
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

  /// parity-runs-crowd-the-collector-pins (10-17): the native parity list
  /// carries two of these pins, and the four places that run it each ran it
  /// as one `xargs flutter test`. They hand it to the plan instead.
  group('a list run (--files-from)', () {
    test('names its files in order, a blank line and a CR left out', () {
      final asked = filesListed(
        'a_test.dart\r\n\r\nb_test.dart\n',
        exists: (_) => true,
      );
      expect(asked.refusal, isNull);
      expect(asked.files, ['a_test.dart', 'b_test.dart']);
    });

    test('⛔a list naming nothing is refused — an empty run is the whole '
        'suite', () {
      final asked = filesListed('\n \r\n', exists: (_) => true);
      expect(asked.refusal, isNotNull);
      expect(asked.files, isEmpty);
    });

    test('so is a list that is not there, and one naming a file that is '
        'not — before anything runs', () {
      expect(filesListed(null, exists: (_) => true).refusal, isNotNull);
      final asked = filesListed(
        'a_test.dart\nb_test.dart\n',
        exists: (path) => path == 'a_test.dart',
      );
      expect(asked.refusal, contains('b_test.dart'));
      expect(asked.files, isEmpty);
    });

    test('🚨every place that runs the parity list runs it by the plan', () {
      // ↩️`lane.sh` was the fifth, naming the runner beside itself through
      // tool/run.sh, till its native gate went with the C (2026-11-13).
      final byThePlan = RegExp(r'affected_tests(\.dart"?)?[\s\\]+--files-from');
      final places = <String>[];
      for (final dir in ['tool', '.github', '.githooks']) {
        for (final file in filesUnder(dir)) {
          // Latin-1 reads any byte, and all that is looked for is ASCII.
          final text = file.readAsStringSync(encoding: latin1);
          if (!text.contains('bash tool/native_parity_tests.sh')) continue;
          final path = file.path.replaceAll(r'\', '/');
          places.add(path);
          expect(
            text,
            matches(byThePlan),
            reason: '$path runs the parity list — through the plan',
          );
          expect(
            text,
            isNot(contains('xargs flutter test')),
            reason: '$path: one `flutter test` puts the collector pins in '
                'the crowd',
          );
        }
      }
      places.sort();
      expect(places, [
        '.github/workflows/linux-release.yml',
        '.github/workflows/macos-developer-id.yml',
        '.github/workflows/testflight.yml',
        '.github/workflows/windows-arm64-release.yml',
      ]);
    });

    test("a list run asked outside the machine's line takes no place in it "
        '— asked alone, it stands in the line', () {
      expect(lineFor(['--files-from', 'parity.txt']).inTheLine, isTrue);
      final shard = lineFor([
        '--files-from',
        'parity.txt',
        '--outside-the-line',
      ]);
      expect(shard.inTheLine, isFalse);
      expect(shard.refusal, isNull);
    });

    test("🗣️the build's wide check stands at the head of the line — every "
        'run master_check makes says so, and no other run does', () {
      // 유저 10-22, tests-crowd-the-machine-Q18 「맨 앞에 세우고, 칸 몫은 지금
      // 법대로」.
      expect(lineFor([kWideCheckStandsFirst, '--wide']).first, isTrue);
      expect(lineFor(['--wide']).first, isFalse);
      expect(lineFor(const []).first, isFalse);
      final check = File('tool/master_check.dart').readAsStringSync();
      expect(
        RegExp("'affected_tests'").allMatches(check),
        hasLength(1),
        reason: 'master_check runs affected_tests in one place',
      );
      expect(
        check,
        matches(RegExp(r"'affected_tests',\s*kWideCheckStandsFirst,")),
      );
    });

    test('⛔any other run asked outside the line is refused — it is a '
        "session's, and stands in it", () {
      expect(lineFor(const []).inTheLine, isTrue);
      final asked = lineFor(['--base', 'master', '--outside-the-line']);
      expect(asked.refusal, contains('--files-from'));
    });

    test('outside the line, a run holds what it asked at once — as on a '
        'machine with no line', () async {
      expect(await outsideTheLine('gates', (turn) => turn.take(files: 3)), 3);
      expect(
        await outsideTheLine('gates', (turn) => turn.take(), asked: 4),
        4,
      );
      expect(
        await outsideTheLine('gates', (turn) => turn.take()),
        kMachineSuites,
      );
    });
  });

  test('🚨THE LEDGER: these are the files that wait for the collector', () {
    final root = Directory.current.path;
    final tagged = <String>[];
    for (final entity in dartFilesUnder('$root/test')) {
      if (!entity.path.endsWith('_test.dart')) continue;
      if (!carriesTag(entity.readAsStringSync(), gcTag)) continue;
      tagged.add(
        entity.path.substring(root.length + 1).replaceAll(r'\', '/'),
      );
    }
    expectSetMatchesLedger(
      tagged,
      const [
        'test/services/brush_stroke_accumulation_guard_test.dart',
        'test/ui/canvas/a_parked_transform_lets_go_of_its_picture_test.dart',
        'test/ui/canvas/tile_images_are_counted_test.dart',
        // F-505 (10-30): what a closed project's tiles give back reaches the
        // engine's parking only when the collector finds them.
        'test/ui/a_closed_project_lets_go_of_its_memory_test.dart',
        // I-57 ㉣ (10-13): a berth that leaves must let go of the row it
        // kept, and only the collector can say it did.
        'test/ui/timeline/a_berth_that_leaves_lets_go_of_its_row_test.dart',
        // screen-on-the-engine c4 (11-08): an engine slot goes with its
        // tile, and only the collector can say it did. The ledger's other
        // pins stay in the crowd, in a file of their own.
        'test/native/a_tile_collected_lets_its_engine_slot_go_test.dart',
        // pool-pages-given-back (11-08): a page goes back once its tiles
        // are collected, and only the collector can say they were.
        'test/native/the_engine_gives_back_the_pages_nobody_holds_test.dart',
        // a-lost-gpu-device-keeps-the-unsaved-tiles (B, 11-11): a landed
        // tile lets go of the tile it landed on once its copy is here, and
        // only the collector can say it did.
        'test/native/a_landed_tile_lets_go_of_the_tile_under_it_test.dart',
        // a-lifted-row-painter-holds-a-reclaimed-hole (11-12): a lifted row's
        // painter lets go of the hole a memory warning took, and the picture
        // cannot say so — it draws the same pixels either way.
        'test/ui/canvas/a_lifted_row_lets_go_of_a_hole_a_warning_took_test.dart',
        // tile-blocks-on-rust (11-12): a tile's block goes back to the
        // lists by its finalizer alone, and only the collector runs it.
        'test/models/a_collected_tile_gives_its_block_back_test.dart',
        // selection-mask-on-the-engine (11-14): a selection's mask goes with
        // the clip that asked for it by its finalizer alone, and only the
        // collector runs it.
        'test/native/a_selection_mask_goes_with_its_clip_test.dart',
      ],
      unledgered:
          'Adding the tag takes a file OUT of the main run — cheap to do by '
          'accident and invisible afterwards. If this list grew on purpose, '
          'say so here; if it grew because a pin was flaky for some other '
          "reason, the tag is the wrong fix and the flake's cause is the "
          'work.',
      paidOff:
          'These no longer carry the tag (or are gone) and run in the crowd '
          'again — take them off the list here.',
    );
  });
}
