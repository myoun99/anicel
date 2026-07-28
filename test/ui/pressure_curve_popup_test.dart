import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/ui/widgets/pressure_curve_popup.dart';

/// BB-3: the shared pressure-curve editor popup — the CSP editing grammar
/// (drag points, press-to-add, drag-out-to-remove, switch = on/off).
void main() {
  Future<void> pumpButton(
    WidgetTester tester, {
    required BrushPressureCurve? curve,
    required ValueChanged<BrushPressureCurve?> onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressureCurveButton(
              keyValue: 'test-pressure-button',
              title: 'Size',
              curve: curve,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openPopup(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('test-pressure-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('pressure-curve-popup')),
      findsOneWidget,
    );
  }

  final graph = find.byKey(const ValueKey<String>('pressure-curve-graph'));

  testWidgets('the switch turns pressure on (identity) and off (null)', (
    tester,
  ) async {
    BrushPressureCurve? received;
    var calls = 0;
    await pumpButton(
      tester,
      curve: null,
      onChanged: (value) {
        received = value;
        calls += 1;
      },
    );
    await openPopup(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('pressure-curve-enable-switch')),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(received, BrushPressureCurve.identity());

    await tester.tap(
      find.byKey(const ValueKey<String>('pressure-curve-enable-switch')),
    );
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(received, isNull);
  });

  testWidgets('pressing an empty spot adds a control point and drags it', (
    tester,
  ) async {
    BrushPressureCurve? received;
    await pumpButton(
      tester,
      curve: BrushPressureCurve.identity(),
      onChanged: (value) => received = value,
    );
    await openPopup(tester);

    final rect = tester.getRect(graph);
    final center = rect.center;
    final gesture = await tester.startGesture(center);
    await tester.pump();
    // Pull the freshly added midpoint upward = stronger response at 0.5.
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(received, isNotNull);
    expect(received!.points, hasLength(3));
    final middle = received!.points[1];
    expect(middle.x, closeTo(0.5, 0.05));
    expect(middle.y, greaterThan(0.6));
    // The curve still ends at the pinned endpoints.
    expect(received!.points.first.x, 0.0);
    expect(received!.points.last.x, 1.0);
  });

  testWidgets('dragging a middle point far outside removes it', (
    tester,
  ) async {
    final threePoint = BrushPressureCurve(const [
      BrushCurvePoint(0.0, 0.0),
      BrushCurvePoint(0.5, 0.8),
      BrushCurvePoint(1.0, 1.0),
    ]);
    BrushPressureCurve? received;
    await pumpButton(
      tester,
      curve: threePoint,
      onChanged: (value) => received = value,
    );
    await openPopup(tester);

    final rect = tester.getRect(graph);
    // The middle point sits at (0.5, 0.8) = (center.dx, 20% height).
    final middlePosition = Offset(
      rect.left + rect.width * 0.5,
      rect.top + rect.height * 0.2,
    );
    final gesture = await tester.startGesture(middlePosition);
    await tester.pump();
    await gesture.moveBy(Offset(0, rect.height + 120));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(received, isNotNull);
    expect(received!.points, hasLength(2));
  });

  testWidgets('endpoints keep their x while their y drags freely', (
    tester,
  ) async {
    BrushPressureCurve? received;
    await pumpButton(
      tester,
      curve: BrushPressureCurve.identity(),
      onChanged: (value) => received = value,
    );
    await openPopup(tester);

    final rect = tester.getRect(graph);
    // The left endpoint of the identity curve sits at the bottom-left
    // (nudged inside: Rect.contains excludes the bottom/left edge line).
    final gesture = await tester.startGesture(
      rect.bottomLeft + const Offset(2, -2),
    );
    await tester.pump();
    await gesture.moveBy(Offset(40, -rect.height * 0.5));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(received, isNotNull);
    expect(received!.points, hasLength(2));
    expect(received!.points.first.x, 0.0);
    expect(received!.points.first.y, greaterThan(0.3));
  });

  testWidgets('R27 #5: a DRAG started outside dismisses the popup', (
    tester,
  ) async {
    await pumpButton(
      tester,
      curve: BrushPressureCurve.identity(),
      onChanged: (_) {},
    );
    await openPopup(tester);

    // Not a tap — press, move, release well away from the popup. The
    // stock modal barrier only closes on a completed tap, so this used to
    // leave the editor hanging over the UI.
    final gesture = await tester.startGesture(const Offset(12, 12));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('pressure-curve-popup')),
      findsNothing,
    );
  });

  testWidgets('reset restores the identity line', (tester) async {
    BrushPressureCurve? received;
    await pumpButton(
      tester,
      curve: BrushPressureCurve.linearFrom(0.6),
      onChanged: (value) => received = value,
    );
    await openPopup(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('pressure-curve-reset')),
    );
    await tester.pumpAndSettle();
    expect(received, BrushPressureCurve.identity());
  });
}
