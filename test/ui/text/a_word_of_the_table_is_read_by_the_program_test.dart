// 🗣️F-318 (유저 2026-10-08): 「동일한 단축키 있을때 빨간 경고메시지가 영어로
// 뜨고」.
//
// The sentence had been in the table, in every language, since the shortcut
// window was localised — and the window went on writing the English one
// itself. Nothing was red: the table's own tests read every getter
// (app_strings_keys_test), so a word no part of the PROGRAM reads looks
// exactly like one that is in use.
//
// ⇒ A WORD OF THE TABLE IS READ BY THE PROGRAM. ↩️Until 2026-10-09 a ledger
// stood here: the 36 words unread the day this was written. Read one at a
// time (card the-string-table-holds-words-nobody-reads), they were three
// things — 31 rows a removed screen left behind (the seven-menu bar, the old
// file browser, the windows that became sections of the preferences …),
// gone with their lines in every language; four the table reads ITSELF,
// through a word it composes (`sheetKindName` answers with
// `sheetThreeSeconds`), which the scan now counts; and one getter that
// `_count` outlived (its lines stay — `_count` reads them by name).
//
// HOW IT READS: a getter is read when some file under lib other than the
// table has `.name` in it, or when the table itself names it outside its own
// getter and outside its text. ⚠️A member of another class with the same
// name reads as a reading — the scan errs towards quiet.
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

/// The names [table] uses in its own code — a composed word's body naming
/// another — with the texts, the comments and each getter's own name left
/// out.
Set<String> readInTable(String table) {
  final code = table
      .replaceAll(RegExp(r"'(?:[^'\\\n]|\\.)*'"), "''")
      .replaceAll(RegExp(r'"(?:[^"\\\n]|\\.)*"'), '""')
      .replaceAll(RegExp(r'//[^\n]*'), '')
      .replaceAll(RegExp(r'String get \w+ =>'), '');
  return {for (final match in RegExp(r'\b(\w+)\b').allMatches(code)) match[1]!};
}

/// The [words] that nothing reads — [program], the program's source with the
/// table left out, nowhere as a member, and [table] nowhere in its own code.
Set<String> unreadAmong(
  Set<String> words,
  String program, {
  String table = '',
}) => words.difference({
  for (final match in RegExp(r'\.(\w+)\b').allMatches(program)) match.group(1)!,
  ...readInTable(table),
});

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

  test('a word the table composes another from is read — named in its '
      'text or its comments, it is not', () {
    const table = '''
  String get threeSeconds => _s('threeSeconds');
  String get sixSeconds => _s('sixSeconds');
  /// [sixSeconds]'s neighbour.
  String get mentioned => _s('mentioned');
  String kindName(int kind) => switch (kind) {
    3 => threeSeconds,
    _ => 'sixSeconds',
  };
  // mentioned
  static const Map<String, String> _en = {
    'mentioned': 'sixSeconds',
  };
''';
    expect(unreadAmong(wordsOf(table), '', table: table), {
      'sixSeconds',
      'mentioned',
    });
  });

  test('🚨every word of the table is read by the program', () {
    final table = File(_table).readAsStringSync();
    final words = wordsOf(table);
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

    expect(
      unreadAmong(words, program.toString(), table: table),
      isEmpty,
      reason:
          'a word of the table that nothing reads: either its place writes '
          'its own words — in one language (F-318) — or nothing shows it any '
          'more and its rows go, in every language',
    );
  });
}
