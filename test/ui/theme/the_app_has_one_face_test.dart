import 'dart:io';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★앱은 **자기 얼굴**로 말한다. 유저 확정 2026-08-28:
/// 일본어 **BIZ UDPGothic**(「작은크기 가독성 목표로해서 아주 읽기쉬워」)
/// + 한글 **나눔고딕**. 그 전까지는 폰트가 없어서 OS 가 주는 것을 입었다.
void main() {
  test('테마가 앱 폰트를 들고 있다 — OS 에 맡기지 않는다', () {
    final theme = buildAppTheme();
    expect(theme.textTheme.bodyMedium?.fontFamily, isNotNull);
  });

  test('🚨순서가 법이다 — 일본어가 앞, 한글이 뒤', () {
    // ⛔순서는 취향이 아니라 **무엇이 어느 폰트로 그려지는가**다.
    // ①한자는 일·중이 코드포인트를 공유하고 자형이 다르다 — 앞의 폰트가 정한다
    // ②나눔고딕에는 라틴 확장이 없고 BIZ 에는 프랑스어 32/32 가 있다
    //   ⇒ 뒤집히면 é 가 두부가 된다
    expect(AppTypography.familyFor(AppLanguage.ja), 'BIZ UDPGothic');
    expect(AppTypography.fallbackFor(AppLanguage.ja), ['Nanum Gothic']);
    expect(
      AppTypography.familyFor(AppLanguage.ko),
      'BIZ UDPGothic',
      reason: '한국어 UI 라도 라틴·한자는 BIZ 가 그린다 — 한글만 뒤로 간다',
    );
  });

  test('🚨중국어는 OS 에 맡긴다 — 섞이느니 통째로 넘긴다', () {
    // BIZ 는 앱의 중국어 582자 중 174자를 안 갖고 있다(실측). 그대로 씌우면
    // 408자는 일본 자형, 174자는 OS 폰트로 **한 문장 안에서 갈린다** —
    // 통일하려다 오히려 갈라 놓는 것이라, 중국어만 통째로 OS 로 보낸다.
    expect(AppTypography.familyFor(AppLanguage.zhHans), isNull);
    expect(AppTypography.fallbackFor(AppLanguage.zhHans), isNull);
  });

  test('⛔선언한 폰트만 부른다 — pubspec 에 없는 이름은 조용히 OS 로 떨어진다', () {
    // 🚨이게 이 파일에서 가장 중요한 단언이다. 이름을 틀리게 적어도 Flutter 는
    // **아무 말 없이** 플랫폼 폰트로 그린다 — 화면은 예전과 똑같고, 4.5MB 를
    // 번들한 채로 아무 효과가 없다.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared = RegExp(r'- family: (.+)')
        .allMatches(pubspec)
        .map((m) => m.group(1)!.trim())
        .toSet();

    expect(declared, isNotEmpty, reason: '⛔pubspec 에서 family 를 못 찾았다');
    for (final language in AppLanguage.values) {
      final family = AppTypography.familyFor(language);
      if (family != null) {
        expect(declared, contains(family), reason: '$language 의 본체');
      }
      for (final name in AppTypography.fallbackFor(language) ?? const []) {
        expect(declared, contains(name), reason: '$language 의 폴백');
      }
    }
  });

  test('⛔선언한 폰트 파일이 실제로 있다', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final assets = RegExp(r'- asset: (assets/fonts/\S+)')
        .allMatches(pubspec)
        .map((m) => m.group(1)!)
        .toList();
    expect(assets, isNotEmpty);
    for (final path in assets) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });
}
