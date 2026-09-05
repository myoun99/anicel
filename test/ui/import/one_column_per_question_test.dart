import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/import/import_file_table.dart';

/// The import window's file list: one row per file, one COLUMN per
/// question. Nothing named it (2026-09-05).
///
/// 🚨The window used to hold ONE answer for the whole batch, which meant
/// the answer was wrong for at least one file most of the time. Here the
/// cell shows what THIS file will do, and pressing it offers only the
/// answers this file can give — an impossible one is SHOWN and dim, so the
/// row says what is impossible instead of hiding that it was ever asked.
///
/// And a column's header is a button too: it applies one answer to every
/// row, because setting twenty files one at a time is not a feature.
void main() {
  ImportFileRow row(String name) => ImportFileRow(
    path: '/in/$name',
    name: name,
    modified: '2026-09-05',
    size: '1 MB',
  );

  /// One question with three answers, where 'b.png' cannot say "carry" and
  /// the question is meaningless for 'c.wav'.
  ({
    ImportColumn<Object?> column,
    List<({List<String> paths, Object? value})> picks,
  })
  question({bool onlyOneAnswer = false}) {
    final picks = <({List<String> paths, Object? value})>[];
    return (
      column: ImportColumn<Object?>(
        label: 'Mode',
        width: 90,
        values: const ['carry', 'reference', 'skip'],
        labelOf: (value) => value! as String,
        valueOf: (path) => path.endsWith('b.png') ? 'reference' : 'carry',
        appliesTo: (path) => !path.endsWith('c.wav'),
        enabledFor: (path, value) => onlyOneAnswer
            ? (!path.endsWith('b.png') || value == 'reference')
            : !(path.endsWith('b.png') && value == 'carry'),
        onPick: (paths, value) =>
            picks.add((paths: paths.toList(), value: value)),
      ),
      picks: picks,
    );
  }

  Future<
    ({List<({List<String> paths, Object? value})> picks, List<String> taps})
  >
  pumpTable(
    WidgetTester tester, {
    Set<String> selected = const {},
    bool enabled = true,
    bool onlyOneAnswer = false,
  }) async {
    final q = question(onlyOneAnswer: onlyOneAnswer);
    final taps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 300,
            child: ImportFileTable(
              rows: [row('a.png'), row('b.png'), row('c.wav')],
              columns: [q.column],
              selected: selected,
              enabled: enabled,
              onRowTap: taps.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (picks: q.picks, taps: taps);
  }

  testWidgets('every file gets a row, and each row shows its OWN answer', (
    tester,
  ) async {
    await pumpTable(tester);

    expect(find.text('a.png'), findsOneWidget);
    expect(find.text('b.png'), findsOneWidget);
    expect(find.text('c.wav'), findsOneWidget);
    expect(find.text('carry'), findsOneWidget, reason: 'a.png only');
    expect(find.text('reference'), findsOneWidget, reason: 'b.png only');
  });

  testWidgets('⛔a file the question is MEANINGLESS for shows a dash — not '
      'a value nobody chose', (tester) async {
    await pumpTable(tester);

    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('🚨the column HEADER applies one answer to every row — '
      'setting twenty files one at a time is not a feature', (tester) async {
    final table = await pumpTable(tester);

    await tester.tap(find.text('Mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('reference').last);
    await tester.pumpAndSettle();

    expect(table.picks, hasLength(1));
    expect(table.picks.single.value, 'reference');
    expect(
      table.picks.single.paths.length,
      greaterThan(1),
      reason: 'the header speaks for the batch',
    );
  });

  testWidgets('🚨an impossible answer is SHOWN and dim rather than hidden — '
      'the row says what it cannot do instead of hiding that it was ever '
      'asked', (tester) async {
    final table = await pumpTable(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('import-cell-Mode-/in/b.png')),
    );
    await tester.pumpAndSettle();

    expect(find.text('carry'), findsWidgets, reason: 'offered, not hidden');

    final before = table.picks.length;
    await tester.tap(find.text('carry').last);
    await tester.pumpAndSettle();

    expect(table.picks.length, before, reason: 'and inert');
  });

  testWidgets('🚨a cell with only ONE possible answer does not open at all '
      '— a menu of one is a menu that wastes a press', (tester) async {
    final table = await pumpTable(tester, onlyOneAnswer: true);

    await tester.tap(
      find.byKey(const ValueKey<String>('import-cell-Mode-/in/b.png')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(table.picks, isEmpty);
    expect(
      find.text('skip'),
      findsNothing,
      reason: 'no popup opened — "skip" lives only inside one',
    );
  });

  testWidgets('a row press reports which file it was', (tester) async {
    final table = await pumpTable(tester);

    await tester.tap(find.text('a.png'));
    await tester.pumpAndSettle();

    expect(table.taps, ['/in/a.png']);
  });

  testWidgets('⛔a DISABLED table takes no press at all — a running import '
      'must not be re-answered under itself', (tester) async {
    final table = await pumpTable(tester, enabled: false);

    await tester.tap(find.text('a.png'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(table.taps, isEmpty);
  });
}
