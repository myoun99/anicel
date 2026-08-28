import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';

/// 🚨F-41 — **그리드선은 정해진 세기 순서를 지킨다.**
///
/// > 「그리드선이 너무 진함. 전체적으로 좀 더 한단계 밝은색쪽으로 변경.
/// > **포인트는 그리드선이 진해서 블록이 한 블록이아니라 나뉜것처럼 보이는
/// > 착시현상이 문제**」
///
/// 🔬재봤더니 **법이 깨져 있었다.** `timeline_beat_lines.dart` 는 SECOND 를
/// 「the strongest」라고 적어 두는데, 블록 종이(L=0.906) 위에서 실제로는
/// **6f 가 더 진했다** — 6f ΔL=0.649 vs SECOND ΔL=0.451. 6f 는 **여섯 칸마다**
/// 오므로, 한 블록을 여섯 칸마다 가장 진한 선으로 자르고 있었다. 유저가 말한
/// 「나뉜 것처럼 보이는 착시」가 그것이다.
///
/// ⇒ 이 파일은 **순서**를 잰다. 「얼마나 밝은가」는 취향이지만 **어느 선이 더
/// 진한가는 법**이고, 그 법이 파일에 적혀 있다.
void main() {
  const paper = timelineDrawingHeldColor;

  double luminance(Color c) => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;

  /// 종이 위에 그 선이 얹혔을 때 **얼마나 어두워지는가**.
  double darkening(({Color color, double strokeWidth}) ink) =>
      luminance(paper) - luminance(timelineGridLineInkOnGround(ink, paper));

  testWidgets('base < 6f < second — 법이 적어 둔 순서 그대로', (tester) async {
    late ColorScheme scheme;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) {
            scheme = Theme.of(context).colorScheme;
            return const SizedBox();
          },
        ),
      ),
    );

    final base = darkening(timelineGridBaseLineInk(scheme));
    final six = darkening(timelineGridSixLineInk(scheme));
    final second = darkening(timelineGridSecondLineInk());

    expect(base, greaterThan(0), reason: '⛔0 이면 선이 아예 안 보인다');
    expect(
      base,
      lessThan(six),
      reason: '기본선은 6f 보다 옅다 — 그게 「기본」의 뜻이다',
    );
    expect(
      six,
      lessThan(second),
      reason:
          '🚨SECOND 가 가장 진하다고 파일이 적어 뒀다. 6f 가 더 진하면 '
          '**여섯 칸마다 블록이 잘려 보인다** — 유저가 말한 착시가 그것이다',
    );
  });
}
