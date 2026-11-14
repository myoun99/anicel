import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/ui/widgets/anchored_popup.dart';
import 'package:anicel/src/ui/widgets/icon_button_box.dart' show FaceGround;
import 'package:anicel/src/ui/widgets/pressure_curve_popup.dart';

import '../helpers/text_finders.dart';

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
              target: BrushPressureTarget.size,
              curves: {BrushInputSource.pressure: curve},
              onChanged: (bySource) =>
                  onChanged(bySource[BrushInputSource.pressure]),
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

  final graph = find.byKey(const ValueKey<String>('pressure-curve-graph-pressure'));

  /// [curve]'s button stood on [ground] — the ground its face is told of
  /// ([FaceGround]) and the box under it — as captured: RGBA, row by row.
  Future<({Uint8List bytes, int width, int height})> capture(
    WidgetTester tester,
    BrushPressureCurve? curve,
    Color ground,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey<String>('mini-curve-capture'),
              child: ColoredBox(
                color: ground,
                child: FaceGround(
                  ground: ground,
                  child: PressureCurveButton(
                    keyValue: 'test-pressure-button',
                    target: BrushPressureTarget.size,
                    curves: {BrushInputSource.pressure: curve},
                    onChanged: (_) {},
                  ),
                ),
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
    final shot = (bytes: bytes, width: image.width, height: image.height);
    image.dispose();
    return shot;
  }

  /// How strongly [curve]'s button paints each pixel, 0 to 1, row by row:
  /// its alpha over whatever it stands on, read back from the button stood
  /// on black and on white — over black a pixel is `a·c`, over white
  /// `a·c + (1 − a)·255`, so `a = 1 − (white − black) / 255`.
  ///
  /// ↩️R4 #9 and R6 #2 read the alpha of ONE capture on nothing until
  /// 2026-11-08. A face with an edge paints the ground it stands on inside
  /// that edge since a-live-dock-frame-costs-a-whole-draw-Q12 (유저 답 2), so
  /// that capture went opaque wherever the button is and said nothing about
  /// the mark. 🔬On the app's own brush panel the OFF button's pixels did not
  /// move with that change — the edge 10% white, the X 30%, the inside the
  /// panel's own colour, only the edge's antialiasing apart (9/255 at worst).
  /// Its ground is painted, and painted as the ground, so it reads as none.
  Future<List<List<double>>> inkOf(
    WidgetTester tester,
    BrushPressureCurve? curve,
  ) async {
    final black = await capture(tester, curve, const Color(0xFF000000));
    final white = await capture(tester, curve, const Color(0xFFFFFFFF));
    double alphaAt(int pixel) => [
      for (var c = 0; c < 3; c += 1)
        1 - (white.bytes[pixel * 4 + c] - black.bytes[pixel * 4 + c]) / 255,
    ].reduce((a, b) => a > b ? a : b);
    return [
      for (var y = 0; y < black.height; y += 1)
        [for (var x = 0; x < black.width; x += 1) alphaAt(y * black.width + x)],
    ];
  }


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
      final ink = await inkOf(tester, curve);
      // Two logical pixels in from every edge: the 1px border and its
      // antialiasing, gone. The X's corners sit 7 logical px in (a 3px
      // border+padding inset, then the painter's own 3px), so nothing the
      // test is actually about is cropped with it.
      final inset = (2 * tester.view.devicePixelRatio).round();
      // How much ink each row carries, top row first.
      return [
        for (final row in ink.sublist(inset, ink.length - inset))
          row
              .sublist(inset, row.length - inset)
              .fold(0.0, (sum, pixel) => sum + pixel),
      ];
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
    Future<double> peakAlpha(BrushPressureCurve? curve) async => [
      for (final row in await inkOf(tester, curve)) ...row,
    ].reduce((a, b) => a > b ? a : b);

    expect(
      await peakAlpha(null),
      lessThan(150 / 255),
      reason: 'OFF is a whisper: the X is white at ~30%, the edge at ~10%',
    );
    expect(
      await peakAlpha(BrushPressureCurve.identity()),
      greaterThan(200 / 255),
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
            matching: find.anyText(),
          )
          .first,
    );
    expect(title.data, 'Size — Response');
    expect(title.style, AnchoredPopupText.title);
  });

  testWidgets('the source NAME toggles it on (identity) and off (null)', (
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
      find.byKey(const ValueKey<String>('curve-source-pressure')),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(received, BrushPressureCurve.identity());

    await tester.tap(
      find.byKey(const ValueKey<String>('curve-source-pressure')),
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

  testWidgets('F-450: Escape closes it, as it closes every other window — '
      'R27 #5 took the barrier\'s tap and Escape went with it', (
    tester,
  ) async {
    await pumpButton(
      tester,
      curve: BrushPressureCurve.identity(),
      onChanged: (_) {},
    );
    await openPopup(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('pressure-curve-popup')),
      findsNothing,
      reason: '유저 2026-10-23 (F-450), the window up: 「키보드도 안먹힘」',
    );
  });

  testWidgets('F-456: the graph draws the line joining its points, which '
      'pull the curve from off it — Clip Studio\'s graph', (tester) async {
    await pumpButton(
      tester,
      curve: BrushPressureCurve(const [
        BrushCurvePoint(0.0, 0.0),
        BrushCurvePoint(0.5, 0.8),
        BrushCurvePoint(1.0, 1.0),
      ]),
      onChanged: (_) {},
    );
    await openPopup(tester);

    final painter = find.descendant(
      of: graph,
      matching: find.byType(CustomPaint),
    );
    final size = tester.getSize(painter);
    Offset at(double x, double y) =>
        Offset(x * size.width, (1.0 - y) * size.height);
    // The grid is drawn in lines too: each edge is the first line between
    // its two points, the grid's passed over.
    PaintPatternPredicate edge(Offset from, Offset to) =>
        (method, arguments) =>
            method == #drawLine && arguments[0] == from && arguments[1] == to;
    expect(
      tester.renderObject(painter),
      paints
        ..something(edge(at(0.0, 0.0), at(0.5, 0.8)))
        ..something(edge(at(0.5, 0.8), at(1.0, 1.0))),
    );
  });

  testWidgets('reset restores the identity line', (tester) async {
    BrushPressureCurve? received;
    // ↩️A bent SHAPE, not `linearFrom(0.6)`: since F-176 that is a straight
    // shape over a floor of its own, and the floor survives a reset (the
    // floor and ceiling pins in the_curve_popup_shows_every_source_test).
    await pumpButton(
      tester,
      curve: BrushPressureCurve(const [
        BrushCurvePoint(0.0, 0.0),
        BrushCurvePoint(0.5, 0.8),
        BrushCurvePoint(1.0, 1.0),
      ]),
      onChanged: (value) => received = value,
    );
    await openPopup(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('curve-reset-pressure')),
    );
    await tester.pumpAndSettle();
    expect(received, BrushPressureCurve.identity());
  });
}
