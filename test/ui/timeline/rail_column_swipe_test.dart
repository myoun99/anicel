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
//
// 🚨★★★AND THE COLUMN IS THE ONE THE PRESSED BUTTON NAMES (F-475), not one
// worked out from where the press stood: the pins below lay two columns'
// buttons in the other order from the rail's list.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/input/control_press_claim.dart'
    show DragVerbClaim;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show RailSwipeColumn, RailSwipeColumnPointer;
import 'package:anicel/src/ui/timeline/rail_column_swipe.dart';

const double _rowHeight = 40;

class _Rail {
  _Rail(
    this.values, {
    this.buttons = true,
    this.kind = RailSwipeColumn.visibility,
  });

  _Rail.four()
    : values = {0: false, 1: false, 2: true, 3: null},
      buttons = true,
      kind = RailSwipeColumn.visibility;

  final Map<int, bool?> values;
  final toggled = <int>[];

  /// Whether a row with a control wears its BUTTON in the column's slot, as
  /// a rail's rows do — or the slot is bare.
  final bool buttons;

  /// The column this is — the one its buttons name.
  final RailSwipeColumn kind;

  /// How many rows the resolver was asked about, and how often — the
  /// per-move cost, so 「the sweep does work per BUTTON」 can be measured
  /// rather than assumed.
  int rowsInCalls = 0;

  RailToggleColumn<int> get column => (
    column: kind,
    valueOf: (row) => values[row],
    toggle: (row) {
      toggled.add(row);
      values[row] = !values[row]!;
    },
  );

  /// This column's button on [row], as a rail row wears it.
  Widget buttonOn(int row) => _button(() => column.toggle(row), column: kind);

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

/// A column's button as a rail row wears it: the STRONG claim, which names
/// the column it stands in ([RailSwipeColumnPointer]), and its press fired
/// on the down — a rail row's button acts at tap-down.
Widget _button(VoidCallback press, {required RailSwipeColumn column}) =>
    RailSwipeColumnPointer(
      column: column,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => press(),
      ),
    );

/// A rail of [rows], each an 80 × [_rowHeight] slot down the side of a
/// wider strip, with two rows' worth of SPACER past the last so a press
/// below the rows still lands on the widget. With a [scroller] the strip
/// stands in a list, which scrolls under a drag nobody else holds.
Future<void> _pumpRail(
  WidgetTester tester, {
  required List<RailToggleColumn<int>> columns,
  required List<RailSwipeRow<int>> Function(double from, double to) rowsIn,
  required List<Widget> rows,
  ScrollController? scroller,
}) {
  final rail = RailColumnSwipe<int>(
    axis: Axis.vertical,
    columns: columns,
    rowsIn: rowsIn,
    child: SizedBox(
      width: 200,
      height: _rowHeight * (rows.length + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            SizedBox(width: 80, height: _rowHeight, child: row),
        ],
      ),
    ),
  );
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: scroller == null
            ? Align(alignment: Alignment.topLeft, child: rail)
            : SingleChildScrollView(
                controller: scroller,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [rail, const SizedBox(height: 2000)],
                ),
              ),
      ),
    ),
  );
}

