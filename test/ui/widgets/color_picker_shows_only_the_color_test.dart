import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/color/color_slot_pair.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/color_swatch_button.dart';

/// **F-23 — the picker stopped saying what your finger is already on.**
///
/// 유저 2026-08-24: 「지금 캔버스패널 색 선택시 왼쪽위에 **캔버스라고 써있거나
/// 하는데, 그거 그냥 제거. 안뜨도록.** 오른쪽에 있는 **선택된 색 보여주는것도
/// 어차피 버튼자체가 색 보여주는거니까 겹치니까 삭제.** 대신 해당 위치에
/// **현재 색 반영** 이라는 버튼 추가 … 그리고 아래에 컬러 패널처럼 **hex나
/// RGB있는거 그대로 로직 재사용** … 그리고 **색 보여주는건 싹 다 일반
/// 동그라미로 변경**」
void main() {
  Future<List<int>> pumpAndOpen(
    WidgetTester tester, {
    int color = 0xFF102030,
    int current = 0xFFAABBCC,
  }) async {
    final picked = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: ColorSwatchButton(
              keyValue: 'probe-color-button',
              color: color,
              currentColorOf: () => current,
              onChanged: picked.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('probe-color-button')));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('it opens with no title and no second swatch', (tester) async {
    await pumpAndOpen(tester);

    expect(
      find.byKey(const ValueKey<String>('color-picker-wheel')),
      findsOneWidget,
      reason: 'fixture premise: the picker is open',
    );
    expect(
      find.byKey(const ValueKey<String>('color-picker-preview')),
      findsNothing,
      reason: 'the trigger IS the preview — 「겹치니까 삭제」',
    );
    expect(
      find.text('Canvas'),
      findsNothing,
      reason: 'the window no longer names the colour it was opened for',
    );
  });

  testWidgets('「현재 색 반영」 takes the tool colour', (tester) async {
    final picked = await pumpAndOpen(tester, current: 0xFFAABBCC);

    await tester.tap(
      find.byKey(const ValueKey<String>('color-picker-use-current')),
    );
    await tester.pumpAndSettle();

    expect(picked, isNotEmpty);
    expect(
      picked.last,
      0xFFAABBCC,
      reason: 'the button copies the colour the tool is on right now',
    );
  });

  testWidgets('and the readout below it is the colour window\'s own', (
    tester,
  ) async {
    final picked = await pumpAndOpen(tester);

    expect(
      find.byKey(const ValueKey<String>('color-picker-status')),
      findsOneWidget,
      reason: '「hex나 RGB있는거 그대로 로직 재사용」',
    );

    // Typing a hex there moves the picker, because both write one colour.
    await tester.tap(find.byKey(const ValueKey<String>('color-status-hex')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('color-status-hex-input')),
      '336699',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(picked.last, 0xFF336699);
  });

  testWidgets('every swatch that shows a colour is a circle', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: ColorSlotPair(
              foreground: const Color(0xFF112233),
              background: const Color(0xFF445566),
              onBackgroundTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final key in [
      'color-wheel-foreground-swatch',
      'color-wheel-background-swatch',
    ]) {
      final box = tester.widget<Container>(
        find.byKey(ValueKey<String>(key)),
      );
      expect(
        (box.decoration! as BoxDecoration).shape,
        BoxShape.circle,
        reason: '$key — 「색 보여주는건 싹 다 일반 동그라미로 변경」',
      );
    }
  });

  test('the button label is a translated string, not typed Korean', () {
    expect(AppText.strings.colorUseCurrent, isNotEmpty);
  });
}
