import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/project_scratch_folder.dart';
import '../helpers/temp_dir.dart';

/// 🚨**A RECURSIVE DELETE IN `test/` LIVES IN ONE OF TWO SEATS.**
///
/// Cleaning a temp directory is not a test's result: on Windows a handle
/// outlives the last write and the delete throws `errno 32`, which cost a
/// whole affected batch on 2026-09-16 in a test unrelated to the round that
/// was gating. The suite wrote that delete by hand in 167 places
/// (2026-09-23).
///
/// The two seats are not interchangeable, which is why there are two:
///  · `temp_dir.dart`'s `deleteTempQuietly` attempts the delete and swallows
///    only the FAILURE — for a cleanup registered as a group `tearDown`,
///    where `flutter_test_config.dart` has already released the project
///    file by the time it runs.
///  · `project_scratch_folder.dart`'s `deleteAfterSessionEnds` ends that
///    hold ITSELF and then calls the same body — for a cleanup registered
///    with `addTearDown`, from a test body or a `setUp` alike, which runs
///    before the corpus-wide release and so cannot wait for it.
///
/// ⛔**Creating a temp directory is NOT what this holds.** `createTemp` in a
/// test is fine and needs no entrance of its own; inventing one would be a
/// third way to say what these two already say.
///
/// A behaviour test cannot hold this — every copy passes on its own — so the
/// ratchet is a source scan, and an absence cannot be mutated, so each scan
/// proves it can SEE what it forbids before it reports finding none.
void main() {
  /// ⚠️This file is exempt from its own scans: the files it plants are
  /// STRINGS holding the very patterns the scans match, so a file that
  /// proves the scans work must contain what they forbid.
  const itself =
      'test/architecture/a_temp_dir_cleans_itself_up_in_one_place_test.dart';

  /// ⚠️**Premises, not cleanups** — each removes a folder AS the situation
  /// the test is about, and a delete that failed quietly would be a premise
  /// that silently did not hold. Named by the LINE, not the file, so a
  /// cleanup written by hand elsewhere in the same file is still caught.
  const premises = <String, String>{
    // The suite is ABOUT sweeping the rooms of runs that ended: its setUp
    // empties the room to state the starting position.
    'test/services/persistence/a_run_that_ended_leaves_its_room_test.dart':
        'root().deleteSync(recursive: true);',
    // A FILE goes where the room's folder has to be — the shape of a revoked
    // scope or a full disk — so the folder has to be gone first.
    'test/services/a_cooled_cel_parks_on_disk_test.dart':
        'room.deleteSync(recursive: true);',
    // The stand-in coordinator replaces the destination whole, as the native
    // one does; a quiet failure would be a replace that did not happen.
    'test/ui/coordinated_replace_fallback_test.dart':
        'blocking.deleteSync(recursive: true);',
  };

  bool deletesByHand(String line) =>
      line.contains('delete(recursive: true)') ||
      line.contains('deleteSync(recursive: true)');

  String slashed(File file) => file.path.replaceAll(r'\', '/');

  /// Every hand-written recursive delete under [root], as `path:line`.
  ///
  /// ⛔THE WALK IS NOT WRITTEN HERE. `dartFilesUnder` is the one walk every
  /// source scan asks, and it FAILS on a folder that does not exist rather
  /// than quietly measuring nothing.
  List<String> handDeletes(
    String root, {
    Map<String, String> allowed = const {},
  }) {
    final offenders = <String>[];
    for (final file in dartFilesUnder(root)) {
      final path = slashed(file);
      if (path.endsWith(itself) || path.endsWith(_quietSeat)) {
        continue;
      }
      final premise = [
        for (final entry in allowed.entries)
          if (path.endsWith(entry.key)) entry.value,
      ];
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        final line = lines[index];
        if (deletesByHand(line) && !premise.contains(line.trim())) {
          offenders.add('$path:${index + 1}');
        }
      }
    }
    return offenders..sort();
  }

  /// The callbacks handed to `addTearDown` in [source], balanced on
  /// parentheses. ⚠️A parenthesis inside a string in the callback would
  /// throw the balance off; none does, and that failure is loud — it reports
  /// a file that is innocent, never passes one that is not.
  Iterable<String> addTearDownCallbacks(String source) sync* {
    const opener = 'addTearDown(';
    var from = 0;
    while (true) {
      final start = source.indexOf(opener, from);
      if (start < 0) {
        return;
      }
      var depth = 1;
      var index = start + opener.length;
      while (index < source.length && depth > 0) {
        if (source[index] == '(') depth += 1;
        if (source[index] == ')') depth -= 1;
        index += 1;
      }
      yield source.substring(start, index);
      from = index;
    }
  }

  /// Every file under [root] that hands `deleteTempQuietly` to
  /// `addTearDown`, where it runs before the project file is let go.
  List<String> quietDeletesTooEarly(String root) {
    final offenders = <String>[];
    for (final file in dartFilesUnder(root)) {
      final path = slashed(file);
      if (path.endsWith(itself) || path.endsWith(_releasingSeat)) {
        continue;
      }
      final callbacks = addTearDownCallbacks(file.readAsStringSync());
      if (callbacks.any((it) => it.contains('deleteTempQuietly('))) {
        offenders.add(path);
      }
    }
    return offenders..sort();
  }

  test('every recursive delete in test/ sits in one of the two seats', () {
    expect(
      handDeletes('test', allowed: premises),
      isEmpty,
      reason:
          'ask deleteTempQuietly(dir) from a group tearDown, or '
          'deleteAfterSessionEnds(dir) where it would be an addTearDown',
    );
  });

  test('an addTearDown cleanup is deleteAfterSessionEnds, never the bare '
      'quiet delete', () {
    expect(
      quietDeletesTooEarly('test'),
      isEmpty,
      reason:
          'addTearDown runs before the corpus-wide release, so the project '
          'file still holds the folder: deleteAfterSessionEnds(dir) lets it '
          'go first',
    );
  });

  test('each scan sees what it forbids, and lets through only the premise '
      'line it was told about', () {
    final planted = Directory.systemTemp.createTempSync('temp-dir-ratchet');
    deleteAfterSessionEnds(planted);
    File('${planted.path}/innocent_test.dart').writeAsStringSync(
      'void main() {\n'
      '  tearDown(() => deleteTempQuietly(dir));\n'
      '  addTearDown(session.dispose);\n'
      '}\n',
    );
    File('${planted.path}/remnant_test.dart').writeAsStringSync(
      'void main() {\n'
      '  room.deleteSync(recursive: true);\n'
      '  Directory("x").deleteSync(recursive: true);\n'
      '  addTearDown(() => deleteTempQuietly(dir));\n'
      '}\n',
    );

    expect(
      handDeletes(
        planted.path,
        allowed: {'remnant_test.dart': 'room.deleteSync(recursive: true);'},
      ),
      [endsWith('/remnant_test.dart:3')],
      reason: 'the scan reads files and matches the delete, so an empty '
          'answer above means there is nothing there — and the premise line '
          'is the only one it lets through',
    );
    expect(
      quietDeletesTooEarly(planted.path),
      [endsWith('/remnant_test.dart')],
      reason: 'a quiet delete in a group tearDown is the right seat; the '
          'same call handed to addTearDown is not',
    );
  });

  test('the quiet delete still deletes — only its failure is quiet', () {
    final room = Directory.systemTemp.createTempSync('temp-dir-quiet');
    File('${room.path}/left.bin').writeAsBytesSync(const [1, 2, 3]);

    deleteTempQuietly(room);
    expect(room.existsSync(), isFalse, reason: '⛔not 「지우지 않는다」');

    expect(
      () => deleteTempQuietly(room),
      returnsNormally,
      reason: 'a folder that could not be removed — here, one already gone '
          '— is not the test\'s result',
    );
  });
}

/// The seat that swallows, and the seat that releases the project file
/// before asking it.
const _quietSeat = 'test/helpers/temp_dir.dart';
const _releasingSeat = 'test/helpers/project_scratch_folder.dart';
