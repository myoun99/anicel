import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/stylus_glide_stop.dart';

/// PEN-9: a stylus approach stops a COASTING scroll (mid-glide the
/// viewport ignore-pointers its children, so a pen landing right after a
/// touch fling scrolls instead of selecting); a live finger drag is never
/// interrupted, and a mouse changes nothing.
void main() {
  late ScrollController controller;

  Widget harness() {
    return MaterialApp(
      home: Scaffold(
        body: StylusGlideStop(
          controllers: [controller],
          child: ListView.builder(
            controller: controller,
            itemExtent: 40,
            itemCount: 200,
            itemBuilder: (context, index) => Text('row $index'),
          ),
        ),
      ),
    );
  }

  setUp(() {
    controller = ScrollController();
  });
  tearDown(() => controller.dispose());

  Future<TestGesture> hoverAt(
    WidgetTester tester,
    Offset location, {
    required PointerDeviceKind kind,
  }) async {
    final gesture = await tester.createGesture(kind: kind, pointer: 77);
    await gesture.addPointer(location: location);
    await gesture.moveTo(location + const Offset(1, 1));
    await tester.pump();
    return gesture;
  }

  testWidgets('a coasting fling STOPS on stylus hover', (tester) async {
    await tester.pumpWidget(harness());
    await tester.fling(find.byType(ListView), const Offset(0, -400), 2000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.position.isScrollingNotifier.value, isTrue);

    final gesture = await hoverAt(
      tester,
      tester.getCenter(find.byType(ListView)),
      kind: PointerDeviceKind.stylus,
    );
    final stoppedAt = controller.offset;
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      controller.offset,
      stoppedAt,
      reason: 'the pen approach must freeze the glide',
    );
    await gesture.removePointer();
    await tester.pumpAndSettle();
  });

  testWidgets('a MOUSE hover leaves the coast alone', (tester) async {
    await tester.pumpWidget(harness());
    await tester.fling(find.byType(ListView), const Offset(0, -400), 2000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final gesture = await hoverAt(
      tester,
      tester.getCenter(find.byType(ListView)),
      kind: PointerDeviceKind.mouse,
    );
    final at = controller.offset;
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      controller.offset,
      greaterThan(at),
      reason: 'a mouse changes nothing — the glide keeps coasting',
    );
    await gesture.removePointer();
    await tester.pumpAndSettle();
  });

  testWidgets('a live FINGER drag is never yanked by a pen hover', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    final center = tester.getCenter(find.byType(ListView));
    final finger = await tester.startGesture(
      center,
      kind: PointerDeviceKind.touch,
    );
    await finger.moveBy(const Offset(0, -60));
    await tester.pump();
    final midDrag = controller.offset;
    expect(midDrag, greaterThan(0));

    final pen = await hoverAt(
      tester,
      center + const Offset(40, 0),
      kind: PointerDeviceKind.stylus,
    );
    await finger.moveBy(const Offset(0, -30));
    await tester.pump();
    expect(
      controller.offset,
      greaterThan(midDrag),
      reason: 'the finger drag keeps scrolling through the pen hover',
    );
    await finger.up();
    await pen.removePointer();
    await tester.pumpAndSettle();
  });
}
