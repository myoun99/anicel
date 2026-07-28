import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/export/export_cut_grid.dart';

void main() {
  testWidgets('toggle, All-reset and the range field drive the scope',
      (tester) async {
    final excluded = <CutId>{};
    var allTaps = 0;
    (int, int)? range;
    Future<void> pump() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: ExportCutGrid(
              cuts: [
                for (var i = 1; i <= 24; i += 1)
                  (id: CutId('c$i'), number: i),
              ],
              isIncluded: (id) => !excluded.contains(id),
              enabled: true,
              onToggle: (id, included) {
                if (included) {
                  excluded.remove(id);
                } else {
                  excluded.add(id);
                }
              },
              onAllIncluded: () {
                allTaps += 1;
                excluded.clear();
              },
              onRangeSelected: (start, end) => range = (start, end),
            ),
          ),
        ),
      ),
    );

    await pump();
    expect(find.text('24 / 24 cuts'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('export-cut-cell-3')));
    await pump();
    expect(excluded, {const CutId('c3')});
    expect(find.text('23 / 24 cuts'), findsOneWidget);

    // The excluded cell toggles back in.
    await tester.tap(find.byKey(const ValueKey<String>('export-cut-cell-3')));
    await pump();
    expect(excluded, isEmpty);

    // All stays a no-op while nothing is excluded.
    await tester.tap(find.byKey(const ValueKey<String>('export-cut-grid-all')));
    expect(allTaps, 0);
    excluded.add(const CutId('c5'));
    await pump();
    await tester.tap(find.byKey(const ValueKey<String>('export-cut-grid-all')));
    expect(allTaps, 1);
    expect(excluded, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey<String>('export-cut-grid-range')),
      '2-7',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(range, (2, 7));
  });

  testWidgets('a long list stays lazily built under the height cap',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: ExportCutGrid(
              cuts: [
                for (var i = 1; i <= 1500; i += 1)
                  (id: CutId('c$i'), number: i),
              ],
              isIncluded: (_) => true,
              enabled: true,
              onToggle: (_, _) {},
              onAllIncluded: () {},
              onRangeSelected: (_, _) {},
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('export-cut-cell-1')),
      findsOneWidget,
    );
    // Far cells are not built — the grid virtualizes.
    expect(
      find.byKey(const ValueKey<String>('export-cut-cell-1500')),
      findsNothing,
    );
    expect(find.text('1500 / 1500 cuts'), findsOneWidget);
  });
}
