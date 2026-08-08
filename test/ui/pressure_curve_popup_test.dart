import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('유저 R4 #9: pressure OFF wears an X, not a flat graph pinned '
      'to the top of the box', (tester) async {
    // 그게 아니라 해당 버튼에 그래프 말고 x 이렇게 둬서 필압 적용 안 되어
    // 있다는 거 알기 쉽게.
    //
    // OFF drew `evaluate(t) ?? 1.0` — a line along the TOP EDGE and nothing
    // anywhere else. Truthful and unreadable at 22×14, and identical to an
    // identity curve someone had dragged flat.
    //
    // The discriminator is therefore INK BELOW THE TOP EDGE: the old
    // drawing put none there at any width, and an X puts some in both
    // bottom corners. Restore the flat line and this goes red.
    Future<List<double>> inkRows(BrushPressureCurve? curve) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: const ValueKey<String>('mini-curve-capture'),
                child: PressureCurveButton(
                  keyValue: 'test-pressure-button',
                  title: 'Size',
                  curve: curve,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey<String>('mini-curve-capture')),
      );
      final image = boundary.toImageSync();
      late Uint8List bytes;
      await tester.runAsync(() async {
        final data = await image.toByteData(format: ImageByteFormat.rawRgba);
        bytes = data!.buffer.asUint8List();
      });
      final width = image.width;
      final height = image.height;
      image.dispose();
      // How much non-background ink each row carries, top row first.
      final rows = <double>[];
      for (var y = 0; y < height; y += 1) {
        var ink = 0.0;
        for (var x = 0; x < width; x += 1) {
          ink += bytes[(y * width + x) * 4 + 3] / 255.0;
        }
        rows.add(ink);
      }
      return rows;
    }

    final off = await inkRows(null);
    // The BOTTOM THIRD of the button. The border is on every row, so the
    // claim is comparative: OFF must carry meaningfully more ink down there
    // than a curve that genuinely sits along the top.
    double bottomThird(List<double> rows) {
      final start = (rows.length * 2 / 3).floor();
      return rows.sublist(start).fold(0.0, (a, b) => a + b);
    }

    final flatTop = await inkRows(
      BrushPressureCurve([
        const BrushCurvePoint(0, 1),
        const BrushCurvePoint(1, 1),
      ]),
    );
    expect(
      bottomThird(off),
      greaterThan(bottomThird(flatTop) * 1.15),
      reason:
          'the X reaches both bottom corners; a top-pinned line never leaves '
          'the top edge',
    );
  });

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
