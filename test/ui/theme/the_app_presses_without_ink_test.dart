import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../../helpers/dart_sources.dart';

/// 🚨★★★**F-138 ② — 눌린 자리에 잉크가 번지지 않는다, 앱 전체에서.**
///
/// > 「눌림 흰색 채움 애니메이션 제거. **이 앱은 기본적으로 이런거 off임.
/// > 없는채로 통일**」 (유저 2026-09-16)
///
/// F-132(2026-09-14)가 이 법을 이미 세웠는데 **레일 행 라벨 자리에만** 세웠다:
/// 「x시트 레이어라벨만 … 흰색으로 채워지는 애니메이션 없는데, 이거 맘에듬.
/// 일단 그부분 타임라인이랑 스토리보드패널이랑 법 하나로 통일」. 「일단 그부분」
/// 이었고, 이번 말이 그 범위를 앱 전체로 넓힌다.
///
/// ⛔**그래서 테마가 답한다.** 위젯마다 `splashFactory:` 를 적는 것은 「지우는
/// 곳을 하나 더 추가」이고, 다음에 생기는 버튼이 옆 버튼 중 어느 쪽을 베끼느냐에
/// 달리게 된다.
void main() {
  test('the theme presses without ink', () {
    final theme = buildAppTheme();
    expect(
      theme.splashFactory,
      NoSplash.splashFactory,
      reason: '유저: 「이 앱은 기본적으로 이런거 off임」',
    );
    expect(
      theme.highlightColor,
      Colors.transparent,
      reason: '번지는 것뿐 아니라 **누르고 있는 동안의 채움**도 없다',
    );
  });

  /// ⛔이제 아무도 제 것을 쓰지 않는다 (소스 스캔 래칫).
  ///
  /// 행동 테스트는 「지금은 테마와 일치하는 사본 셋」을 통과시킨다 — F-132 가
  /// 남긴 상수 둘이 정확히 그것이었다.
  test('no widget spells its own no-ink', () {
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib/src/ui')) {
      final path = libPath(file);
      if (path == 'lib/src/ui/theme/app_theme.dart') {
        continue; // The one home.
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//') || line.startsWith('///')) {
          continue;
        }
        if (line.contains('NoSplash.splashFactory')) {
          offenders.add('$path:${i + 1}  $line');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '⛔잉크를 끄는 곳은 테마 하나다 — 위젯이 제 손으로 끄면 다음 위젯은 '
          '끄는 것을 잊고, 그게 F-132 가 한 번 닫았다가 다시 열린 이유다',
    );
  });
}
