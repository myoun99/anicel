import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/export/export_cut_grid.dart';

void main() {
  ExportCutEntry entry(int number, {List<String>? ids, String? label}) => (
    ids: [for (final id in ids ?? ['c$number']) CutId(id)],
    label: label ?? '$number',
    number: number,
  );

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
              cuts: [for (var i = 1; i <= 24; i += 1) entry(i)],
              isIncluded: (id) => !excluded.contains(id),
              enabled: true,
              onToggle: (ids, included) {
                if (included) {
                  excluded.removeAll(ids);
                } else {
                  excluded.addAll(ids);
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

  testWidgets('a 겸용 group is ONE cell: it prints the joined name and its '
      'cuts flip together', (tester) async {
    // 유저 2026-09-09: 「컷 리스트에도 한 칸 … 겸용컷 비포함이란게 불가능하도록」.
    final excluded = <CutId>{};
    Future<void> pump() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: ExportCutGrid(
              cuts: [
                entry(1),
                entry(2, ids: ['c2', 'c3'], label: '2-3'),
                entry(4),
              ],
              isIncluded: (id) => !excluded.contains(id),
              enabled: true,
              onToggle: (ids, included) =>
                  included ? excluded.removeAll(ids) : excluded.addAll(ids),
              onAllIncluded: excluded.clear,
              onRangeSelected: (_, _) {},
            ),
          ),
        ),
      ),
    );

    await pump();
    expect(find.text('2-3'), findsOneWidget);
    expect(find.text('3 / 3 cuts'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('export-cut-cell-2')));
    await pump();
    expect(excluded, {const CutId('c2'), const CutId('c3')});
    expect(find.text('2 / 3 cuts'), findsOneWidget);
  });

  testWidgets('a long list stays lazily built under the height cap',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: ExportCutGrid(
              cuts: [for (var i = 1; i <= 1500; i += 1) entry(i)],
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
