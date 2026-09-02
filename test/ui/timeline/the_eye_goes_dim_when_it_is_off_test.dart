import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';

/// 🚨★★★유저 (F-58): 「비지블off일경우 색라벨이 불투명도가 낮아지는데. 이거
/// 멋대로 추가한건데 맘에드니 채용. 근데 내가말한건 **비지블off시 비지블버튼
/// 자체를 비활성화색(어둡게)** 하란거였음. 그러니 작업하고, 추가적으로
/// **비지블버튼은 다른곳에서도 쓰니까 공용화/통일화**시켜서 결과적으로
/// **다른곳도 비활성화시 비활성화색 되도록**」.
///
/// ⚠️This is the 「자체를」 half. The 「다른곳도」 half is
/// `test/architecture/one_eye_toggle_test.dart`, which is a SOURCE scan —
/// two eyes that agree today would pass anything written here.
void main() {
  Future<Icon> pumpEye(WidgetTester tester, {required bool visible}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LayerVisibilityToggleButton(
              keyValue: 'eye-under-test',
              isVisible: visible,
              onToggle: () {},
            ),
          ),
        ),
      ),
    );
    return tester.widget<Icon>(
      find.descendant(
        of: find.byType(LayerVisibilityToggleButton),
        matching: find.byType(Icon),
      ),
    );
  }

  testWidgets('ON leaves the glyph in the ambient ink', (tester) async {
    final icon = await pumpEye(tester, visible: true);
    expect(
      icon.color,
      isNull,
      reason: 'nothing overrides it — the button is at rest',
    );
    expect(icon.icon, Icons.visibility);
  });

  testWidgets('OFF dims the BUTTON, not only the row it stands on', (
    tester,
  ) async {
    final off = await pumpEye(tester, visible: false);
    final on = await pumpEye(tester, visible: true);

    expect(off.icon, Icons.visibility_off);
    expect(off.color, isNotNull, reason: '「비지블off시 비지블버튼 자체를 비활성화색(어둡게)」');
    expect(
      off.color!.a,
      closeTo(layerRailOffAlpha, 0.001),
      reason:
          '⛔and in the rail OWN off language — the alpha the onion '
          'and fx icons already wear, so a hidden row reads as off in one '
          'language rather than in three',
    );
    // ★The premise this rests on: the two states really do differ, so the
    // assertion above is not describing a colour both of them have.
    expect(off.color, isNot(on.color));
  });
}
