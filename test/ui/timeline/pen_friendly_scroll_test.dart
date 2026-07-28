import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/pen_friendly_scroll_controller.dart';

/// PEN-10: while [PenFriendlyScrollPosition.penNearby] is set, a COASTING
/// viewport keeps its children hittable (the framework hides them for the
/// whole life of any scroll activity); without it the framework default
/// stands, and a live finger drag always keeps the default.
void main() {
  late PenFriendlyScrollController controller;

  setUp(() => controller = PenFriendlyScrollController());
  tearDown(() => controller.dispose());

  Widget harness(VoidCallback onChildTap) {
    return MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          controller: controller,
          itemExtent: 40,
          itemCount: 200,
          itemBuilder: (context, index) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onChildTap,
            child: Text('row $index'),
          ),
        ),
      ),
    );
  }

  testWidgets('mid-coast taps only reach children while penNearby', (
    tester,
  ) async {
    var childTaps = 0;
    await tester.pumpWidget(harness(() => childTaps += 1));

    // Baseline: the framework default — a tap during the coast stops the
    // glide and never reaches a child.
    await tester.fling(find.byType(ListView), const Offset(0, -400), 2000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.position.isScrollingNotifier.value, isTrue);
    await tester.tap(find.byType(ListView), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(childTaps, 0);

    // penNearby: the same mid-coast tap hits the child.
    await tester.fling(find.byType(ListView), const Offset(0, -400), 2000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.position.isScrollingNotifier.value, isTrue);
    (controller.position as PenFriendlyScrollPosition).penNearby = true;
    await tester.tap(find.byType(ListView), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(childTaps, 1, reason: 'penNearby must restore the child hit-test');
  });

  testWidgets('a live finger DRAG keeps ignoring children even penNearby', (
    tester,
  ) async {
    var childTaps = 0;
    await tester.pumpWidget(harness(() => childTaps += 1));
    (controller.position as PenFriendlyScrollPosition).penNearby = true;

    final center = tester.getCenter(find.byType(ListView));
    final finger = await tester.startGesture(
      center,
      kind: PointerDeviceKind.touch,
    );
    await finger.moveBy(const Offset(0, -40));
    await tester.pump();
    await finger.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(controller.offset, greaterThan(0));

    // A second finger tapping mid-drag must not press a cell (the drag
    // protection the framework default exists for).
    final tapper = await tester.startGesture(
      center + const Offset(60, 0),
      kind: PointerDeviceKind.touch,
      pointer: 9,
    );
    await tapper.up();
    await tester.pump();
    expect(childTaps, 0, reason: 'drag protection stays untouched');

    await finger.up();
    await tester.pumpAndSettle();
  });
}
