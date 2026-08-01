import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/timeline/layer_rail_columns.dart';
import 'package:anicel/src/ui/timeline/layer_rail_window.dart';

/// The rail-window model, pinned:
///
/// > the rail is always laid out at its natural size; the splitter sizes a
/// > window over it and the tail is simply cut off.
///
/// Everything the round deleted (whole-header scale-down, per-surface
/// header layout arithmetic, the drop-a-control-at-a-time ladder) was an
/// answer to the same question this file now answers once.
void main() {
  group('LayerRailExtent', () {
    test('untouched, a rail is as wide as it naturally is', () {
      final extent = LayerRailExtent();
      expect(extent.value, isNull);
      expect(extent.windowExtent(434), 434);
      expect(extent.windowExtent(372), 372);
    });

    test('the floor is the leading cluster plus one name character', () {
      // Derived, not typed: a new control slot moves the floor with it.
      expect(layerRailMinimumWindowExtent, layerRailLeadingWidth + 14);
      final extent = LayerRailExtent();
      extent.resizeBy(-1000, naturalExtent: 434);
      expect(extent.windowExtent(434), layerRailMinimumWindowExtent);
    });

    test('natural is the ceiling — dragging past it opens no gap', () {
      final extent = LayerRailExtent()..resizeBy(1000, naturalExtent: 434);
      expect(extent.windowExtent(434), 434);
      // And the drag back out of the ceiling is immediate: nothing
      // accumulated past it that has to be spent first.
      extent.resizeBy(-100, naturalExtent: 434);
      expect(extent.windowExtent(434), 334);
    });

    test('a natural extent below the floor still yields the floor', () {
      final extent = LayerRailExtent();
      expect(extent.windowExtent(20), layerRailMinimumWindowExtent);
    });

    test('reset goes back to natural, and the push goes home with it', () {
      final extent = LayerRailExtent()..resizeBy(-200, naturalExtent: 434);
      expect(extent.value, isNotNull);
      extent.pushTo(999, naturalExtent: 434);
      expect(extent.offset.value, greaterThan(0));

      extent.reset();
      expect(extent.value, isNull);
      expect(extent.windowExtent(434), 434);
      // At the natural size there is nothing to push into, so a surviving
      // offset is invisible until the NEXT narrowing drag — at which point
      // the rail would jump to its tail.
      expect(extent.offset.value, 0);
    });

    test('a resize notifies (that is what the debounced save listens to)', () {
      final extent = LayerRailExtent();
      var notifications = 0;
      extent.addListener(() => notifications += 1);
      extent.resizeBy(-100, naturalExtent: 434);
      expect(notifications, 1);
      // At the floor there is nothing left to give, so nothing is saved.
      extent.resizeBy(-10000, naturalExtent: 434);
      extent.resizeBy(-10, naturalExtent: 434);
      expect(notifications, 2);
    });

    test('a push is clamped to what the rail can give', () {
      final extent = LayerRailExtent()..resizeBy(-134, naturalExtent: 434);
      expect(extent.windowExtent(434), 300);
      extent.pushTo(1000, naturalExtent: 434);
      expect(extent.offset.value, 134);
      extent.pushTo(-50, naturalExtent: 434);
      expect(extent.offset.value, 0);
    });

    test('widening the window pulls the pushed tail back into view', () {
      final extent = LayerRailExtent()..resizeBy(-234, naturalExtent: 434);
      extent.pushTo(1000, naturalExtent: 434);
      expect(extent.offset.value, 234);
      extent.resizeBy(200, naturalExtent: 434);
      // 400 wide leaves only 34 to be pushed into — without the follow-up
      // clamp the tail would have stayed off-screen and snapped back the
      // next time the window narrowed.
      expect(extent.offset.value, 34);
    });

    test('a push does not notify the SIZE listeners', () {
      final extent = LayerRailExtent();
      var sizeNotifications = 0;
      extent.addListener(() => sizeNotifications += 1);
      extent.resizeBy(-134, naturalExtent: 434);
      extent.pushTo(50, naturalExtent: 434);
      expect(extent.offset.value, 50);
      expect(sizeNotifications, 1);
    });
  });

  group('LayerRailWindow', () {
    Future<void> pumpWindow(
      WidgetTester tester, {
      required Axis axis,
      required LayerRailExtent rail,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: LayerRailWindow(
                axis: axis,
                rail: rail,
                naturalExtent: 400,
                child: Container(
                  key: const ValueKey<String>('rail-content'),
                  width: axis == Axis.horizontal ? null : 60,
                  height: axis == Axis.horizontal ? 60 : null,
                  color: const Color(0xFF00FF00),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('the rail keeps its natural extent inside a narrow window', (
      tester,
    ) async {
      final rail = LayerRailExtent()..resizeBy(-250, naturalExtent: 400);
      addTearDown(rail.dispose);
      await pumpWindow(tester, axis: Axis.horizontal, rail: rail);

      final content = find.byKey(const ValueKey<String>('rail-content'));
      // Nothing inside rearranged: the rail is still 400 wide, the box
      // around it is 150, and the difference is a CUT.
      expect(tester.getSize(content).width, 400);
      expect(tester.getSize(find.byType(LayerRailWindow)).width, 150);
      // Across the axis the window is transparent — the child's own size
      // comes back untouched.
      expect(tester.getSize(find.byType(LayerRailWindow)).height, 60);
    });

    testWidgets('pushing the window slides the rail under it', (tester) async {
      final rail = LayerRailExtent()..resizeBy(-250, naturalExtent: 400);
      addTearDown(rail.dispose);
      await pumpWindow(tester, axis: Axis.horizontal, rail: rail);
      final content = find.byKey(const ValueKey<String>('rail-content'));
      final windowLeft = tester.getTopLeft(find.byType(LayerRailWindow)).dx;
      expect(tester.getTopLeft(content).dx, windowLeft);

      rail.pushTo(100, naturalExtent: 400);
      await tester.pump();
      expect(tester.getTopLeft(content).dx, windowLeft - 100);

      // The push is clamped to the tail: 400 − 150.
      rail.pushTo(9999, naturalExtent: 400);
      await tester.pump();
      expect(tester.getTopLeft(content).dx, windowLeft - 250);
    });

    testWidgets('a control pushed out of the window cannot be tapped', (
      tester,
    ) async {
      // The push is a PAINT offset now, not a parentData one, so the
      // clip's hit-test contract is the render object's own business —
      // worth pinning rather than assuming.
      final rail = LayerRailExtent()..resizeBy(-250, naturalExtent: 400);
      addTearDown(rail.dispose);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: LayerRailWindow(
                axis: Axis.horizontal,
                rail: rail,
                naturalExtent: 400,
                child: SizedBox(
                  width: 400,
                  height: 60,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      key: const ValueKey<String>('tail-button'),
                      // Opaque: a bare SizedBox hit-tests as nothing, and
                      // the default deferToChild would make this pass for
                      // the wrong reason.
                      behavior: HitTestBehavior.opaque,
                      onTap: () => taps += 1,
                      child: const SizedBox(width: 100, height: 60),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // The button sits in the rail's tail, outside the 150px window.
      final button = find.byKey(const ValueKey<String>('tail-button'));
      expect(tester.getTopLeft(button).dx, greaterThan(150));
      await tester.tapAt(const Offset(75, 30));
      await tester.pump();
      expect(taps, 0, reason: 'the cut tail must not take taps');

      // Pushed into view, the same button answers.
      rail.pushTo(250, naturalExtent: 400);
      await tester.pump();
      expect(tester.getTopLeft(button).dx, lessThan(150));
      await tester.tapAt(const Offset(100, 30));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('the vertical rail is the same window turned 90°', (
      tester,
    ) async {
      final rail = LayerRailExtent()..resizeBy(-250, naturalExtent: 400);
      addTearDown(rail.dispose);
      await pumpWindow(tester, axis: Axis.vertical, rail: rail);
      final content = find.byKey(const ValueKey<String>('rail-content'));
      expect(tester.getSize(content).height, 400);
      expect(tester.getSize(find.byType(LayerRailWindow)).height, 150);
      expect(tester.getSize(find.byType(LayerRailWindow)).width, 60);

      final windowTop = tester.getTopLeft(find.byType(LayerRailWindow)).dy;
      rail.pushTo(100, naturalExtent: 400);
      await tester.pump();
      expect(tester.getTopLeft(content).dy, windowTop - 100);
    });
  });

  group('LayerRailSplitter', () {
    testWidgets('dragging resizes, double-clicking restores natural', (
      tester,
    ) async {
      final rail = LayerRailExtent();
      addTearDown(rail.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                height: 200,
                child: LayerRailSplitter(
                  axis: Axis.horizontal,
                  extent: rail,
                  naturalExtent: 434,
                ),
              ),
            ),
          ),
        ),
      );

      // The arithmetic per delta is pinned on [LayerRailExtent] above;
      // what matters here is that the grip is wired to it at all (the
      // recognizer swallows its own slop before the first delta lands).
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(LayerRailSplitter)),
      );
      await gesture.moveBy(const Offset(-40, 0));
      await gesture.moveBy(const Offset(-60, 0));
      await gesture.up();
      await tester.pump();
      expect(rail.windowExtent(434), lessThan(434));
      expect(rail.windowExtent(434), greaterThan(layerRailMinimumWindowExtent));

      await tester.tap(find.byType(LayerRailSplitter));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(LayerRailSplitter));
      await tester.pumpAndSettle();
      expect(rail.value, isNull);
      expect(rail.windowExtent(434), 434);
    });
  });

  group('TimelineSecondsToggleCorner', () {
    testWidgets('the corner cell toggles the frame axis notation', (
      tester,
    ) async {
      var showSeconds = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => TimelineSecondsToggleCorner(
                width: 16,
                height: 28,
                showSeconds: showSeconds,
                onChanged: (value) => setState(() => showSeconds = value),
              ),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(InkWell)).width, 16);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      await tester.tap(find.byType(InkWell));
      await tester.pump();
      expect(showSeconds, isTrue);
      expect(find.byIcon(Icons.timer), findsOneWidget);
    });

    testWidgets('without a setter the corner is a plain spacer', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TimelineSecondsToggleCorner(
              width: 16,
              height: 28,
              showSeconds: false,
              onChanged: null,
            ),
          ),
        ),
      );
      expect(find.byType(InkWell), findsNothing);
    });
  });
}
