import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/axis_gesture_detector.dart';

/// The one recogniser family, chosen by the axis — and the OTHER family is
/// not mounted. Both claims for both axes, because a widget that got one of
/// the four wrong would still pass a test that drags only one way.
///
/// ⚠️「The other family is absent」 cannot be shown by dragging the other way
/// and seeing nothing: a lone recogniser wins the arena on the pointer's
/// down whatever direction it then moves. It is shown on the detector
/// itself — which handlers it mounted — and by the delta it reports, which
/// is along ITS axis (a move across it reads 0).
void main() {
  Future<List<String>> drive(
    WidgetTester tester,
    Axis axis,
    Offset move,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: AxisGestureDetector(
            axis: axis,
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onDragDown: (_) => log.add('down'),
            onDragStart: (_) => log.add('start'),
            onDragUpdate: (d) => log.add('update ${d.primaryDelta!.round()}'),
            onDragEnd: (_) => log.add('end'),
            onDragCancel: () => log.add('cancel'),
            child: const SizedBox(width: 200, height: 200),
          ),
        ),
      ),
    );
    final centre = tester.getCenter(find.byType(AxisGestureDetector));
    final gesture = await tester.startGesture(centre);
    await gesture.moveBy(move);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    return log;
  }

  GestureDetector mounted(WidgetTester tester) =>
      tester.widget<GestureDetector>(find.byType(GestureDetector));

  testWidgets('horizontal: a drag along x fires, with the delta along x', (
    tester,
  ) async {
    final log = await drive(tester, Axis.horizontal, const Offset(40, 0));
    expect(log, ['down', 'start', 'update 40', 'end']);
  });

  testWidgets('horizontal: the vertical family is not mounted, and a move '
      'along y reads 0', (tester) async {
    final log = await drive(tester, Axis.horizontal, const Offset(0, 40));
    expect(log, ['down', 'start', 'update 0', 'end']);
    final d = mounted(tester);
    expect(d.onHorizontalDragStart, isNotNull);
    expect(d.onHorizontalDragUpdate, isNotNull);
    expect(d.onVerticalDragDown, isNull);
    expect(d.onVerticalDragStart, isNull);
    expect(d.onVerticalDragUpdate, isNull);
    expect(d.onVerticalDragEnd, isNull);
    expect(d.onVerticalDragCancel, isNull);
  });

  testWidgets('vertical: a drag along y fires, with the delta along y', (
    tester,
  ) async {
    final log = await drive(tester, Axis.vertical, const Offset(0, 40));
    expect(log, ['down', 'start', 'update 40', 'end']);
  });

  testWidgets('vertical: the horizontal family is not mounted, and a move '
      'along x reads 0', (tester) async {
    final log = await drive(tester, Axis.vertical, const Offset(40, 0));
    expect(log, ['down', 'start', 'update 0', 'end']);
    final d = mounted(tester);
    expect(d.onVerticalDragStart, isNotNull);
    expect(d.onVerticalDragUpdate, isNotNull);
    expect(d.onHorizontalDragDown, isNull);
    expect(d.onHorizontalDragStart, isNull);
    expect(d.onHorizontalDragUpdate, isNull);
    expect(d.onHorizontalDragEnd, isNull);
    expect(d.onHorizontalDragCancel, isNull);
  });

  testWidgets('a tap-down on the surface is axis-free', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: AxisGestureDetector(
            axis: Axis.vertical,
            // An empty box is not hit-testable on its own; the surface is.
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => taps++,
            child: const SizedBox(width: 200, height: 200),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(AxisGestureDetector));
    expect(taps, 1);
  });
}
