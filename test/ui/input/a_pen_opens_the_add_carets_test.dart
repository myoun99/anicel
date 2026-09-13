import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';

/// 🚨F-120 (유저 2026-09-13): 「펜으로 레이어나 컷이나 +버튼 옆의 생성할 레이어
/// 여는 버튼같은게 작동안함. 마우스로는 작동함. 펜이라 클릭중에 커서 위치
/// 바뀌는데 그게 영향이 있을것으로 추측? 그런 커서 위치따라 판정하는거 없도록.
/// 애초에 공용버튼아닌가?」
///
/// The guess was right. The caret beside every `＋` mounted the press claim
/// but opened its menu from a gesture-arena TAP, and the claim takes the arena
/// on the first movement — so a press that moved at all lost its tap. A still
/// mouse click never moves; a pen always does. The existing opener tests TAP,
/// which never moves either, so nothing measured the hand the user actually
/// holds.
///
/// ⛔Every device, not only the pen: the law is 「released inside the control」
/// for all of them (`control_press_claim.dart`), and a mouse that wobbles two
/// pixels failed the same way — it just rarely wobbles.
const _carets = <({String menu, String entry})>[
  (menu: 'timeline-toolbar-add-layer-menu', entry: 'add-layer-kind-animation'),
  (menu: 'new-cut-menu', entry: 'add-cut-new'),
];

void main() {
  setUp(debugClearValueControlPointers);
  tearDown(debugClearValueControlPointers);

  for (final kind in const [
    PointerDeviceKind.stylus,
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
  ]) {
    for (final caret in _carets) {
      testWidgets('${kind.name}: ${caret.menu} opens on a press that moves', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(1400, 950));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(home: HomePage(initialProject: createDefaultProject())),
        );
        await tester.pumpAndSettle();

        final opener = find.byKey(ValueKey<String>(caret.menu));
        final entry = find.byKey(ValueKey<String>(caret.entry));
        expect(opener, findsOneWidget);
        expect(entry, findsNothing, reason: 'the menu starts closed');

        final gesture = await tester.startGesture(
          tester.getCenter(opener),
          kind: kind,
        );
        await gesture.moveBy(const Offset(0, 2));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveBy(const Offset(0, -1));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          entry,
          findsOneWidget,
          reason:
              'a press released inside the caret opens it, however much the '
              'hand moved on the way — 「그런 커서 위치따라 판정하는거 없도록」',
        );
      });
    }
  }
}
