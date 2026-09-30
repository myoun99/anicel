import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🗣️F-76 (유저 2026-09-11): 「콘티패널은 지금의 스토리보드패널을 콘티패널로
/// 명명하고, 기존 콘티패널은 … 콘티 용지 …」 — F-76-Q1 (09-30): 「콘티 용지」.
/// The two panels shared one Korean name, 「콘티」, until then.
void main() {
  test('every language tells the two panels apart', () {
    for (final language in AppLanguage.values) {
      final strings = AppStrings.of(language);
      expect(
        strings.panelConte,
        isNot(strings.panelStoryboard),
        reason: '$language',
      );
    }
  });

  test('the storyboard panel is the 콘티 panel; the old one is the 콘티 용지', () {
    final korean = AppStrings.of(AppLanguage.ko);
    expect(korean.panelStoryboard, '콘티');
    expect(korean.panelConte, '콘티 용지');
  });
}
