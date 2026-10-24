import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🗣️I-58 (유저 2026-10-18): 「추가로 버튼이름 이상함 … 진짜 감탄나오게도
/// 통일을 안해놨는데 통일(레이어 추가 이런식으로 ㅁㅁ 추가. ㅁㅁ 삭제)하고」 —
/// a delete says what it deletes. Three did not: the guide row's said 「삭제」,
/// the vanishing point's borrowed that same string, and the media pool's
/// said 「제거」.
void main() {
  // The form the app's deletes already read in — 「그룹 삭제」, 'Delete
  // group', 'グループを削除', 'Supprimer le groupe', '删除分组': the verb, and
  // what it deletes.
  final form = <AppLanguage, Matcher>{
    AppLanguage.en: matches(RegExp(r'^Delete \S')),
    AppLanguage.ja: matches(RegExp(r'^.+を削除$')),
    AppLanguage.ko: matches(RegExp(r'^\S.* 삭제$')),
    AppLanguage.fr: matches(RegExp(r'^Supprimer \S')),
    AppLanguage.zhHans: matches(RegExp('^删除.+')),
  };

  test('in every language each reads as the app\'s other deletes do, and '
      'names its own thing', () {
    expect(form.keys, unorderedEquals(AppLanguage.values), reason: '⛔전제');
    for (final language in AppLanguage.values) {
      final strings = AppStrings.of(language);
      expect(
        strings.brDeleteGroup,
        form[language],
        reason: '⛔전제: the form is the one ${language.name} already reads',
      );
      final names = [
        strings.guideDelete,
        strings.guideDeleteVanishingPoint,
        strings.mediaRemove,
      ];
      expect(names, everyElement(form[language]), reason: language.name);
      expect(names.toSet(), hasLength(names.length), reason: language.name);
    }
  });

  // 🔎brush-tip-delete-question-speaks-english (10-19): the group's question
  // was English beside the tables, its plural too.
  test('a group\'s delete question names the group and counts what goes '
      'with it — none, one, or many', () {
    final ko = AppStrings.of(AppLanguage.ko);
    expect(ko.brDeleteGroupBody('Ink', 0), '「Ink」 빈 그룹을 삭제할까요?');
    expect(ko.brDeleteGroupBody('Ink', 1), '「Ink」 그룹과 안의 브러시 1개를 삭제할까요?');
    expect(ko.brDeleteGroupBody('Ink', 3), '「Ink」 그룹과 안의 브러시 3개를 삭제할까요?');
    final en = AppStrings.of(AppLanguage.en);
    expect(en.brDeleteGroupBody('Ink', 1), 'Delete "Ink" and the brush inside it?');
    expect(
      en.brDeleteGroupBody('Ink', 3),
      'Delete "Ink" and the 3 brushes inside it?',
    );
    expect(ko.brDeleteTipBody('Old'), '「Old」 끝을 라이브러리에서 삭제합니다.');
  });
}
