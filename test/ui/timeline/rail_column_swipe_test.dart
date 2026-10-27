// THE RAIL'S PAINT-SWIPE: A DRAG THAT STARTS ON A COLUMN'S BUTTON SPREADS
// WHAT ITS PRESS WROTE — THE OPPOSITE OF THE FIRST ROW'S VALUE — TO EVERY
// ROW IT CROSSES: EACH ROW ONCE WHILE THE STRETCH HOLDS IT AND BACK WHEN THE
// CURSOR DRAWS BACK FROM IT (F-182), ROWS THAT ALREADY AGREE LEFT ALONE,
// ROWS WITH NO CONTROL SKIPPED, AND A PRESS NO BUTTON TOOK STARTS NOTHING.
//
// No test named this widget (audit 2026-09-03) although both rails wear
// it. These pins drive it with four rows of one column, each control a
// button that acts on the down, as a rail row's does.
//
// 🚨★★★AND THE ROWS IT CROSSES ARE THE ONES IN THE SEGMENT, NOT THE ONES
// A POINTER HAPPENED TO REPORT (F-66, 유저 2026-09-10: 「렉걸리는 상태에서
// 아래로 끌면 **중간에 조작이 안 걸리는 레이어가 생긴다**」). A pointer move
// is not a promise to visit every row on the way, so the pins below drive
// one that JUMPS — the shape a dropped frame actually has.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show RailSwipeColumnPointer;
import 'package:anicel/src/ui/timeline/rail_column_swipe.dart';

const double _rowHeight = 40;

class _Rail {
  _Rail(this.values, {this.buttons = true});

  _Rail.four()
    : values = {0: false, 1: false, 2: true, 3: null},
      buttons = true;

  final Map<int, bool?> values;
  final toggled = <int>[];

  /// Whether a row with a control wears its BUTTON in the column's band, as
  /// a rail's rows do — or the band is bare.
  final bool buttons;

  /// How many rows the resolver was asked about, and how often — the
  /// per-move cost, so 「the sweep does work per BUTTON」 can be measured
  /// rather than assumed.
  int rowsInCalls = 0;
  int bandCalls = 0;

  RailToggleColumn<int> get column => (
    bandAt: (_) {
      bandCalls += 1;
      return (start: 0, end: 60);
    },
    valueOf: (row) => values[row],
    toggle: (row) {
      toggled.add(row);
      values[row] = !values[row]!;
    },
  );

  /// Every row whose 40px band meets the stretch, ends included.
  ///
  /// ⛔Written out BY HAND rather than calling `railRowsAlong`, which is
  /// what both timeline grids hand the widget. This is the oracle: a
  /// fake host that shares the product's arithmetic agrees with it while
  /// they are both wrong.
  List<RailSwipeRow<int>> rowsIn(double from, double to) {
    rowsInCalls += 1;
    var first = ((from <= to ? from : to) / _rowHeight).floor();
    var last = ((from <= to ? to : from) / _rowHeight).floor();
    if (first < 0) {
      first = 0;
    }
    if (last > values.length - 1) {
      last = values.length - 1;
    }
    return [
      for (var row = first; row <= last; row += 1) (row: row, id: row),
    ];
  }
}

/// A column's button as a rail row wears it: the STRONG claim
/// ([RailSwipeColumnPointer]), and its press fired on the down — a rail
/// row's button acts at tap-down.
Widget _button(VoidCallback press) => RailSwipeColumnPointer(
  child: Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (_) => press(),
  ),
);

