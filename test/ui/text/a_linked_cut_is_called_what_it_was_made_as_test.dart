import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart'
    show EditorActionIds;
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🗣️F-554 (유저 2026-11-04): 「링크컷에서 버튼 이름, 지금 링크 대상
/// 이런식인데 이름 제대로 겸용으로서 지칭하도록. 이 링크컷 만드는것도 이름
/// 겸용컷 만들기니까. 동기는 지금그대로 동기」 — the link badge and its window
/// call the link by the word its cut was made by, in every language.
void main() {
  // The word each language makes a linked cut by.
  const madeAs = {
    AppLanguage.en: 'link',
    AppLanguage.ja: '兼用',
    AppLanguage.ko: '겸용',
    AppLanguage.fr: 'lié',
    AppLanguage.zhHans: '链接',
  };

  for (final language in AppLanguage.values) {
    test('in ${language.name}, the window is titled by the word the cut was '
        'made by', () {
      final strings = AppStrings.of(language);
      final word = madeAs[language]!;
      expect(
        strings
            .shortcutLabel(EditorActionIds.cutCreateLinked, 'Create linked cut')
            .toLowerCase(),
        contains(word),
      );
      expect(strings.tlLinkedWith.toLowerCase(), contains(word));
    });
  }

  test('the Korean and Japanese windows part a 겸용 by that word too — they '
      'said 「링크」 · 「リンク」', () {
    for (final language in [AppLanguage.ko, AppLanguage.ja]) {
      expect(
        AppStrings.of(language).linkWindowUnlink,
        contains(madeAs[language]),
      );
    }
  });

  test('the sync keeps its own word (「동기는 지금그대로 동기」)', () {
    final korean = AppStrings.of(AppLanguage.ko);
    expect(korean.syncedWith, '동기 대상');
    expect(korean.linkWindowUnsync, '동기 해제');
  });
}
