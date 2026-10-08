import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/ui/dialogs/app_confirm_dialog.dart'
    show fileErrorWords;
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🗣️유저 2026-10-06 (the save law): 「옛파일 읽는코드는 필요없다고
/// 확신했어」 → 「아까 답변 범위 ok 옛파일 열었을때 보이는거 ok.」 — an older
/// file is refused at the open door, in one sentence that says its format.
///
/// ↩️It said it in English with `FormatException:` in front of it in every
/// language: the open door shows a file error as it is (`showFileError`),
/// and the refusal was a bare [FormatException].
void main() {
  List<int> documentSaying(int formatVersion) => utf8.encode(
    jsonEncode({
      'formatVersion': formatVersion,
      'project': createDefaultProject().toJson(),
    }),
  );

  Object refusalOf(int formatVersion) {
    try {
      decodeAnicelProjectDocument(documentSaying(formatVersion));
    } on Object catch (error) {
      return error;
    }
    fail('format $formatVersion opened');
  }

  tearDown(() => AppText.settings.value = const AppLanguageSettings());

  test('the archive refuses by number, and says which side of the range', () {
    final older = refusalOf(anicelOldestReadFormatVersion - 1);
    expect(older, isA<FormatException>(), reason: 'still caught as one');
    expect(
      older,
      isA<AnicelFormatRefused>()
          .having((error) => error.saved, 'saved',
              anicelOldestReadFormatVersion - 1)
          .having((error) => error.newer, 'newer', isFalse),
    );
    expect(
      refusalOf(anicelFormatVersion + 1),
      isA<AnicelFormatRefused>().having((error) => error.newer, 'newer', true),
    );
  });

  test('🚨what a person reads is the program language\'s sentence, with the '
      'file\'s format in it — no FormatException', () {
    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.ko,
      notationLanguage: AppLanguage.ko,
    );
    final older = fileErrorWords(refusalOf(9));
    expect(older, AppText.strings.openOlderFormat(9, 11));
    expect(older, contains('9'));
    expect(older, contains('$anicelOldestReadFormatVersion'));
    expect(older, isNot(contains('FormatException')));
    expect(older, isNot(contains('older than')));
    expect(
      fileErrorWords(refusalOf(anicelFormatVersion + 1)),
      AppText.strings.openNewerFormat,
    );
  });

  test('every language says both, and the older one names both numbers', () {
    for (final language in AppLanguage.values) {
      final strings = AppStrings.of(language);
      final older = strings.openOlderFormat(4, 11);
      expect(older, allOf(contains('4'), contains('11')), reason: '$language');
      expect(older, isNot(contains('{')), reason: '$language');
      expect(strings.openNewerFormat, isNotEmpty, reason: '$language');
    }
  });

  test('⛔an error the app has no sentence for is shown as it is', () {
    expect(fileErrorWords(const FormatException('odd')), 'FormatException: odd');
  });
}
