import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🗣️I-24-open-entry (유저 2026-10-01): 「노출 길이 설정 (프레임), 노출 길이
/// 설정 (컷) 이렇게 하자 … 이 규칙은 다른 타임라인 버튼도 동일하게.
/// 이름편집같은거. 이름 편집 (레이어) 이렇게」 — a timeline button's window
/// is titled with what it does and, in brackets, the kind it does it to.
void main() {
  test('in the user\'s own words', () {
    final ko = AppStrings.of(AppLanguage.ko);
    expect(
      ko.windowTitleOn(ko.setLengthAction, ko.tlFrame),
      '노출 길이 설정 (프레임)',
    );
    expect(ko.windowTitleOn(ko.setLengthAction, ko.tlCut), '노출 길이 설정 (컷)');
    expect(ko.windowTitleOn(ko.editNameAction, ko.tlLayer), '이름 편집 (레이어)');
  });

  test('every language: the action, then the kind in its own brackets', () {
    final titled = <AppLanguage, String>{
      AppLanguage.en: 'Set exposure length (Frame)',
      AppLanguage.ja: '露光の長さの設定（フレーム）',
      AppLanguage.ko: '노출 길이 설정 (프레임)',
      AppLanguage.fr: "Définir la durée d'exposition (Image)",
      AppLanguage.zhHans: '设置曝光长度（帧）',
    };
    expect(titled.keys, unorderedEquals(AppLanguage.values), reason: '⛔전제');
    for (final language in AppLanguage.values) {
      final strings = AppStrings.of(language);
      expect(
        strings.windowTitleOn(strings.setLengthAction, strings.tlFrame),
        titled[language],
        reason: language.name,
      );
    }
  });
}
