import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// I-66 (유저 2026-10-04): 「링크컷 이름 겸용컷으로 변경. 한국어 일본어는
/// 겸용, 영어나 다른건 링크컷 그대로」.
///
/// A cut that shares its pictures with another was 「링크 컷」 / 「リンク
/// カット」 in four places each — the menu that makes one, the menu and the
/// window that convert one, and the reason its rows cannot be unlinked alone
/// — while the import window and the convert window's own warning already
/// said 겸용 / 兼用. One name for it now, in the two languages that have the
/// word.
void main() {
  List<String> wordsFor(AppLanguage language) {
    final strings = AppStrings.of(language);
    return [
      strings.shortcutLabel('cut-create-linked', '?'),
      strings.shortcutLabel('cut-convert-linked', '?'),
      strings.convertLinkedCutTitle,
      strings.linkWindowUnlinkLinkedCut,
      strings.imMultiCutFolders,
    ];
  }

  test('Korean says 겸용컷 everywhere a linked cut is named, in one '
      'spelling', () {
    final words = wordsFor(AppLanguage.ko);
    expect(words, everyElement(contains('겸용컷')));
    expect(words, everyElement(isNot(contains('링크 컷'))));
  });

  test('Japanese says 兼用カット', () {
    final words = wordsFor(AppLanguage.ja);
    expect(words, everyElement(contains('兼用カット')));
    expect(words, everyElement(isNot(contains('リンクカット'))));
  });

  test('the languages that have no such word keep theirs', () {
    final english = AppStrings.of(AppLanguage.en);
    expect(english.convertLinkedCutTitle, contains('linked'));
    expect(
      english.shortcutLabel('cut-create-linked', 'Create linked cut'),
      'Create linked cut',
      reason: 'English lives in the registry, as the row\'s own label',
    );
  });
}
