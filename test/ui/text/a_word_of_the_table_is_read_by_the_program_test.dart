// 🗣️F-318 (유저 2026-10-08): 「동일한 단축키 있을때 빨간 경고메시지가 영어로
// 뜨고」.
//
// The sentence had been in the table, in every language, since the shortcut
// window was localised — and the window went on writing the English one
// itself. Nothing was red: the table's own tests read every getter
// (app_strings_keys_test), so a word no part of the PROGRAM reads looks
// exactly like one that is in use.
//
// ⇒ A WORD OF THE TABLE IS READ BY THE PROGRAM — or it stands in the ledger
// below: the words that were unread the day this was written (2026-10-08,
// 37 of 941). Each is one of two things, and telling them apart is reading
// its place, one at a time — a place that still writes its own words, or a
// row left behind by something that was removed. The ledger is what is
// owed, and it only shrinks.
//
// HOW IT READS: a getter is read when some file under lib other than the
// table has `.name` in it. ⚠️A member of another class with the same name
// reads as a reading — the scan errs towards quiet, never a false alarm.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/dart_sources.dart';

const _table = 'lib/src/ui/text/app_strings.dart';

/// The getters [table] declares — `String get name => _s('name')`, on one
/// line or two.
Set<String> wordsOf(String table) => {
  for (final match in RegExp(r'String get (\w+) =>\s*_s\(').allMatches(table))
    match.group(1)!,
};

/// The [words] that [program] — the program's source, the table left out —
/// nowhere reads as a member.
Set<String> unreadAmong(Set<String> words, String program) => words.difference({
  for (final match in RegExp(r'\.(\w+)\b').allMatches(program)) match.group(1)!,
});

/// The words nobody read when this was written. ⛔Nothing is added: a new
/// word is read by the place it was written for.
const _owed = <String>{
  'accentTitle',
  'brGroupOptions',
  'brTransformPreserveColors',
  'brTransformPreserveColorsHint',
  'canvasPresetDefault',
  'commonFill',
  'cutDelete',
  'exCelCountOne',
  'fileNameEmpty',
  'fileNameLabel',
  'fileSaveTitle',
  'inputTitle',
  'languageSettingsTitle',
  'menuBarCut',
  'menuBarEdit',
  'menuBarFile',
  'menuBarHelp',
  'menuBarLayer',
  'menuBarPlayback',
  'menuBarWindow',
  'onionAfter',
  'onionBefore',
  'penPressureAxis',
  'sheetSixSeconds',
  'sheetThreeSeconds',
  'sortByModified',
  'sortByName',
  'sortBySize',
  'sortDescending',
  'tlCustom',
  'tlDeleteLayer',
  'tlRenameLayer',
  'tlSameAsSelected',
  'tlSeNameTemplate',
  'tlSharedDeselect',
  'workCover',
  'workLogo',
};

void main() {
  test('the scan tells a word that is read from one that is not', () {
    const table = '''
  String get savedNotice => _s('savedNotice');
  String get neverShown =>
      _s('neverShown');
  String composed(String name) => _s('composed');
''';
    expect(wordsOf(table), {'savedNotice', 'neverShown'});
    expect(
      unreadAmong(wordsOf(table), 'Text(AppText.strings.savedNotice)'),
      {'neverShown'},
    );
    expect(
      unreadAmong(wordsOf(table), "Text('Saved.') // savedNotice"),
      {'savedNotice', 'neverShown'},
      reason: 'a word named in passing is not a word read',
    );
  });

  test('🚨every word of the table is read by the program, or is owed', () {
    final words = wordsOf(File(_table).readAsStringSync());
    expect(words.length, greaterThan(900), reason: '⛔premise: the table');
    final program = StringBuffer();
    var files = 0;
    for (final file in dartFilesUnder('lib')) {
      if (libPath(file) != _table) {
        program.writeln(file.readAsStringSync());
        files += 1;
      }
    }
    expect(files, greaterThan(100), reason: '⛔premise: the program');
    final unread = unreadAmong(words, program.toString());

    expect(
      unread.difference(_owed),
      isEmpty,
      reason:
          'a word of the table that no part of the program reads: either '
          'its place writes its own words — in one language (F-318) — or '
          'nothing shows it any more and its rows go, in every language',
    );
    expect(
      _owed.difference(unread),
      isEmpty,
      reason: 'read now, or gone from the table: take it out of the ledger',
    );
    expect(_owed, hasLength(37), reason: 'the ledger only shrinks');
  });
}
