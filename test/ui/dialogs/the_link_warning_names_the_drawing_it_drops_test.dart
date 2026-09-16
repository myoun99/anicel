import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// link-frame-join-shares-or-replaces — the link window says what joining
/// by name costs.
///
/// 유저 2026-09-12, 「문구를 동작에 맞춘다」: 「기존 문장을 그대로 사용하되,
/// 좀 더 알기쉽게 정리하고 이 프레임 그림 버린다고 안내. 문장만 알기쉽게
/// 정리하자.」
///
/// The window promised only that the same name would SHARE the same
/// material, while the join moves this frame's blocks onto the other frame
/// and takes this frame's cel out of the bank. Every language now says the
/// drawing goes.
void main() {
  const dropped = <AppLanguage, String>{
    AppLanguage.en: 'discarded',
    AppLanguage.ja: '破棄',
    AppLanguage.ko: '버려',
    AppLanguage.fr: 'supprimé',
    AppLanguage.zhHans: '舍弃',
  };

  for (final language in AppLanguage.values) {
    test('${language.name}: the link window says the drawing goes', () {
      // The ! stays, in the one place it means something: a language
      // missing from the table must fail loudly here, not quietly
      // pass a null through `contains` (unnecessary_null_checks).
      final expected = dropped[language]!;
      expect(
        AppStrings.of(language).frameNameConflictBody,
        contains(expected),
      );
    });
  }
}
