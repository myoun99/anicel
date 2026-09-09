import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/ui/widgets/pressure_curve_popup.dart';

/// The curve editor's point insertion, the one law behind a press on the
/// graph and a removed point's return (the audit's clone scan, 2026-09-03).
/// A "no point inserted" mutant survived every test that mentions the
/// curve: none opened the popup and pressed the graph, so this does.
void main() {
  Future<BrushPressureCurve?> Function() openAndPress(WidgetTester tester) {
    BrushPressureCurve? committed;
    return () async {
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
                    initialCurves: {
                      BrushInputSource.pressure: BrushPressureCurve.identity(),
                    },
                    onChanged: (bySource) =>
                        committed = bySource[BrushInputSource.pressure],
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
      final graph = find.byKey(const ValueKey<String>('pressure-curve-graph-pressure'));
      expect(graph, findsOneWidget, reason: '⛔the popup did not open');

      // A press in the middle of the graph is far from both endpoints, so
      // it adds a point there and starts dragging it.
      final gesture = await tester.startGesture(tester.getCenter(graph));
      await gesture.moveBy(const Offset(0, -12));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      return committed;
    };
  }

  testWidgets('a press on the graph between the endpoints ADDS a point', (
    tester,
  ) async {
    final committed = await openAndPress(tester)();
    expect(committed, isNotNull, reason: 'the editor commits on every edit');
    expect(
      committed!.points.length,
      3,
      reason: 'the identity curve has two endpoints; the press adds one',
    );
    expect(committed.points[1].x, closeTo(0.5, 0.1));
  });
}
