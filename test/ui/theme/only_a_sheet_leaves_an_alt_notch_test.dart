import 'package:anicel/src/ui/theme/app_scroll_behavior.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🗣️I-155: a notch turned with Alt held zooms a sheet, and a sheet's own
/// scrollers leave it to the zoom (`SheetScrollPhysics`) — the physics the
/// app hands every scroller. Every OTHER scroller still takes it.
void main() {
  testWidgets('⛔a list that is no sheet scrolls on a notch with Alt held', (
    tester,
  ) async {
    final list = ScrollController();
    addTearDown(list.dispose);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: ListView(
          controller: list,
          children: [
            for (var i = 0; i < 60; i += 1)
              SizedBox(height: 40, child: Text('$i')),
          ],
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(100, 100)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    expect(list.offset, greaterThan(0));
  });
}
