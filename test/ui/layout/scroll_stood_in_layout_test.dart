import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/layout/scroll_stood_in_layout.dart';

/// 🚨A SCROLLABLE ASKED TO STAND SOMEWHERE STANDS THERE IN THE FRAME ITS
/// CONTENT IS LAID OUT IN (card
/// the-media-button-lights-but-no-media-panel-shows, 2026-11-15).
///
/// Every case pumps ONE frame after asking: a jump that lands a frame later
/// is the defect — the content drawn where the old offset puts it, then
/// moved (「한프레임 보이는건 무조건걸리고 싫어」, 유저 2026-08-12).
void main() {
  const window = 200.0;

  Future<void> pumpContent(
    WidgetTester tester,
    ScrollController controller, {
    required double content,
    ScrollStand? stand,
  }) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 100,
          height: window,
          child: SingleChildScrollView(
            controller: controller,
            child: ScrollStoodInLayout(
              controller: controller,
              stand: stand,
              child: SizedBox(height: content),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('it stands where it is asked in the frame its content grows '
      'in — past where the old content ended', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpContent(tester, controller, content: 300);
    expect(controller.position.maxScrollExtent, 100);

    await pumpContent(
      tester,
      controller,
      content: 600,
      stand: (asking: 1, pixels: 350),
    );

    expect(controller.offset, 350);
  });

  testWidgets('asked past the content\'s end, it stands at the end', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpContent(tester, controller, content: 300);

    await pumpContent(
      tester,
      controller,
      content: 600,
      stand: (asking: 1, pixels: 10000),
    );

    expect(controller.offset, 400);
  });

  testWidgets('content that did not change is stood too', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpContent(tester, controller, content: 600);
    expect(controller.offset, 0);

    await pumpContent(
      tester,
      controller,
      content: 600,
      stand: (asking: 1, pixels: 120),
    );

    expect(controller.offset, 120);
  });

  testWidgets('an asking is answered once: scrolled away from, it is not '
      'gone back to — built again, or laid out again', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpContent(tester, controller, content: 600);
    const stand = (asking: 1, pixels: 120.0);
    await pumpContent(tester, controller, content: 600, stand: stand);
    expect(controller.offset, 120);

    controller.jumpTo(10);
    await tester.pump();
    // Built again with the asking it has answered…
    await pumpContent(tester, controller, content: 600, stand: stand);
    expect(controller.offset, 10, reason: 'built again');
    // …and its content laid out again.
    await pumpContent(tester, controller, content: 700, stand: stand);
    expect(controller.offset, 10, reason: 'laid out again');

    // The next asking is another.
    await pumpContent(
      tester,
      controller,
      content: 700,
      stand: (asking: 2, pixels: 300),
    );
    expect(controller.offset, 300);
  });
}