void main() {
  Future<_Rail> pump(WidgetTester tester, [_Rail? rail]) async {
    final subject = rail ?? _Rail.four();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RailColumnSwipe<int>(
              axis: Axis.vertical,
              columns: [subject.column],
              rowsIn: subject.rowsIn,
              // Two rows' worth of SPACER past the last row, so a press
              // below the rows still lands on the widget.
              child: SizedBox(
                width: 200,
                height: _rowHeight * (subject.values.length + 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final MapEntry(key: row, value: on)
                        in subject.values.entries)
                      SizedBox(
                        width: 60,
                        height: _rowHeight,
                        child: on == null
                            ? null
                            : subject.buttons
                            ? _button(() => subject.column.toggle(row))
                            // The row's own plate, which no button claims.
                            : const ColoredBox(color: Colors.transparent),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return subject;
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

  // 🚨F-475: what was pressed decides. A press in the band that no button
  // took is the rail's — it scrolls, or drags the row — and starts no sweep.
  // ↩️It did: the band itself started one, a pen's 4px past each slot
  // included, so a press beside a button swept that button's column.
  testWidgets('a press in the band its button did not take sweeps nothing', (
    tester,
  ) async {
    // The rows below DISAGREE with the pressed one, so a sweep begun here
    // would show whatever it latched.
    final rail = await pump(
      tester,
      _Rail({0: false, 1: true, 2: true}, buttons: false),
    );
    await swipe(tester, from: const Offset(30, 20), to: 110);
    expect(rail.toggled, isEmpty);
  });

  // The strong claim says a value control took the press; the band says
  // which column it is. A claimed press in no band — a button its column
  // does not lay where it stands — is no column's to sweep.
  testWidgets('a claimed press outside every band sweeps nothing', (
    tester,
  ) async {
    final rail = _Rail({0: false, 1: true, 2: true});
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RailColumnSwipe<int>(
              axis: Axis.vertical,
              columns: [rail.column],
              rowsIn: rail.rowsIn,
              child: SizedBox(
                width: 200,
                height: _rowHeight * 3,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 100),
                    child: SizedBox(
                      width: 40,
                      height: _rowHeight,
                      child: _button(() => pressed += 1),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await swipe(tester, from: const Offset(120, 20), to: 110);
    expect(pressed, 1, reason: '⛔전제: the control took the press');
    expect(rail.toggled, isEmpty);
    expect(tester.takeException(), isNull);
  });

  // 🚨★★★F-66. The whole point is the row the pointer never reported.
  testWidgets('a pointer that JUMPS still paints every row it flew over', (
    tester,
  ) async {
    final rail = await pump(
      tester,
      _Rail({for (var row = 0; row < 8; row += 1) row: false}),
    );
    final gesture = await tester.startGesture(const Offset(30, 20));
    await tester.pump();
    // One 10px step so the drag is under way on row 0...
    await gesture.moveTo(const Offset(30, 30));
    await tester.pump();
    // ...then A DROPPED FRAME: row 0 to row 6 in ONE event, and nothing
    // between them is ever reported.
    await gesture.moveTo(const Offset(30, 260));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(
      rail.toggled,
      [0, 1, 2, 3, 4, 5, 6],
      reason: 'rows 1..5 were never under the cursor at an event',
    );
    for (var row = 0; row <= 6; row += 1) {
      expect(rail.values[row], isTrue, reason: 'row $row');
    }
    expect(rail.values[7], isFalse, reason: 'past where the pointer stopped');
  });

  // ⛔THE FIRST MOVE IS ALREADY A SEGMENT. The recogniser reports its start
  // at the PRESS ([DragStartBehavior.down]) and the move that won the arena
  // arrives as the first update — so if that one move is the dropped frame,
  // the stretch from the press to it is the only place those rows are ever
  // named.
  testWidgets('a jump on the very FIRST move sweeps from the press', (
    tester,
  ) async {
    final rail = await pump(
      tester,
      _Rail({for (var row = 0; row < 8; row += 1) row: false}),
    );
    final gesture = await tester.startGesture(const Offset(30, 20));
    await tester.pump();
    await gesture.moveTo(const Offset(30, 260));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(rail.toggled, [0, 1, 2, 3, 4, 5, 6]);
  });

  testWidgets('a jump UP paints the rows above it too', (tester) async {
    final rail = await pump(
      tester,
      _Rail({for (var row = 0; row < 8; row += 1) row: false}),
    );
    final gesture = await tester.startGesture(const Offset(30, 300));
    await tester.pump();
    await gesture.moveTo(const Offset(30, 290));
    await tester.pump();
    await gesture.moveTo(const Offset(30, 20));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    for (var row = 0; row <= 7; row += 1) {
      expect(rail.values[row], isTrue, reason: 'row $row');
    }
  });

  // 🚨F-182 (유저 2026-09-25): 「레이어 라벨 버튼 드래그 일괄조작, 원래 위치로
  // 돌아가면 원복하도록」. ↩️This pin said the opposite until that day — 「a
  // drag that wanders back over one must not undo it」. A row is painted
  // once while the stretch holds it; drawing back takes it back (here, with
  // no history above the rail, by pressing it again) and reaching it again
  // paints it again.
  testWidgets('a pointer that goes back and forth takes back what it leaves',
      (tester) async {
    final rail = await pump(
      tester,
      _Rail({for (var row = 0; row < 8; row += 1) row: false}),
    );
    final gesture = await tester.startGesture(const Offset(30, 20));
    await tester.pump();
    for (final y in [30.0, 140.0, 30.0, 140.0, 20.0]) {
      await gesture.moveTo(Offset(30, y));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(rail.toggled, [0, 1, 2, 3, 3, 2, 1, 1, 2, 3, 3, 2, 1]);
    expect(rail.values[0], isTrue, reason: 'the row the press began on');
    expect(
      [rail.values[1], rail.values[2], rail.values[3]],
      [false, false, false],
      reason: 'back where the press began, the rest are as they were',
    );
  });

  // 🚨②, MEASURED. 유저 suspected the sweep does work per BUTTON on every
  // pointer move. It does not and it did not: the column bands are read
  // ONCE, at the press, and an update asks the host exactly one question
  // whatever the columns or rows number.
  testWidgets('one pointer move asks the rail once and reads no band', (
    tester,
  ) async {
    final rail = await pump(
      tester,
      _Rail({for (var row = 0; row < 8; row += 1) row: false}),
    );
    final gesture = await tester.startGesture(const Offset(30, 20));
    await tester.pump();
    await gesture.moveTo(const Offset(30, 30));
    await tester.pump();

    rail.rowsInCalls = 0;
    rail.bandCalls = 0;
    await gesture.moveTo(const Offset(30, 260));
    await tester.pump();
    expect(rail.rowsInCalls, 1, reason: 'one segment, one question');
    expect(rail.bandCalls, 0, reason: 'bands are a press-time answer');

    await gesture.up();
    await tester.pump();
  });
}
