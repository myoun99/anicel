import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// Two notices the guide's audit found behind the app (관제 2026-10-21).
void main() {
  /// convert-dialog-says-two-cuts: the conversion reaches each side's
  /// family (491813562 · f42a6f5c2 · d6720eaa2), and its one undo restores
  /// every cut it touched — the window promised two.
  test('the convert window\'s undo note promises no two cuts, in any '
      'language', () {
    const two = {
      AppLanguage.en: 'both',
      AppLanguage.ja: '両方',
      AppLanguage.ko: '두 컷',
      AppLanguage.fr: 'deux',
      AppLanguage.zhHans: '两个',
    };
    expect(two.keys, unorderedEquals(AppLanguage.values), reason: '⛔전제');
    for (final MapEntry(key: language, value: word) in two.entries) {
      expect(
        AppStrings.of(language).convertLinkedCutUndoNote,
        isNot(contains(word)),
        reason: language.name,
      );
    }
  });

  /// conte-duplicate-notice-old-name: the notice a cut's second conte row
  /// meets called it 「스토리보드 레이어」 in Korean, where the row's kind is
  /// 「콘티」.
  test('the notice that a cut holds one conte row names the row by its '
      'kind\'s own word, in every language', () {
    for (final language in AppLanguage.values) {
      final strings = AppStrings.of(language);
      expect(
        strings.sbOneStoryboardRowPerCut.toLowerCase(),
        contains(strings.tlKindStoryboard.toLowerCase()),
        reason: language.name,
      );
    }
  });
}
