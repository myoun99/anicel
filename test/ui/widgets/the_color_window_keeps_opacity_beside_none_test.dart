import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/color_swatch_button.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

/// 🚨F-114 (유저 2026-09-15): the shared colour window carries the OPACITY bar
/// in the row of the none button — 「버튼 있는 열에서, 왼쪽정렬로 불투명도
/// 슬라이더가 존재하고, 오른쪽에 공간 남겨놔서 거기다가 없음버튼.
/// 없음버튼누르면 불투명도쪽 비활성화시킴. 불투명도쪽 조절은 가능해서 조절하면
/// 활성화색되면서 조절」 — and 「불투명도는 체크무늬는 안되고 진짜 불투명도를
/// 낮추는행위」: the bar writes the colour's real alpha.
void main() {
  Future<({List<int> emitted, List<void> nones})> open(
    WidgetTester tester, {
    required int color,
    required bool none,
    required bool keepsAlpha,
  }) async {
    final emitted = <int>[];
    final nones = <void>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ColorSwatchButton(
              keyValue: 'swatch',
              color: color,
              none: none,
              keepsAlpha: keepsAlpha,
              onChanged: emitted.add,
              onNone: () => nones.add(null),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('swatch')));
    await tester.pumpAndSettle();
    return (emitted: emitted, nones: nones);
  }

  const barKey = ValueKey<String>('color-picker-opacity');
  const noneKey = ValueKey<String>('color-picker-none');
  FieldSlider bar(WidgetTester tester) =>
      tester.widget<FieldSlider>(find.byKey(barKey));

  testWidgets('the bar sits LEFT of 「없음」 in one row and reads the kept '
      'alpha', (tester) async {
    await open(tester, color: 0x80336699, none: false, keepsAlpha: true);
    final barRect = tester.getRect(find.byKey(barKey));
    final noneRect = tester.getRect(find.byKey(noneKey));
    expect(barRect.right, lessThanOrEqualTo(noneRect.left));
    expect((barRect.center.dy - noneRect.center.dy).abs(), lessThan(2));
    expect(bar(tester).value, closeTo(0x80 / 255, 1e-9));
    expect(bar(tester).restingAccent, isNull, reason: 'a plane that is there');
  });

  testWidgets('「없음」 dims the bar and the window stays; a drag lights it '
      'and writes the kept colour at the new alpha', (tester) async {
    final probe = await open(
      tester,
      color: 0x80336699,
      none: false,
      keepsAlpha: true,
    );
    await tester.tap(find.byKey(noneKey));
    await tester.pumpAndSettle();
    expect(probe.nones, hasLength(1));
    expect(
      find.byKey(const ValueKey<String>('color-picker-wheel')),
      findsOneWidget,
      reason: 'the window stays open, so the dimmed bar can be seen and used',
    );
    expect(bar(tester).restingAccent, AppColors.textDim);
    expect(bar(tester).onChanged, isNotNull, reason: 'dim, still adjustable');

    bar(tester).onChanged!(0.25);
    await tester.pump();
    expect(probe.emitted.last >>> 24, (0.25 * 255).round());
    expect(probe.emitted.last & 0xFFFFFF, 0x336699);
    expect(bar(tester).restingAccent, isNull, reason: 'adjusting lights it');
  });

  testWidgets('a window opened on an ABSENT plane starts dim', (tester) async {
    await open(tester, color: 0xFF336699, none: true, keepsAlpha: true);
    expect(bar(tester).restingAccent, AppColors.textDim);
  });

  testWidgets('a host that keeps no alpha: the bar keeps its seat, dead, and '
      'a pick is opaque', (tester) async {
    final probe = await open(
      tester,
      color: 0x80336699,
      none: false,
      keepsAlpha: false,
    );
    expect(bar(tester).onChanged, isNull);
    final wheel = tester.getRect(
      find.byKey(const ValueKey<String>('color-picker-wheel')),
    );
    await tester.dragFrom(
      wheel.center - Offset(wheel.shortestSide / 2 - 6, 0),
      const Offset(2, 2),
    );
    await tester.pumpAndSettle();
    expect(probe.emitted, isNotEmpty);
    expect(probe.emitted.every((argb) => argb >>> 24 == 0xFF), isTrue);
  });
}
