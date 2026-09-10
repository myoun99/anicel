import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_preset_reorder_grid.dart';

/// 🚨유저 확정 (`brush-grid-reorder-Q1`, 답 1): 「2열에서도 드래그 재정렬을
/// 지킨다」. The option this beat would have made the order changeable only
/// after switching the VIEW — two modes for one job.
void main() {
  group('the columns follow the width', () {
    test('the panel\'s own default width holds TWO', () {
      // 유저 확정: 「260px 폭에서 2열」, and `EditorPanelDock.width` is 260.
      expect(brushPresetColumnsFor(260), 2);
    });

    test('a wider panel holds three, then four — and stops', () {
      expect(brushPresetColumnsFor(390), 3);
      expect(brushPresetColumnsFor(520), 4);
      expect(
        brushPresetColumnsFor(2000),
        brushPresetMaxColumns,
        reason: 'a fifth column would thin the strokes, not help',
      );
    });

    test('a panel too narrow for one cell still draws one', () {
      expect(brushPresetColumnsFor(40), 1);
      expect(brushPresetColumnsFor(0), 1);
      expect(brushPresetColumnsFor(double.nan), 1);
    });
  });

  group('⛔a resize is not a reorder', () {
    Widget gridAt(double width) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: 400,
          child: BrushPresetReorderGrid(
            itemCount: 6,
            cellHeight: brushPresetRowHeight,
            itemKey: (index) => ValueKey<String>('cell-$index'),
            itemBuilder: (context, index) => ColoredBox(
              color: Colors.blue,
              child: Center(child: Text('$index')),
            ),
          ),
        ),
      ),
    );

    testWidgets('the columns change AT ONCE, with nothing sliding', (
      tester,
    ) async {
      // 유저 H33: 「열이 바껴서 3개나 4개로 늘어날때 필요없는 쓸데없는
      // 애니메이션 있거든? 그냥 그런거 싹 빼고 심플하게 열이 두개 세개로
      // 그냥 늘어나게만」.
      //
      // ⚠️ONE pump, deliberately — `pumpAndSettle` would run the animation
      // to its end and report the right answer either way, which is exactly
      // how this would have gone unnoticed. What the user sees is the FIRST
      // frame after the splitter moves.
      await tester.pumpWidget(gridAt(260));
      expect(brushPresetColumnsFor(260), 2, reason: 'fixture premise');
      expect(
        tester.getTopLeft(find.byKey(const ValueKey<String>('cell-2'))).dy,
        brushPresetRowHeight,
        reason: 'fixture premise: at two columns cell 2 opens the SECOND row',
      );

      await tester.pumpWidget(gridAt(390));
      await tester.pump();

      expect(brushPresetColumnsFor(390), 3, reason: 'fixture premise');
      expect(
        tester.getTopLeft(find.byKey(const ValueKey<String>('cell-2'))).dy,
        0,
        reason: 'at three columns cell 2 closes the FIRST row, and it is '
            'ALREADY there on the frame the width changed — a cell still '
            'sliding would read the row it came from',
      );
    });

    testWidgets('and the cells follow a splitter that never changes the '
        'column COUNT', (tester) async {
      // ⚠️Not a second case of the same thing: a splitter drag spends most of
      // its frames INSIDE one column count, and the cell width changes on
      // every one of them. Watching only the count would leave exactly the
      // swimming 유저 named, just between the steps instead of at them.
      await tester.pumpWidget(gridAt(260));
      expect(brushPresetColumnsFor(300), 2, reason: 'fixture premise: still 2');
      expect(
        tester.getTopLeft(find.byKey(const ValueKey<String>('cell-1'))).dx,
        130,
        reason: 'fixture premise: half of 260',
      );

      await tester.pumpWidget(gridAt(300));
      await tester.pump();

      expect(
        tester.getTopLeft(find.byKey(const ValueKey<String>('cell-1'))).dx,
        150,
        reason: 'column 1 starts at half of 300 the moment the panel is 300',
      );
    });

    testWidgets('a REORDER still slides — the animation was not deleted', (
      tester,
    ) async {
      // The other half: 유저 named the resize, not the drag. A pin that only
      // said "nothing animates" would pass with the slide ripped out of every
      // path, and the reorder is what it was written for.
      //
      // ⚠️This drives the real drag rather than reading
      // `brushPresetReorderDuration`: a constant nothing consults is not
      // evidence, and forcing the duration to zero everywhere would leave
      // that constant untouched.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              height: 400,
              child: BrushPresetReorderGrid(
                itemCount: 6,
                cellHeight: brushPresetRowHeight,
                itemKey: (index) => ValueKey<String>('cell-$index'),
                onReorder: (_, _) {},
                itemBuilder: (context, index) => ColoredBox(
                  color: Colors.blue,
                  child: Center(child: Text('$index')),
                ),
              ),
            ),
          ),
        ),
      );

      final displaced = find.byKey(const ValueKey<String>('cell-1'));
      final home = tester.getTopLeft(displaced).dx;
      expect(home, greaterThan(0), reason: 'cell 1 starts in column 1');

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey<String>('cell-0'))),
      );
      await gesture.moveBy(const Offset(0, 8));
      await tester.pump();
      // Cell 0 aims at slot 1, so cell 1 is pushed back to column 0.
      await gesture.moveBy(const Offset(130, 0));
      await tester.pump();
      await tester.pump(brushPresetReorderDuration ~/ 2);

      final midway = tester.getTopLeft(displaced).dx;
      expect(midway, lessThan(home), reason: 'it has set off');
      expect(midway, greaterThan(0), reason: 'and has not arrived — it slides');

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('the grid reorders', () {
    Future<List<(int, int)>> pumpAndDrag(
      WidgetTester tester, {
      required double width,
      required int from,
      required Offset by,
    }) async {
      final moves = <(int, int)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              height: 400,
              child: BrushPresetReorderGrid(
                itemCount: 6,
                cellHeight: brushPresetRowHeight,
                itemKey: (index) => ValueKey<String>('cell-$index'),
                onReorder: (oldIndex, newIndex) =>
                    moves.add((oldIndex, newIndex)),
                itemBuilder: (context, index) => ColoredBox(
                  color: Colors.blue,
                  child: Center(child: Text('$index')),
                ),
              ),
            ),
          ),
        ),
      );

      final start = tester.getCenter(
        find.byKey(ValueKey<String>('cell-$from')),
      );
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, 8));
      await tester.pump();
      await gesture.moveBy(by);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      return moves;
    }

    testWidgets('🚨a cell dragged ACROSS lands in the next column — the thing '
        'a one-dimensional list cannot do', (tester) async {
      // Two columns: cell 0 and cell 1 sit side by side, so a purely
      // HORIZONTAL drag has to move the order. `ReorderableListView` reads
      // only the cross axis and would report nothing at all.
      final moves = await pumpAndDrag(
        tester,
        width: 260,
        from: 0,
        by: const Offset(130, 0),
      );

      expect(moves, isNotEmpty, reason: 'the sideways drag reordered');
      expect(moves.single.$1, 0);
      expect(moves.single.$2, 1);
    });

    testWidgets('a cell dragged DOWN a row lands two slots on in two columns',
        (tester) async {
      final moves = await pumpAndDrag(
        tester,
        width: 260,
        from: 0,
        by: const Offset(0, brushPresetRowHeight),
      );

      expect(moves.single, (0, 2));
    });

    testWidgets('🚨the drop reads the cell\'s MIDDLE, so crossing half a cell '
        'is enough', (tester) async {
      // 70 of a 130-wide cell. Read from the carried cell's top-left corner
      // this is still column 0 and nothing moves; read from its middle it is
      // past the boundary, which is where the eye says it is.
      final moves = await pumpAndDrag(
        tester,
        width: 260,
        from: 0,
        by: const Offset(70, 0),
      );

      expect(moves.single, (0, 1));
    });

    testWidgets('a drag that goes nowhere reports nothing', (tester) async {
      final moves = await pumpAndDrag(
        tester,
        width: 260,
        from: 2,
        by: Offset.zero,
      );

      expect(moves, isEmpty);
    });

    testWidgets('⛔with no reorder callback the cells do not drag at all',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              height: 400,
              child: BrushPresetReorderGrid(
                itemCount: 4,
                cellHeight: brushPresetRowHeight,
                itemKey: (index) => ValueKey<String>('cell-$index'),
                itemBuilder: (context, index) => Text('$index'),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Draggable<int>), findsNothing);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('the rail is told when a drag starts and ends', (tester) async {
      var starts = 0;
      var ends = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              height: 400,
              child: BrushPresetReorderGrid(
                itemCount: 4,
                cellHeight: brushPresetRowHeight,
                itemKey: (index) => ValueKey<String>('cell-$index'),
                onReorder: (_, _) {},
                onDragStart: () => starts += 1,
                onDragEnd: () => ends += 1,
                itemBuilder: (context, index) =>
                    ColoredBox(color: Colors.blue, child: Text('$index')),
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey<String>('cell-0'))),
      );
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
      expect(starts, 1, reason: 'the spring-loaded tabs need to know');
      expect(ends, 0);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(ends, 1, reason: 'and they need to be let go of');
    });
  });
}
