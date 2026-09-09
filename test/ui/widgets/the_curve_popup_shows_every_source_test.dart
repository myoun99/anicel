// THE SOURCE AXIS — the three things this round exists to make true.
//
// The .sut importer already builds tilt and speed curves off real Clip Studio
// brushes, and until this round nothing in the app could show one, let alone
// edit it: `BrushShape.withCurve` had zero production callers. So the pins are
// (1) all three sources are reachable, (2) editing one does not disturb the
// others, and (3) an imported ceiling survives being touched.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/ui/widgets/pressure_curve_popup.dart';

void main() {
  Map<BrushInputSource, BrushPressureCurve?>? committed;

  Future<void> open(
    WidgetTester tester,
    Map<BrushInputSource, BrushPressureCurve?> initial,
  ) async {
    committed = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                key: const ValueKey<String>('open-curve'),
                onPressed: () => showPressureCurvePopup(
                  context,
                  title: 'Size',
                  initialCurves: initial,
                  onChanged: (bySource) => committed = bySource,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('open-curve')));
    await tester.pumpAndSettle();
  }

  testWidgets('🚨every source has its own row, always — none behind a tab', (
    tester,
  ) async {
    // ⛔A segmented selector was the obvious design and it is the wrong one:
    // it would hide an imported tilt curve behind a click, which is the gap
    // this round exists to close.
    await open(tester, const {});

    for (final source in BrushInputSource.values) {
      expect(
        find.byKey(ValueKey<String>('pressure-curve-graph-${source.name}')),
        findsOneWidget,
        reason: source.name,
      );
      expect(
        find.byKey(ValueKey<String>('curve-source-${source.name}')),
        findsOneWidget,
        reason: source.name,
      );
    }
    // ⛔And no master switch above them: one control answering three
    // questions is the thing the rows replaced.
    expect(
      find.byKey(const ValueKey<String>('pressure-curve-enable-switch')),
      findsNothing,
    );
  });

  testWidgets('🚨turning one source off does not resurrect another', (
    tester,
  ) async {
    // THE LOST UPDATE THIS ROUND WAS BUILT TO AVOID. `onChanged` closes over
    // the tool state as it was when the BUTTON was built, so a popup that
    // committed one source at a time would read that stale base once per
    // source: clearing tilt and then touching pressure would put tilt back.
    // Committing the whole target every time is what makes this pass.
    await open(tester, {
      BrushInputSource.pressure: BrushPressureCurve.identity(),
      BrushInputSource.tilt: BrushPressureCurve.linearFrom(0.4),
    });

    await tester.tap(find.byKey(const ValueKey<String>('curve-source-tilt')));
    await tester.pumpAndSettle();

    expect(committed, isNotNull);
    expect(committed![BrushInputSource.tilt], isNull);
    // ...and pressure came along in the same write, unchanged.
    expect(committed![BrushInputSource.pressure], BrushPressureCurve.identity());

    // Now touch PRESSURE. A stale base would hand tilt back here.
    await tester.tap(
      find.byKey(const ValueKey<String>('curve-reset-pressure')),
    );
    await tester.pumpAndSettle();
    expect(
      committed![BrushInputSource.tilt],
      isNull,
      reason: 'the second write read a stale base and undid the first',
    );
  });

  testWidgets('speed is reachable, and starts from nothing', (tester) async {
    await open(tester, const {});

    await tester.tap(find.byKey(const ValueKey<String>('curve-source-speed')));
    await tester.pumpAndSettle();

    expect(committed![BrushInputSource.speed], BrushPressureCurve.identity());
    // The other two stay absent — ON is per row.
    expect(committed![BrushInputSource.pressure], isNull);
    expect(committed![BrushInputSource.tilt], isNull);
  });

  testWidgets('🚨an imported ceiling survives a reset and a toggle', (
    tester,
  ) async {
    // `maximum` is Clip Studio's 最大値 and the graph physically cannot draw
    // it: the points live in the unit square and `evaluate` multiplies by the
    // ceiling afterwards. The editor used to rebuild the curve as
    // `BrushPressureCurve(points)` and drop it to 1.0 on every commit — a
    // dormant bug while only pressure was editable, because the importer only
    // ever puts a ceiling on TILT.
    await open(tester, {
      BrushInputSource.tilt: BrushPressureCurve(
        const [BrushCurvePoint(0.0, 0.25), BrushCurvePoint(1.0, 1.0)],
        maximum: 4.0,
      ),
    });

    await tester.tap(find.byKey(const ValueKey<String>('curve-reset-tilt')));
    await tester.pumpAndSettle();

    expect(committed![BrushInputSource.tilt]!.maximum, 4.0);
    expect(
      committed![BrushInputSource.tilt]!.points,
      BrushPressureCurve.identity().points,
      reason: 'reset restores the SHAPE, and only the shape',
    );

    // And it is on screen, at ×4, drawn whether or not it is the default.
    expect(find.text('×4'), findsOneWidget);
    expect(find.text('×1'), findsNWidgets(2));
  });

  testWidgets('a point dragged to the right EDGE is not deleted', (
    tester,
  ) async {
    // 🚨The hit box and the painted box used to be two numbers: `_graphSize`
    // was the old popup width minus its padding, typed in by hand, while the
    // painter took whatever the column gave it. Widening the popup with that
    // arrangement would put the remove-slack boundary INSIDE the drawn strip,
    // so a middle point dragged to the right edge would vanish.
    await open(tester, {
      BrushInputSource.pressure: BrushPressureCurve(const [
        BrushCurvePoint(0.0, 0.0),
        BrushCurvePoint(0.5, 0.5),
        BrushCurvePoint(1.0, 1.0),
      ]),
    });

    final strip = find.byKey(
      const ValueKey<String>('pressure-curve-graph-pressure'),
    );
    final box = tester.getRect(strip);
    // Grab the middle point and drag it to just inside the right edge.
    final from = Offset(box.left + box.width * 0.5, box.top + box.height * 0.5);
    final gesture = await tester.startGesture(from);
    await gesture.moveTo(Offset(box.right - 2, box.center.dy));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      committed![BrushInputSource.pressure]!.points,
      hasLength(3),
      reason: 'the middle point was inside the strip and must survive',
    );
  });
}
