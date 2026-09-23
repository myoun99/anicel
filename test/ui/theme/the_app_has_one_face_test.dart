import 'dart:io';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/dart_sources.dart';

/// 🚨★★★앱은 **자기 얼굴**로 말한다. 유저 확정 2026-08-28:
/// 일본어 **BIZ UDPGothic**(「작은크기 가독성 목표로해서 아주 읽기쉬워」)
/// + 한글 **나눔고딕**. 그 전까지는 폰트가 없어서 OS 가 주는 것을 입었다.
void main() {
  _noWidgetNamesItsOwnFace();

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
    final declared = RegExp('- family: (.+)')
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

/// ⛔**진짜 폰트 이름을 위젯이 자기 손으로 적지 못한다** (소스 스캔 래칫).
///
/// 하나가 적으면 그 위젯만 다른 글씨가 되고, 값이 같은 동안에는 안 보이다가
/// **폰트를 바꾸는 날 갈라진다** — 어제 색 토큰에서 정확히 그 일이 있었다.
///
/// ⚠️허용은 **제네릭 `'monospace'`** 뿐이다. 그건 폰트를 고르는 게 아니라
/// 「고정폭이면 된다」는 말이라 OS 에 맡기는 것이 맞다.
void _noWidgetNamesItsOwnFace() {
  test('lib 전체에서 진짜 폰트 이름을 적는 곳이 없다', () {
    // 폰트가 **자기 일**인 파일 둘은 뺀다: 테마(정의하는 곳)와 콘티 폰트
    // (PDF 에 임베드하는 파일을 이름으로 부른다).
    const owners = ['app_theme.dart', 'conte_fonts.dart'];
    // 제네릭 패밀리 — CSS 의 그것과 같다. 이름이 아니라 종류다.
    const generic = {'monospace', 'sans-serif', 'serif', 'cursive'};

    // ⚠️RAW 문자열이다. 보통 문자열에 `\s` 를 쓰면 Dart 가 **조용히 백슬래시를
    // 버려** 정규식이 `fontFamilys*` 가 된다 — 아무것도 안 잡으면서 초록이고,
    // 실제로 그렇게 통과했다. 뮤테이션이 살아남아서 알았다.
    final literal = RegExp(r"fontFamily:\s*'([^']+)'");
    final offenders = <String>[];
    var scanned = 0;
    for (final entity in dartFilesUnder('lib')) {
      if (owners.any(entity.path.endsWith)) {
        continue;
      }
      scanned++;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) {
          continue;
        }
        final hit = literal.firstMatch(lines[i]);
        if (hit != null && !generic.contains(hit.group(1))) {
          offenders.add('${entity.path}:${i + 1} — ${hit.group(1)}');
        }
      }
    }

    // 🚨계측기를 먼저 의심한다: 파일을 못 찾았으면 「위반 없음」이 공짜다.
    expect(scanned, greaterThan(100), reason: '⛔빈 것을 쟀다');
    expect(
      offenders,
      isEmpty,
      reason:
          '폰트 이름은 AppTypography 가 정한다 — 위젯이 직접 적으면 그 위젯만 '
          '다른 글씨가 된다:\n${offenders.join('\n')}',
    );
  });
}
