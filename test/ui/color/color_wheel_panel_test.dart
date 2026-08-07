import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/color/color_wheel_panel.dart';

void main() {
  group('ColorWheelGeometry', () {
    final geometry = ColorWheelGeometry(const Size(200, 200), hue: 0);

    test('triangle and ring regions resolve by position', () {
      expect(geometry.outerRadius, 100);
      // The centroid is always inside the triangle.
      expect(
        geometry.regionAt(const Offset(100, 100)),
        ColorWheelRegion.svTriangle,
      );
      expect(
        geometry.regionAt(const Offset(191, 100)),
        ColorWheelRegion.hueRing,
      );
      expect(geometry.regionAt(const Offset(2, 2)), ColorWheelRegion.none);
    });

    test('hue runs clockwise from 3 o\'clock', () {
      expect(geometry.hueAt(const Offset(191, 100)), 0);
      expect(geometry.hueAt(const Offset(100, 191)), 90);
      expect(geometry.hueAt(const Offset(9, 100)), 180);
      expect(geometry.hueAt(const Offset(100, 9)), 270);
    });

    test('the hue corner rides the ring: white above, black below at 0°', () {
      // hue 0 → full-saturation corner at 3 o'clock on the triangle radius.
      expect(
        geometry.hueCorner.dx,
        closeTo(100 + geometry.triangleRadius, 1e-9),
      );
      expect(geometry.hueCorner.dy, closeTo(100, 1e-9));
      // White up-left, black down-left (screen y grows downward).
      expect(geometry.whiteCorner.dx, lessThan(100));
      expect(geometry.whiteCorner.dy, lessThan(100));
      expect(geometry.blackCorner.dx, lessThan(100));
      expect(geometry.blackCorner.dy, greaterThan(100));

      // The triangle rotates with the hue.
      final rotated = ColorWheelGeometry(const Size(200, 200), hue: 90);
      expect(rotated.hueCorner.dx, closeTo(100, 1e-9));
      expect(rotated.hueCorner.dy, closeTo(100 + rotated.triangleRadius, 1e-9));
    });

    test('svAt inverts svPosition across the triangle', () {
      // Corners map to their canonical extremes.
      final (sHue, vHue) = geometry.svAt(geometry.hueCorner);
      expect(sHue, closeTo(1, 1e-9));
      expect(vHue, closeTo(1, 1e-9));
      final (sWhite, vWhite) = geometry.svAt(geometry.whiteCorner);
      expect(sWhite, closeTo(0, 1e-9));
      expect(vWhite, closeTo(1, 1e-9));
      final (_, vBlack) = geometry.svAt(geometry.blackCorner);
      expect(vBlack, closeTo(0, 1e-9));

      // An interior point round-trips.
      final (s, v) = geometry.svAt(geometry.svPosition(0.4, 0.7));
      expect(s, closeTo(0.4, 1e-9));
      expect(v, closeTo(0.7, 1e-9));
    });

    test('positions outside the triangle clamp to its boundary', () {
      final center = geometry.center;
      // Way past the black corner: clamps to the corner, v = 0.
      final pastBlack =
          geometry.blackCorner + (geometry.blackCorner - center) * 2;
      final (_, v) = geometry.svAt(pastBlack);
      expect(v, closeTo(0, 1e-9));
      // Way past the hue corner: clamps to full saturation and value.
      final pastHue = geometry.hueCorner + (geometry.hueCorner - center) * 2;
      final (sMax, vMax) = geometry.svAt(pastHue);
      expect(sMax, closeTo(1, 1e-9));
      expect(vMax, closeTo(1, 1e-9));
    });
  });

  group('ColorWheelPanel', () {
    Future<Rect> pumpPanel(
      WidgetTester tester, {
      required int color,
      required List<int> changes,
      int backgroundColor = 0xFFFFFFFF,
      List<int>? backgroundChanges,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 220,
                height: 300,
                child: ColorWheelPanel(
                  color: color,
                  onColorChanged: changes.add,
                ),
              ),
            ),
          ),
        ),
      );
      return tester.getRect(find.byKey(const ValueKey<String>('color-wheel')));
    }

    testWidgets('R10 R5: the panel is the WHEEL — a square that takes the '
        'shorter side, whatever the aspect', (tester) async {
      for (final size in const [Size(420, 180), Size(180, 420)]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: ColorWheelPanel(
                    color: 0xFFFF0000,
                    onColorChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);

        // The swatch pair and the swap left for the tool RAIL, the hex for
        // the window's status bar — so there is no strip to lay out around
        // and no aspect that shrinks the wheel behind one.
        final wheelRect = tester.getRect(
          find.byKey(const ValueKey<String>('color-wheel')),
        );
        final shorter = size.shortestSide - 24; // the 12px padding
        expect(wheelRect.height, closeTo(shorter, 1), reason: 'at $size');
        expect(wheelRect.width, closeTo(shorter, 1), reason: 'at $size');
        expect(
          find.byKey(const ValueKey<String>('color-wheel-hex-label')),
          findsNothing,
        );
      }
    });

    testWidgets('tiny and narrow panels never overflow', (tester) async {
      for (final size in const [Size(80, 60), Size(60, 220), Size(220, 46)]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: ColorWheelPanel(
                    color: 0xFF00FF00,
                    onColorChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: 'no overflow at $size');
      }
    });

    testWidgets('tapping the ring spins the hue (red → green stays pure)', (
      tester,
    ) async {
      final changes = <int>[];
      final wheelRect = await pumpPanel(
        tester,
        color: 0xFFFF0000,
        changes: changes,
      );

      final geometry = ColorWheelGeometry(wheelRect.size, hue: 0);
      // 120° on the ring's center radius = pure green for s=1, v=1.
      final ringRadius = geometry.innerRadius + geometry.ringWidth / 2;
      final local =
          geometry.center +
          Offset.fromDirection(120 * 3.14159265 / 180, ringRadius);
      await tester.tapAt(wheelRect.topLeft + local);
      await tester.pump();

      expect(changes, isNotEmpty);
      expect(changes.last, 0xFF00FF00);
    });

    testWidgets('dragging in the triangle picks saturation/value (past the '
        'black corner = black)', (tester) async {
      final changes = <int>[];
      final wheelRect = await pumpPanel(
        tester,
        color: 0xFFFF0000,
        changes: changes,
      );

      final geometry = ColorWheelGeometry(wheelRect.size, hue: 0);
      // Start inside the triangle (locks the region), then drag PAST the
      // black corner — the mapping clamps to the boundary, v = 0.
      final gesture = await tester.startGesture(
        wheelRect.topLeft + geometry.center,
      );
      final pastBlack =
          geometry.blackCorner + (geometry.blackCorner - geometry.center);
      await gesture.moveTo(wheelRect.topLeft + pastBlack);
      await gesture.up();
      await tester.pump();

      expect(changes, isNotEmpty);
      expect(changes.last, 0xFF000000);
      // The hex readout moved to the window's status bar (R10 R5).
    });

    testWidgets('a drag locked to the ring never enters the triangle', (
      tester,
    ) async {
      final changes = <int>[];
      final wheelRect = await pumpPanel(
        tester,
        color: 0xFFFF0000,
        changes: changes,
      );

      final geometry = ColorWheelGeometry(wheelRect.size, hue: 0);
      final ringRadius = geometry.innerRadius + geometry.ringWidth / 2;
      // Down on the ring at 0°, then drag across the triangle's middle:
      // the gesture keeps steering the hue, never saturation/value.
      final gesture = await tester.startGesture(
        wheelRect.topLeft + geometry.center + Offset(ringRadius, 0),
      );
      await gesture.moveTo(wheelRect.topLeft + geometry.center);
      await gesture.up();
      await tester.pump();

      expect(changes, isNotEmpty);
      for (final color in changes) {
        // Hue-only edits of pure red keep s=1, v=1: a fully saturated,
        // full-value color (never a desaturated triangle pick).
        final hsv = HSVColor.fromColor(Color(color));
        expect(hsv.saturation, closeTo(1, 1e-6));
        expect(hsv.value, closeTo(1, 1e-6));
      }
    });

  });
}
