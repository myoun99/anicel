import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/axis_bar_gesture.dart';
import 'package:anicel/src/ui/widgets/dock_edge_splitter.dart';

/// 「바는 자기 축을 따라 움직인 것을 지킨다」 — the law, and the splitter that
/// now rides it (⑧ 유저 2026-08-12: 「펜 갖다대면 5번중 1번만 성공함」).
///
/// 🚨The pure-function group below could pass with the splitter still on
/// `GestureDetector`, so the widget group DRIVES A STYLUS. That is the whole
/// bug: a mouse never had a rival and always worked.
void main() {
  group('the law', () {
    test('travel ALONG the bar is the bar\'s, however far it goes', () {
      expect(
        rivalOwnsGesture(
          dragAxis: Axis.horizontal,
          travelSinceDown: const Offset(400, 0),
          rivalSlop: 18,
        ),
        isFalse,
      );
    });

    test('travel ACROSS it hands the gesture over at the RIVAL\'s threshold', () {
      // Just under, and just over — the number is the rival's, so the test
      // states it rather than a constant of ours.
      expect(
        rivalOwnsGesture(
          dragAxis: Axis.horizontal,
          travelSinceDown: const Offset(0, 17),
          rivalSlop: 18,
        ),
        isFalse,
      );
      expect(
        rivalOwnsGesture(
          dragAxis: Axis.horizontal,
          travelSinceDown: const Offset(0, 18),
          rivalSlop: 18,
        ),
        isTrue,
      );
    });

    test('it reads the axis, not the distance — a long diagonal along the '
        'bar is still the bar\'s', () {
      // 400px of travel, 4 of it across. A distance rule would have handed
      // this over five times over; the axis rule keeps it.
      expect(
        rivalOwnsGesture(
          dragAxis: Axis.horizontal,
          travelSinceDown: const Offset(400, 4),
          rivalSlop: 18,
        ),
        isFalse,
      );
    });

    test('the sign does not matter — across is across', () {
      for (final dy in [30.0, -30.0]) {
        expect(
          rivalOwnsGesture(
            dragAxis: Axis.horizontal,
            travelSinceDown: Offset(0, dy),
            rivalSlop: 18,
          ),
          isTrue,
        );
      }
    });

    test('a VERTICAL bar swaps which component is across', () {
      expect(
        rivalOwnsGesture(
          dragAxis: Axis.vertical,
          travelSinceDown: const Offset(0, 400),
          rivalSlop: 18,
        ),
        isFalse,
      );
      expect(
        rivalOwnsGesture(
          dragAxis: Axis.vertical,
          travelSinceDown: const Offset(30, 0),
          rivalSlop: 18,
        ),
        isTrue,
      );
    });
  });

  group('the splitter under a scroller', () {
    /// A vertical splitter (dragged left-right) sitting inside a VERTICAL
    /// scroll view — the rail's real shape, and the arena the pen was losing.
    Widget harness(void Function(double) onDelta) => MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            const SizedBox(height: 400),
            SizedBox(
              height: 200,
              child: DockEdgeSplitter(
                axis: Axis.vertical,
                onDragDelta: (delta) {
                  onDelta(delta);
                  return delta;
                },
              ),
            ),
            const SizedBox(height: 400),
          ],
        ),
      ),
    );

    testWidgets('a STYLUS drag moves it — no arena to win first', (
      tester,
    ) async {
      final deltas = <double>[];
      await tester.pumpWidget(harness(deltas.add));

      final grip = find.byType(DockEdgeSplitter);
      final gesture = await tester.startGesture(
        tester.getCenter(grip),
        kind: PointerDeviceKind.stylus,
      );
      // A real pen never travels on one axis: this is the diagonal that used
      // to let the scroller cross its threshold first and take the gesture
      // before the splitter had seen a single update.
      await gesture.moveBy(const Offset(12, 3));
      await tester.pump();
      await gesture.moveBy(const Offset(12, 2));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(
        deltas,
        isNotEmpty,
        reason: 'the pen must move the edge on the FIRST try, not one in five',
      );
      expect(deltas.reduce((a, b) => a + b), closeTo(24, 0.01));
    });

    testWidgets('a mouse still works — it never had a rival', (tester) async {
      final deltas = <double>[];
      await tester.pumpWidget(harness(deltas.add));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(DockEdgeSplitter)),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(deltas.reduce((a, b) => a + b), closeTo(20, 0.01));
    });

    testWidgets('travel ACROSS the grip hands it back to the scroller, and '
        'what already moved STAYS moved', (tester) async {
      final deltas = <double>[];
      await tester.pumpWidget(harness(deltas.add));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(DockEdgeSplitter)),
        kind: PointerDeviceKind.stylus,
      );
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump();
      final beforeYield = deltas.fold<double>(0, (a, b) => a + b);
      expect(beforeYield, closeTo(6, 0.01));

      // Now a real scroll: straight down, past the rival's slop.
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      await gesture.moveBy(const Offset(9, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(
        deltas.fold<double>(0, (a, b) => a + b),
        closeTo(beforeYield, 0.01),
        reason: 'once the scroller owns it the edge stops taking travel — and '
            'the 6px it already took is NOT rolled back, because an edge that '
            'springs home is the optimistic-revert the user banned',
      );
    });
  });
}
