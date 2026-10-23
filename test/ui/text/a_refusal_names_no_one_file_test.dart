import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🚨Card open-door-windows-open-with (서피스 AI 실기 2026-10-23): a file
/// nothing opens was refused with 「「{name}」はここでは開けません。…」 — the
/// placeholder on screen. The sentence was born with a `{name}` beside the
/// formats (2026-08-29) and every caller filled the formats alone, so it
/// showed in every refusal, in every language.
///
/// 유저 2026-08-29: 「지원하지 않는 파일이 감지되었습니다. 라는 안내창으로
/// 두번째줄에 해당 파일들이라는 항목으로 접기 펼치기 가능하게 그 안에
/// 파일주소,이름들 표시」 — the sentence says the formats, and the files go
/// in the list beneath it.
void main() {
  for (final language in AppLanguage.values) {
    test('🎯the refusal says the formats and leaves no placeholder — '
        '${language.name}', () {
      final said = AppStrings.of(
        language,
      ).unsupportedFileMessage(const ['png', 'abr']);

      expect(said, contains('.png, .abr'));
      expect(said, isNot(contains('{')), reason: 'a placeholder nothing fills');
      expect(said, isNot(contains('}')));
    });
  }

  test('each language says it in its own words — none falls back to '
      'another', () {
    expect({
      for (final language in AppLanguage.values)
        AppStrings.of(language).unsupportedFileMessage(const ['png']),
    }, hasLength(AppLanguage.values.length));
  });
}
