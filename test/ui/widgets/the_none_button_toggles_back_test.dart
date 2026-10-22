import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/color_swatch_button.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';

/// 🗣️F-425 (유저 2026-10-21): 「캔버스 용지 색 변경 등, 지금 없음버튼
/// 누르면 없음인데, 애초에 있는 상태는 글자 있음, 강조색으로. 즉 누를때마다
/// 토글이란느낌. 기존에 누를때마다 글자색이나 색 변경하는거 버튼 있으니
/// 공용/통일」 — the colour window's 「없음」 is the shared yes/no pill, and a
/// press on it brings the plane back as it was.
void main() {
  Future<({List<int> emitted, List<void> nones})> open(
    WidgetTester tester, {
    required int color,
    required bool none,
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
              keepsAlpha: true,
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

  const noneKey = ValueKey<String>('color-picker-none');
  Pill pill(WidgetTester tester) => tester.widget<Pill>(find.byKey(noneKey));
  FieldSlider bar(WidgetTester tester) => tester.widget<FieldSlider>(
    find.byKey(const ValueKey<String>('color-picker-opacity')),
  );

  Future<void> press(WidgetTester tester) async {
    await tester.tap(find.byKey(noneKey));
    await tester.pumpAndSettle();
  }

  testWidgets('a plane that is there: lit, 「있음」', (tester) async {
    await open(tester, color: 0x80336699, none: false);
    expect(pill(tester).selected, isTrue);
    expect(pill(tester).label, AppText.strings.colorPresent);
  });

  testWidgets('a press takes the plane away: plain, 「없음」, the bar dim', (
    tester,
  ) async {
    final probe = await open(tester, color: 0x80336699, none: false);
    await press(tester);
    expect(probe.nones, hasLength(1));
    expect(pill(tester).selected, isFalse);
    expect(pill(tester).label, AppText.strings.colorNone);
    expect(bar(tester).restingAccent, AppColors.textDim);
  });

  testWidgets('the next press brings it back as it was — its colour and its '
      'opacity — and lights the pill and the bar again', (tester) async {
    final probe = await open(tester, color: 0x80336699, none: false);
    await press(tester);
    await press(tester);
    expect(probe.nones, hasLength(1), reason: 'coming back is no 「없음」');
    expect(probe.emitted, [0x80336699]);
    expect(pill(tester).selected, isTrue);
    expect(pill(tester).label, AppText.strings.colorPresent);
    expect(bar(tester).restingAccent, isNull);
  });

  testWidgets('a window opened on an absent plane says 「없음」, and a press '
      'brings back the colour the plane kept', (tester) async {
    final probe = await open(tester, color: 0xFF336699, none: true);
    expect(pill(tester).selected, isFalse);
    expect(pill(tester).label, AppText.strings.colorNone);
    await press(tester);
    expect(probe.emitted, [0xFF336699]);
    expect(probe.nones, isEmpty);
    expect(pill(tester).selected, isTrue);
  });
}
