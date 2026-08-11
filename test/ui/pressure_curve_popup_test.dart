import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/ui/widgets/anchored_popup.dart';
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
    //
    // 🚨The BORDER is cropped out before anything is counted, and has to
    // be: R6 #2 made the OFF state's edge fainter than the ON state's, so
    // a frame-inclusive count compares two different frames and reports it
    // as a difference in the MARK. It measured that way for one round and
    // went red the moment the edge colour moved — the test was reading the
    // button, not the drawing inside it.
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
      // Two logical pixels in from every edge: the 1px border and its
      // antialiasing, gone. The X's corners sit 7 logical px in (a 3px
      // border+padding inset, then the painter's own 3px), so nothing the
      // test is actually about is cropped with it.
      final inset = (2 * tester.view.devicePixelRatio).round();
      // How much non-background ink each row carries, top row first.
      final rows = <double>[];
      for (var y = inset; y < height - inset; y += 1) {
        var ink = 0.0;
        for (var x = inset; x < width - inset; x += 1) {
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

  testWidgets('유저 R6 #2: the OFF button paints NOTHING at full strength — '
      'mark and edge are both transparent white', (tester) async {
    // 「필압아이콘 필압설정안하면 x잖아. 지금 진하니까 불투명도 낮은 하얀색
    // x로」 · 「테두리도 그럼 흐리게하자」.
    //
    // The mark used to be AppColors.textDim, which is opaque AND brighter
    // than body text — so "this setting is doing nothing" was the loudest
    // thing on the row. The contract is therefore about ALPHA and not about
    // a particular grey: nothing in the OFF state may reach full opacity.
    // Put any opaque colour back on either the painter or the border and
    // this goes red.
    Future<int> peakAlpha(BrushPressureCurve? curve) async {
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
      image.dispose();
      var peak = 0;
      for (var i = 3; i < bytes.length; i += 4) {
        if (bytes[i] > peak) {
          peak = bytes[i];
        }
      }
      return peak;
    }

    expect(
      await peakAlpha(null),
      lessThan(150),
      reason: 'OFF is a whisper: the X is white at ~30%, the edge at ~10%',
    );
    expect(
      await peakAlpha(BrushPressureCurve.identity()),
      greaterThan(200),
      reason:
          'and ON is not — the accent still lands solidly, so this is a '
          'statement about the OFF state and not about the whole button',
    );
  });

  testWidgets('유저 R6 #4: this window titles itself the same way every other '
      'anchored window does', (tester) async {
    // The other half of 「텍스트사이즈도 다 다르고」: the SHELL was unified
    // (surface, corner, hairline, lift) while the four bodies each picked
    // their own title — this one a bare `fontSize: 11`. Paired with the
    // identical assertion in brush_tip_picker_test, so a caller that
    // re-types a size is caught on whichever side drifts.
    await pumpButton(tester, curve: null, onChanged: (_) {});
    await openPopup(tester);

    final title = tester.widget<Text>(
      find
          .descendant(
            of: find.byType(AnchoredPopupHeader),
            matching: find.byType(Text),
          )
          .first,
    );
    expect(title.data, 'Size — Pen pressure');
    expect(title.style, AnchoredPopupText.title);
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
