import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/home_page.dart';

/// 🚨T27 (유저 확정 2026-08-14): 「**옛날처럼 +버튼 오른쪽에 펼치기아이콘으로
/// 버튼** 했었잖아. 그거 그대로하자.」
///
/// The variants used to hang on an 8px band over the `＋`'s top edge, bought
/// with 「a caret costs 16px of the scarce axis, and the top edge costs
/// none」. The width was the cheap part: the `＋` makes an ANIMATION layer and
/// nothing else, so that band was the only route to a storyboard, image or
/// text layer, and a first-time user could not find it (유저: 「그 띠가 너무
/// 알기어렵다고해」).
///
/// What these pin is the SHAPE, because the shape is the whole fix. That the
/// menu opens is already covered elsewhere — it opened from the band too.
const _addPairs = <({String button, String menu})>[
  (button: 'timeline-toolbar-add-layer-button', menu: 'timeline-toolbar-add-layer-menu'),
  (button: 'new-cut-button', menu: 'new-cut-menu'),
];

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 950));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: createDefaultProject())),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every ＋ shows its variants opener BESIDE it, on the right', (
    tester,
  ) async {
    await _pump(tester);

    for (final pair in _addPairs) {
      final button = find.byKey(ValueKey<String>(pair.button));
      final opener = find.byKey(ValueKey<String>(pair.menu));
      expect(button, findsOneWidget, reason: '${pair.button} is on the bar');
      expect(
        opener,
        findsOneWidget,
        reason: '${pair.menu} is a widget of its own now, not a sliver laid '
            'over the button',
      );

      final buttonRect = tester.getRect(button);
      final openerRect = tester.getRect(opener);
      expect(
        openerRect.left,
        greaterThanOrEqualTo(buttonRect.right - 1),
        reason: '${pair.menu} sits to the RIGHT of the ＋, not on top of it',
      );
      // The retired band was 8px tall and pinned to the button's top edge.
      // A caret that is a sibling shares the row's full height, which is
      // what makes it look like a door rather than a hairline.
      expect(
        openerRect.height,
        greaterThan(8),
        reason: '${pair.menu} is a target, not an 8px strip',
      );
      expect(
        openerRect.width,
        lessThan(buttonRect.width),
        reason: 'and it stays narrower than the ＋ — a second door onto that '
            'button, not a second button',
      );
    }
  });

  // ⛔That the opener OPENS is deliberately not re-asserted here.
  // `layer_add_menu_test` already drives that list by the same key — the
  // band's key moved onto the caret unchanged, which is why every test that
  // reached the variants kept working across this change. Repeating it would
  // be a second copy of a covered contract, and the copy is the one that
  // goes stale.
}
