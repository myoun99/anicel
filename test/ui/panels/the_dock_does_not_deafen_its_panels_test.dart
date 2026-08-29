import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/input/pen_friendly_scroll_controller.dart';

/// 🚨★★★A SCROLLING LIST DEAFENS ITS CHILDREN, AND THE DOCK'S CHILDREN ARE
/// THE PANELS.
///
/// 유저 2026-08-29: 「패널 하나만 띄우면 정상적으로 패널만 터치작동하는데
/// 띠의 패널 여러개띄워서 **다중패널 세로스크롤바 활성되있으면 버그나서
/// 뒤의 캔버스패널의 터치가 작동**함」.
///
/// A `ScrollPosition` ignore-pointers the viewport's children for the life
/// of any scroll activity — a drag, and a ballistic coast after it. The
/// timeline hit this first and `PenFriendlyScrollController` was written
/// for it; a dock is not a timeline, so it never got the fix.
///
/// ⛔This pins the POSITION's contract rather than the dock's widget tree:
/// the widget is free to change, the rule is not.
void main() {
  testWidgets('a plain position deafens its children while it coasts', (
    tester,
  ) async {
    // The control, and it is the defect itself — this is what the dock did.
    final plain = ScrollController();
    addTearDown(plain.dispose);
    await tester.pumpWidget(_host(plain));
    await tester.pump();

    await tester.fling(
      find.byType(ListView),
      const Offset(0, -300),
      1000,
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      plain.position.activity,
      isA<BallisticScrollActivity>(),
      reason: 'the fling must actually be coasting, or nothing is measured',
    );
    expect(
      _ignoring(tester),
      isTrue,
      reason:
          'a plain position hides its children from hit testing while it '
          'coasts — this is the state a pen lands into',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('🚨the PEN-FRIENDLY position keeps them hittable', (
    tester,
  ) async {
    final friendly = PenFriendlyScrollController();
    addTearDown(friendly.dispose);
    await tester.pumpWidget(_host(friendly));
    await tester.pump();

    (friendly.position as PenFriendlyScrollPosition).penNearby = true;

    await tester.fling(
      find.byType(ListView),
      const Offset(0, -300),
      1000,
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      friendly.position.activity,
      isA<BallisticScrollActivity>(),
      reason: 'same state as the control above',
    );
    expect(
      _ignoring(tester),
      isFalse,
      reason:
          'with a pen nearby a COASTING list stays hittable, so the panel '
          'under the pen answers instead of the canvas behind it',
    );
    await tester.pumpAndSettle();
  });
}

/// The render object, NOT the widget: `setIgnorePointer` writes
/// `RenderIgnorePointer.ignoring` directly and never rebuilds, so the
/// widget's own field still reads its build-time value. 🧪Measured — the
/// widget said false while the render object said true.
bool _ignoring(WidgetTester tester) => tester
    .renderObjectList<RenderIgnorePointer>(
      find.descendant(
        of: find.byType(Scrollable),
        matching: find.byType(IgnorePointer),
      ),
    )
    .any((render) => render.ignoring);

Widget _host(ScrollController controller) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 220,
      height: 200,
      child: ListView(
        controller: controller,
        children: [for (var i = 0; i < 10; i++) const SizedBox(height: 80)],
      ),
    ),
  ),
);
