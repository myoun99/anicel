import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨A NEW CUT TAKES ITS ROOM BY ONE INSERTION — EVERY NEW CUT.
///
/// 유저 #19 (2026-08-15): 「미는건 뒤에 공간없으면 밀어도되는데, 공간이
/// 여유분이 있는데도 여유분 뒤의 컷을 밀어버림」 · F-97 (2026-09-12): 「새 컷
/// 만드는거랑 똑같이 해서 **법 하나로 통일**」.
///
/// The room a cut takes is ONE piece of arithmetic
/// (`followerGapsAfterInsert`), and ONE place asks it: the insertion
/// (`cut_insertion.dart` — `projectWithCutInserted`, which `CutInsertion`
/// and 겸용컷 생성 both go through).
///
/// ↩️겸용컷 생성 asked it for itself, inside its own project write, and
/// recorded the gaps to hand back in its own words — the same answer spelt
/// twice (`duplicate-cut-skips-the-insertion-law`, found 2026-09-30).
/// ⛔A behaviour test passes two copies that agree today
/// (`a_cut_takes_its_room_the_way_a_block_does_test` did); this scan is
/// what stops the second speller coming back.
void main() {
  const arithmetic = 'followerGapsAfterInsert(';
  const itsOwnFile = 'lib/src/services/editing/cut_insertion_room.dart';
  const theInsertion = 'lib/src/services/commands/cut_insertion.dart';

  /// The lines of [file] that ask the arithmetic, comments aside.
  List<String> askersIn(File file) => [
    for (final line in file.readAsLinesSync())
      if (!line.trimLeft().startsWith('//') && line.contains(arithmetic))
        line.trim(),
  ];

  final askers = <String, List<String>>{
    for (final file in dartFilesUnder('lib'))
      if (libPath(file) != itsOwnFile)
        if (askersIn(file) case final found when found.isNotEmpty)
          libPath(file): found,
  };

  test('premise: the scan sees the insertion ask it', () {
    expect(
      askers.keys,
      contains(theInsertion),
      reason: 'an empty scan must not pass for nothing',
    );
  });

  test('nothing but the insertion asks what room a new cut takes', () {
    expect(
      askers.keys.toList(),
      [theInsertion],
      reason: 'a cut that lands in front of others goes through '
          'projectWithCutInserted — its own arithmetic is the copy this '
          'law was written against',
    );
  });

  test('and 겸용컷 생성 goes through it', () {
    final command = File(
      'lib/src/services/commands/create_linked_cut_command.dart',
    ).readAsStringSync();
    expect(command, contains('projectWithCutInserted('));
    expect(command, contains('projectWithCutTakenOut('));
  });
}
