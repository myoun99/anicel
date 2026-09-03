// THE RAIL'S PAINT-SWIPE: A DRAG THAT STARTS ON A COLUMN LATCHES THE
// OPPOSITE OF THE FIRST ROW'S VALUE AND SETS EVERY ROW IT CROSSES TO IT —
// EACH ROW ONCE, ROWS THAT ALREADY AGREE LEFT ALONE, ROWS WITH NO CONTROL
// SKIPPED, AND A PRESS ON A SPACER STARTS NOTHING.
//
// No test named this widget (audit 2026-09-03) although both rails wear
// it. These pins drive it with four rows of one column.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/timeline/rail_column_swipe.dart';

const double _rowHeight = 40;

class _Rail {
  final values = <int, bool?>{0: false, 1: false, 2: true, 3: null};
  final toggled = <int>[];

  RailToggleColumn<int> get column => (
    bandAt: (_) => (start: 0, end: 60),
    valueOf: (row) => values[row],
    toggle: (row) {
      toggled.add(row);
      values[row] = !values[row]!;
    },
  );

  RailSwipeRow<int>? rowAt(double y) {
    if (y < 0 || y >= _rowHeight * 4) {
      return null;
    }
    final row = y ~/ _rowHeight;
    return (row: row, depth: 0, id: row);
  }
}

void main() {
  Future<_Rail> pump(WidgetTester tester) async {
    final rail = _Rail();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RailColumnSwipe<int>(
              axis: Axis.vertical,
              columns: [rail.column],
              rowAt: rail.rowAt,
              child: const SizedBox(width: 200, height: 240),
            ),
          ),
        ),
      ),
    );
    return rail;
  }

  Future<void> swipe(
    WidgetTester tester, {
    required Offset from,
    required double to,
  }) async {
    final gesture = await tester.startGesture(from);
    var y = from.dy;
    while (y < to) {
      y += 10;
      await gesture.moveTo(Offset(from.dx, y));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
  }

  testWidgets('a swipe down the column paints every disagreeing row once', (
    tester,
  ) async {
    final rail = await pump(tester);
    // Row 0 reads false, so the target is true: rows 0 and 1 flip, row 2
    // already agrees, row 3 has no control.
    await swipe(tester, from: const Offset(30, 20), to: 150);
    expect(rail.toggled, [0, 1]);
    expect(rail.values[0], isTrue);
    expect(rail.values[1], isTrue);
    expect(rail.values[2], isTrue);
    expect(rail.values[3], isNull);
  });

  testWidgets('a press outside the column band or on a spacer paints nothing', (
    tester,
  ) async {
    final rail = await pump(tester);
    await swipe(tester, from: const Offset(120, 20), to: 150);
    await swipe(tester, from: const Offset(30, 200), to: 230);
    expect(rail.toggled, isEmpty);
  });
}
