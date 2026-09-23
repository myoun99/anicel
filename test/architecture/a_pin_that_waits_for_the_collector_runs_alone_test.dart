@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/affected_tests.dart'
    show gcTag, gcTagMarker, partitionByGcTag, runPlan;

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

  group('the plan', () {
    ({List<List<String>> crowd, List<String> alone}) plan(
      List<String> selected,
      Map<String, String> tree,
    ) => runPlan(
      selected: selected,
      suite: tree.keys.toList(),
      read: (path) => tree[path]!,
      // One command per file, so a test can see what went where.
      batches: (files) => [for (final file in files) [file]],
    );

    const tree = {
      'a_test.dart': 'void main() {}',
      'b_test.dart': '$gcTagMarker\nlibrary;\nvoid main() {}',
    };

    test('🚨the WHOLE suite sends its collector pins alone too', () {
      // 2026-09-23: a config change sent the gate to the whole suite, which
      // was one command with the pins in it — and the parked-transform pin
      // went red in that crowd for the third time.
      final result = plan(const [], tree);
      expect(result.crowd, [
        ['--exclude-tags', gcTag],
      ]);
      expect(result.alone, ['b_test.dart']);
    });

    test('a whole suite with no pin in it is one plain command', () {
      final result = plan(const [], {'a_test.dart': ''});
      expect(result.crowd, [<String>[]]);
      expect(result.alone, isEmpty);
    });

    test('a selection splits the same way, by file', () {
      final result = plan(const ['a_test.dart', 'b_test.dart'], tree);
      expect(result.crowd, [
        ['a_test.dart'],
      ]);
      expect(result.alone, ['b_test.dart']);
    });

    test('⛔a selection of nothing but pins runs no crowd — an empty command '
        'is the whole suite', () {
      final result = runPlan(
        selected: const ['b_test.dart'],
        suite: const [],
        read: (path) => tree[path]!,
        // What `_batches` does off Windows: the list, whole, as one batch.
        batches: (files) => [files],
      );
      expect(result.crowd, isEmpty);
      expect(result.alone, ['b_test.dart']);
    });

    test('the tag the crowd leaves out is one the suite declares', () {
      expect(
        File('dart_test.yaml').readAsStringSync(),
        contains('\n  $gcTag:'),
        reason: '--exclude-tags names a tag; one dart_test.yaml does not '
            'declare would leave every pin in the crowd without a word',
      );
    });
  });

  test('🚨THE LEDGER: these are the files that wait for the collector', () {
    final root = Directory.current.path;
    final tagged = <String>[];
    for (final entity in Directory('$root/test').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('_test.dart')) continue;
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
