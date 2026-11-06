import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../helpers/room_for_the_pills.dart';
import 'flyout_test_helpers.dart';

/// Commands that used to exist ONLY in the top menu bar now also reach the
/// surface where their result shows up — the timeline's Layer ▾ and Cut ▾
/// flyouts. The menu bar is going away; these are the entrances that have
/// to outlive it, so each one is pinned here by key.
void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(appWindowWithRoomForItsPills);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
  }

  Future<void> expectInFlyout(WidgetTester tester, String itemKey) async {
    await openOwningFlyout(tester, itemKey);
    expect(
      find.byKey(ValueKey<String>(itemKey)),
      findsOneWidget,
      reason: '$itemKey should be reachable from its flyout',
    );
    await dismissFlyout(tester);
  }

  // ↩️The relocated LAYER commands had their test here. R5 #14 took the two
  // folder-making commands out of the Layer menu, and I-120-Q11 (「하나만
  // 남기도록」) took RASTERIZE, the last of them, to the rail's header.

  testWidgets('the relocated CUT commands reach the Cut flyouts', (
    tester,
  ) async {
    await pumpHome(tester);

    // F-455 (유저 2026-10-23): 「종류버튼의 겸용컷 만들기는 컷 버튼으로
    // 옮김. 겸용컷 변환 위」. ↩️It sat under the New-cut split button, with
    // the other ways of making a cut.
    await expectInFlyout(tester, 'add-cut-create-linked');
    await expectInFlyout(tester, 'convert-cut-to-linked-button');
  });
}