void main() {
  Future<_Rail> pump(WidgetTester tester, [_Rail? rail]) async {
    final subject = rail ?? _Rail.four();
    await _pumpRail(
      tester,
      columns: [subject.column],
      rowsIn: subject.rowsIn,
      rows: [
        for (final MapEntry(key: row, value: on) in subject.values.entries)
          if (on == null)
            const SizedBox.shrink()
          else if (subject.buttons)
            subject.buttonOn(row)
          else
            // The row's own plate, which no button claims.
            const ColoredBox(color: Colors.transparent),
      ],
    );
    return subject;
  }

  /// A drag from [from] to [to] along the rail, 10px a move, either way —
  /// by [pointer] when one is named.
  Future<void> swipe(
    WidgetTester tester, {
    required Offset from,
    required double to,
    int? pointer,
  }) async {
    final gesture = await tester.startGesture(from, pointer: pointer);
    final step = to >= from.dy ? 10.0 : -10.0;
    var y = from.dy;
    while ((to - y) * step > 0) {
      y += step;
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

  testWidgets('a press beside the column\'s button or on a spacer paints '
      'nothing', (tester) async {
    final rail = await pump(tester);
    await swipe(tester, from: const Offset(120, 20), to: 150);
    await swipe(tester, from: const Offset(30, 200), to: 230);
    expect(rail.toggled, isEmpty);
  });

  // 🚨F-475: what was pressed decides. A press on a row's plate that no
  // button took is the rail's — it scrolls, or drags the row — and starts
  // no sweep. ↩️It did: the column's band started one, a pen's 4px past
  // each slot included, so a press beside a button swept that button's
  // column.
  testWidgets('a press on a slot no button took sweeps nothing', (
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

  // 🚨★★★WHICH ONE, NOT WHERE (F-475). Two columns on one rail, their
  // buttons standing in the OTHER order from the list's: a press is swept
  // in the column its button names, and in that column alone.
  testWidgets('a press sweeps the column its button names', (tester) async {
    final eye = _Rail({0: false, 1: false, 2: false});
    final onion = _Rail({
      0: false,
      1: false,
      2: false,
    }, kind: RailSwipeColumn.onion);
    await _pumpRail(
      tester,
      columns: [eye.column, onion.column],
      rowsIn: eye.rowsIn,
      rows: [
        for (final row in [0, 1, 2])
          Row(
            children: [
              SizedBox(width: 40, child: onion.buttonOn(row)),
              SizedBox(width: 40, child: eye.buttonOn(row)),
            ],
          ),
      ],
    );

    await swipe(tester, from: const Offset(20, 20), to: 110);
    expect(onion.toggled, [0, 1, 2]);
    expect(eye.toggled, isEmpty);

    await swipe(tester, from: const Offset(60, 20), to: 110);
    expect(eye.toggled, [0, 1, 2]);
    expect(onion.toggled, [0, 1, 2], reason: 'the onions left as they were');
  });

  // The strong claim says a drag from here is a verb — a slider's is; WHICH
  // column it sweeps is the button's to say, and a claim that names none
  // is no column's. ⛔Nor is it the column an EARLIER press named — even by
  // the same pointer id, as a test's come round again: the answer is this
  // press's own, or a press would sweep from a button it never touched.
  testWidgets(
    'a strong claim that names no column sweeps nothing, even right after '
    'a column\'s button was pressed',
    (tester) async {
      // The rows below DISAGREE with the pressed one, so a sweep begun
      // there would show whatever it latched.
      final rail = _Rail({0: false, 1: false, 2: true, 3: true});
      var pressed = 0;
      await _pumpRail(
        tester,
        columns: [rail.column],
        rowsIn: rail.rowsIn,
        rows: [
          rail.buttonOn(0),
          DragVerbClaim(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => pressed += 1,
            ),
          ),
          rail.buttonOn(2),
          rail.buttonOn(3),
        ],
      );
      await tester.tapAt(const Offset(30, 20), pointer: 7);
      await tester.pump();
      expect(rail.toggled, [0], reason: '⛔전제: the eye took the tap');

      await swipe(tester, from: const Offset(30, 60), to: 150, pointer: 7);
      expect(pressed, 1, reason: '⛔전제: the claim took the press');
      expect(rail.toggled, [0]);
      expect(tester.takeException(), isNull);
    },
  );

  // A column this rail does not list holds its press all the same: the
  // button stood its own claim down for the strong one, so nothing else
  // would hold it, and a drag from a button is the button's (F-475,
  // 「버튼에서 시작한 조작은 스크롤을 발동시키지않음」).
  testWidgets(
    'a press on a column this rail does not sweep holds its drag and sweeps '
    'nothing',
    (tester) async {
      // Rows that DISAGREE with the pressed one, so a sweep begun there in
      // the eye's column would show.
      final rail = _Rail({0: true, 1: true, 2: false});
      final onion = _Rail({2: false}, kind: RailSwipeColumn.onion);
      final scroller = ScrollController();
      addTearDown(scroller.dispose);
      await _pumpRail(
        tester,
        columns: [rail.column],
        rowsIn: rail.rowsIn,
        scroller: scroller,
        rows: [rail.buttonOn(0), rail.buttonOn(1), onion.buttonOn(2)],
      );
      // UP the list, the way it would scroll.
      await swipe(tester, from: const Offset(30, 100), to: 10);
      expect(onion.toggled, [2], reason: '⛔전제: the onion took the press');
      expect(rail.toggled, isEmpty);
      expect(scroller.offset, 0, reason: 'the list stayed where it was');
    },
  );

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
  // pointer move. It does not and it did not: the column is the pressed
  // button's answer, given ONCE at the press, and an update asks the host
  // exactly one question whatever the columns or rows number.
  testWidgets('one pointer move asks the rail once', (tester) async {
    final rail = await pump(
      tester,
      _Rail({for (var row = 0; row < 8; row += 1) row: false}),
    );
    final gesture = await tester.startGesture(const Offset(30, 20));
    await tester.pump();
    await gesture.moveTo(const Offset(30, 30));
    await tester.pump();

    rail.rowsInCalls = 0;
    await gesture.moveTo(const Offset(30, 260));
    await tester.pump();
    expect(rail.rowsInCalls, 1, reason: 'one segment, one question');

    await gesture.up();
    await tester.pump();
  });
}
