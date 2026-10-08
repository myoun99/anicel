import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the brush library says back — after an export, an import, a tip's
/// registration — was English in every language until 2026-10-08 (board
/// `brush-export-has-no-road-where-no-save-window-answers-a-path`: 「영어로
/// 박힌 알림 문장」). Each is the program language's now, its values in it.
void main() {
  final notices = <String, (String Function(AppStrings), List<String>)>{
    'no place chosen': (
      (s) => s.brExportPlaceUnchosen('ERR-1'),
      ['ERR-1'],
    ),
    'not written': ((s) => s.brExportNotWritten('ERR-2'), ['ERR-2']),
    'one exported': ((s) => s.brExportedOne('Ink G'), ['Ink G']),
    'many exported': ((s) => s.brExportedMany(37), ['37']),
    'the file\'s name': ((s) => s.brExportFallbackName, const []),
    'unreadable': ((s) => s.brImportUnreadable, const []),
    'pick failed': ((s) => s.brImportPickFailed('ERR-3'), ['ERR-3']),
    'one imported': ((s) => s.brImported(1, 'pack.abr'), ['pack.abr']),
    'many imported': (
      (s) => s.brImported(37, 'pack.abr'),
      ['37', 'pack.abr'],
    ),
    'with warnings': (
      (s) => s.brImportWarnings('SUMMARY', 5),
      ['SUMMARY', '5'],
    ),
    'tip unreadable': ((s) => s.brTipUnreadable, const []),
    'tip with no shape': ((s) => s.brTipNoShape, const []),
    'tip not saved': ((s) => s.brTipNotSaved, const []),
  };
  final english = AppStrings.of(AppLanguage.en);

  for (final language in AppLanguage.values) {
    test('every brush notice is written in ${language.name}, its values in '
        'it', () {
      final strings = AppStrings.of(language);
      for (final MapEntry(key: name, value: (say, values)) in notices.entries) {
        final said = say(strings);
        expect(said, isNot(contains('{')), reason: '$name: $said');
        for (final value in values) {
          expect(said, contains(value), reason: '$name: $said');
        }
        if (language != AppLanguage.en) {
          expect(said, isNot(say(english)), reason: '$name is still English');
        }
      }
    });
  }

  test('one brush and many are said apart', () {
    final strings = AppStrings.of(AppLanguage.en);
    expect(strings.brImported(1, 'p'), isNot(contains('1 brushes')));
    expect(strings.brImported(2, 'p'), contains('2 brushes'));
  });
}
