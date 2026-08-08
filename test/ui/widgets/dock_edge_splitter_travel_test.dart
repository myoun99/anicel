import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/dock_edge_splitter.dart';

/// 유저, R4 #13: 왼쪽 끝까지 이동하고, 돌아갈 때가 문제야. 커서가 스플리터까지
/// 가고 나서 오른쪽으로 가야 이동되서 커서랑 맞는 느낌인데, 지금은 어긋난 채로
/// 돌아갈 때 스플리터가 바로 오른쪽으로 이동해버려서 어긋나는 느낌.
///
/// Every splitter owner clamps, and the surplus used to be dropped on the
/// floor. That is what makes an edge that has been pushed to the wall start
/// moving on the first pixel of the return trip and stay ahead of the hand
/// for the rest of the drag.
///
/// This is the widget-level contract, so it holds for every owner at once —
/// the workspace docks, the two rail grips, the region's side insets, and
/// the timeline's layer rail, which is the one the report came from.
void main() {
  /// A splitter over a value with a hard floor and ceiling, returning what
  /// it actually used — the shape every real owner has.
  Future<double Function()> pumpClamped(
    WidgetTester tester, {
    double start = 50,
    double floor = 0,
    double ceiling = 100,
  }) async {
    var value = start;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 40,
              height: 200,
              child: DockEdgeSplitter(
                axis: Axis.vertical,
                onDragDelta: (delta) {
                  final next = (value + delta).clamp(floor, ceiling).toDouble();
                  final used = next - value;
                  value = next;
                  return used;
                },
              ),
            ),
          ),
        ),
      ),
    );
    return () => value;
  }

  testWidgets('travel spent past the wall must be paid back before the edge '
      'moves again', (tester) async {
    final read = await pumpClamped(tester, start: 50, floor: 0, ceiling: 100);

    final grip = find.byType(DockEdgeSplitter);
    final drag = await tester.startGesture(tester.getCenter(grip));

    // Down to the floor, and then 30px PAST it. The edge stops at 0; the
    // hand keeps going.
    await drag.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(read(), 0, reason: 'the wall holds');

    // Coming back 10px must move NOTHING: the hand is still 20px outside
    // where the edge is.
    await drag.moveBy(const Offset(10, 0));
    await tester.pump();
    expect(
      read(),
      0,
      reason: 'the edge waits for the hand to reach it',
    );

    // 20 more closes the gap exactly; the very next pixel is the first the
    // edge is entitled to.
    await drag.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(read(), 0);

    await drag.moveBy(const Offset(15, 0));
    await tester.pump();
    expect(
      read(),
      15,
      reason: 'and from there it tracks 1:1 again',
    );

    await drag.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the ceiling owes the same debt as the floor', (tester) async {
    final read = await pumpClamped(tester, start: 90, floor: 0, ceiling: 100);

    final drag = await tester.startGesture(
      tester.getCenter(find.byType(DockEdgeSplitter)),
    );
    await drag.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(read(), 100);

    await drag.moveBy(const Offset(-25, 0));
    await tester.pump();
    expect(read(), 100, reason: '30 was overshot, so 25 back is still outside');

    await drag.moveBy(const Offset(-10, 0));
    await tester.pump();
    expect(read(), 95, reason: '5 past the debt is 5 of movement');

    await drag.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the debt belongs to ONE drag — a fresh grab starts live', (
    tester,
  ) async {
    // Otherwise letting go at the wall and grabbing again would leave the
    // splitter dead until the hand paid off travel it never made in this
    // gesture.
    final read = await pumpClamped(tester, start: 50, floor: 0, ceiling: 100);

    final grip = find.byType(DockEdgeSplitter);
    final first = await tester.startGesture(tester.getCenter(grip));
    await first.moveBy(const Offset(-90, 0));
    await tester.pump();
    await first.up();
    await tester.pumpAndSettle();
    expect(read(), 0);

    final second = await tester.startGesture(tester.getCenter(grip));
    await second.moveBy(const Offset(12, 0));
    await tester.pump();
    expect(read(), 12, reason: 'the new drag owes nothing');

    await second.up();
    await tester.pumpAndSettle();
  });

  testWidgets('an owner that uses everything is unaffected', (tester) async {
    // The opt-out: returning the delta you were handed is what this widget
    // always did, and unclamped owners must not start lagging.
    var value = 0.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 40,
              height: 200,
              child: DockEdgeSplitter(
                axis: Axis.vertical,
                onDragDelta: (delta) {
                  value += delta;
                  return delta;
                },
              ),
            ),
          ),
        ),
      ),
    );

    final drag = await tester.startGesture(
      tester.getCenter(find.byType(DockEdgeSplitter)),
    );
    await drag.moveBy(const Offset(-40, 0));
    await tester.pump();
    await drag.moveBy(const Offset(15, 0));
    await tester.pump();
    expect(value, -25);

    await drag.up();
    await tester.pumpAndSettle();
  });
}
