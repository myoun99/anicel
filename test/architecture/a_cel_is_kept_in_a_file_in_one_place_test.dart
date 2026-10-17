import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/project_scratch_folder.dart';

/// 🚨**A TEST KEEPS A CEL IN A FILE THROUGH ONE HELPER** —
/// `keepInAFile` (`test/helpers/cels_kept_in_a_file.dart`).
///
/// Keeping a cel as an opened project keeps it — a stretch of a saved file,
/// cold until it is read — is one algorithm: the surface encoded, written
/// to a file, named by the ref its head reads into, handed to
/// `BrushFrameStore.restoreFromFile`. Thirteen tests wrote it, each with a
/// temp folder and a cleanup of its own (board
/// test-cels-kept-in-a-file-by-hand, 2026-10-16), and one of them read the
/// photo index off the head where the others named none.
///
/// ⛔**A test that measures the FILE ITSELF is not a copy**: refs at
/// offsets it chose, what a real save wrote and an open read back, an
/// empty open. Those call the store themselves, on purpose, and stand in
/// the ledger below with the reason and how many calls they make — a hand
/// copy added beside them is one more than the ledger says.
///
/// A behaviour test cannot hold this — every copy passes on its own — so the
/// ratchet is a source scan, and it proves it can see what it forbids.
void main() {
  /// ⚠️Exempt from its own scan: the files it plants are STRINGS holding
  /// the very call the scan counts.
  const itself =
      'test/architecture/a_cel_is_kept_in_a_file_in_one_place_test.dart';

  /// The files that call the store themselves, how many times, and why.
  const ledger = <String, (int, String)>{
    'test/helpers/cels_kept_in_a_file.dart': (1, 'the helper'),
    'test/services/a_moved_entry_takes_its_refs_along_test.dart': (
      3,
      'refs at offsets it chose, in a file that is never written — what it '
          'measures is where each stretch lies after a move',
    ),
    'test/services/brush_frame_store_400cut_test.dart': (
      1,
      'opens what a real save of 400 cels wrote',
    ),
    'test/services/brush_frame_store_tiering_test.dart': (
      5,
      'opens what real saves wrote (four), and an empty open that clears '
          'every tier (one)',
    ),
    // The save lane's (another machine's session) — read, not changed.
    'test/services/persistence/'
            'a_compacting_save_keeps_every_cel_readable_test.dart':
        (1, 'opens what a compacting save wrote'),
    'test/services/persistence/a_photo_index_survives_every_save_test.dart': (
      2,
      'opens what each save wrote',
    ),
    'test/services/persistence/anicel_recovery_test.dart': (
      1,
      'opens what a recovery wrote',
    ),
    'test/services/persistence/the_project_file_disappeared_test.dart': (
      1,
      'an empty open that clears every tier',
    ),
  };

  /// How many times each file under [root] — itself a folder named `test` —
  /// calls the store's file entrance, for the files that do, by their path
  /// from `test/` on.
  ///
  /// ⛔THE WALK IS NOT WRITTEN HERE: `dartFilesUnder` is the one walk every
  /// source scan asks, and it fails on a folder that is not there.
  Map<String, int> callsUnder(String root) {
    final from = root.replaceAll(r'\', '/').length + 1;
    final calls = <String, int>{};
    for (final file in dartFilesUnder(root)) {
      final path = 'test/${file.path.replaceAll(r'\', '/').substring(from)}';
      if (path == itself) {
        continue;
      }
      final count = 'restoreFromFile('.allMatches(
        file.readAsStringSync(),
      ).length;
      if (count > 0) {
        calls[path] = count;
      }
    }
    return calls;
  }

  /// The files of [calls] that call the store more often than [allowed]
  /// says they may.
  List<String> overTheLedger(
    Map<String, int> calls,
    Map<String, (int, String)> allowed,
  ) => [
    for (final MapEntry(key: path, value: count) in calls.entries)
      if (count > (allowed[path]?.$1 ?? 0)) '$path ($count)',
  ]..sort();

  test('a test keeps a cel in a file through keepInAFile, or the ledger '
      'says why it calls the store itself', () {
    expect(
      overTheLedger(callsUnder('test'), ledger),
      isEmpty,
      reason:
          'keep the cel with keepInAFile(store, {key: surface}) — it '
          'answers the refs, for a test that needs where a cel is kept',
    );
  });

  test('the ledger is exact: every file it names calls the store as many '
      'times as it says', () {
    final calls = callsUnder('test');
    expect(
      {for (final path in ledger.keys) path: calls[path] ?? 0},
      {
        for (final MapEntry(key: path, value: (count, _)) in ledger.entries)
          path: count,
      },
      reason: 'a call that went to the helper takes its line out of the '
          'ledger, so the ceiling never stands above what is there',
    );
  });

  test('the scan sees what it forbids, and lets through only what the '
      'ledger counts', () {
    final planted = Directory.systemTemp.createTempSync('kept-cel-ratchet');
    deleteAfterSessionEnds(planted);
    final folder = Directory('${planted.path}/test')..createSync();
    File('${folder.path}/kept_test.dart').writeAsStringSync(
      'void main() {\n'
      '  keepInAFile(store, {key: surface});\n'
      '}\n',
    );
    File('${folder.path}/by_hand_test.dart').writeAsStringSync(
      'void main() {\n'
      '  store.restoreFromFile({key: ref});\n'
      '  other.restoreFromFile(const {});\n'
      '}\n',
    );

    final calls = callsUnder(folder.path);
    expect(calls, {'test/by_hand_test.dart': 2});
    expect(
      overTheLedger(calls, const {}),
      ['test/by_hand_test.dart (2)'],
      reason: 'the scan reads files and counts the call, so an empty answer '
          'above means there is none',
    );
    expect(
      overTheLedger(calls, const {'test/by_hand_test.dart': (1, 'one')}),
      ['test/by_hand_test.dart (2)'],
      reason: 'a copy beside a counted call is one more than the ledger says',
    );
    expect(
      overTheLedger(calls, const {'test/by_hand_test.dart': (2, 'two')}),
      isEmpty,
    );
  });
}
