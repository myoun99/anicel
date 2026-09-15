import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/media_asset.dart' show mediaFileNameParts;
import 'package:anicel/src/ui/import/import_file_table.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

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
  ImportFileRow row(String file) {
    final parts = mediaFileNameParts('/in/$file');
    return ImportFileRow(
      path: '/in/$file',
      name: parts.name,
      extension: parts.extension,
      modified: '09-05',
      size: '1 MB',
    );
  }

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
        id: 'mode',
        label: 'Mode',
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
    List<ImportFileRow>? rows,
    List<ImportColumn<Object?>> extra = const [],
    double? width = 500,
  }) async {
    final q = question(onlyOneAnswer: onlyOneAnswer);
    final taps = <String>[];
    final shownRows = rows ?? [row('a.png'), row('b.png'), row('c.wav')];
    final columns = [q.column, ...extra];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Builder(
              builder: (context) => SizedBox(
                // null = the narrowest the table may be laid out.
                width:
                    width ??
                    ImportFileTable.minimumWidth(
                      context,
                      rows: shownRows,
                      columns: columns,
                    ),
                height: 300,
                child: ImportFileTable(
                  rows: shownRows,
                  columns: columns,
                  selected: selected,
                  enabled: enabled,
                  onRowTap: taps.add,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (picks: q.picks, taps: taps);
  }

  Finder cell(String id, String file) =>
      find.byKey(ValueKey<String>('import-cell-$id-/in/$file'));

  testWidgets('every file gets a row, and each row shows its OWN answer', (
    tester,
  ) async {
    await pumpTable(tester);

    expect(find.text('.png'), findsNWidgets(2));
    expect(find.text('.wav'), findsOneWidget);
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
    await tester.tap(
      find.byKey(const ValueKey<String>('import-option-mode-reference')),
    );
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

    await tester.tap(cell('mode', 'b.png'));
    await tester.pumpAndSettle();

    final carry = find.byKey(const ValueKey<String>('import-option-mode-carry'));
    expect(carry, findsOneWidget, reason: 'offered, not hidden');

    final before = table.picks.length;
    await tester.tap(carry);
    await tester.pumpAndSettle();

    expect(table.picks.length, before, reason: 'and inert');
  });

  testWidgets('🚨a cell with only ONE possible answer does not open at all '
      '— a menu of one is a menu that wastes a press', (tester) async {
    final table = await pumpTable(tester, onlyOneAnswer: true);

    await tester.tap(cell('mode', 'b.png'), warnIfMissed: false);
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

    await tester.tap(find.byKey(const ValueKey<String>('import-name-/in/a.png')));
    await tester.pumpAndSettle();

    expect(table.taps, ['/in/a.png']);
  });

  testWidgets('⛔a DISABLED table takes no press at all — a running import '
      'must not be re-answered under itself', (tester) async {
    final table = await pumpTable(tester, enabled: false);

    await tester.tap(
      find.byKey(const ValueKey<String>('import-name-/in/a.png')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(table.taps, isEmpty);
  });

  group('the table is laid out once, for the header and the rows alike '
      '(유저 2026-09-11: 「열끼리 길이 어긋났거든? 크기랑 실제 크기 쪽이랑 '
      '규격이 달라. 이름은 표시도안되고」)', () {
    testWidgets('🚨the header sits OVER its cells — the size header ends '
        'where the sizes end, and a question\'s header is centred over its '
        'chips', (tester) async {
      await pumpTable(tester);

      final sizeHeader = tester.getRect(find.text(AppText.strings.imSize));
      final sizeValue = tester.getRect(find.text('1 MB').first);
      expect(
        sizeHeader.right,
        moreOrLessEquals(sizeValue.right, epsilon: 0.5),
        reason: 'the header and the rows are laid out in one box, beside '
            'the same scrollbar lane',
      );

      final modeHeader = tester.getCenter(find.text('Mode'));
      final modeCell = tester.getCenter(cell('mode', 'a.png'));
      expect(modeHeader.dx, moreOrLessEquals(modeCell.dx, epsilon: 0.5));

      final modifiedHeader = tester.getRect(find.text(AppText.strings.imModified));
      final modifiedValue = tester.getRect(find.text('09-05').first);
      expect(
        modifiedHeader.left,
        moreOrLessEquals(modifiedValue.left, epsilon: 0.5),
      );
    });

    testWidgets('🚨the name is READ — at the narrowest the table may be, a '
        'long name still has its readable room, and its extension is never '
        'the part cut away', (tester) async {
      const long = 'background_street_night_rain_version_final.png';
      await pumpTable(tester, rows: [row(long)], width: null);

      final name = tester.getSize(
        find.byKey(const ValueKey<String>('import-name-/in/$long')),
      );
      final extension = tester.getSize(find.text('.png'));
      // The room is stated here, not read back from the table: a floor the
      // test takes from the code it guards moves with that code.
      const readableRoom = 120.0;
      expect(
        name.width + extension.width,
        greaterThanOrEqualTo(readableRoom - 0.5),
        reason: 'the fixed columns used to leave the name 20px',
      );
      expect(find.text('.png'), findsOneWidget);
    });

    testWidgets('🚨a chip is never cut — the row is as tall as what it '
        'holds', (tester) async {
      await pumpTable(tester);

      final chip = tester.getRect(cell('mode', 'a.png'));
      final word = tester.getRect(
        find.descendant(of: cell('mode', 'a.png'), matching: find.text('carry')),
      );
      final line = tester.getRect(
        find.byKey(const ValueKey<String>('import-row-a.png')),
      );
      expect(word.top, greaterThanOrEqualTo(chip.top));
      expect(word.bottom, lessThanOrEqualTo(chip.bottom));
      expect(chip.top, greaterThanOrEqualTo(line.top));
      expect(chip.bottom, lessThanOrEqualTo(line.bottom));
      // Boxes nest even when squeezed — a word pressed into 6px still sits
      // inside its chip. A cut is a box shorter than what it holds needs.
      for (final box in [
        find.descendant(of: cell('mode', 'a.png'), matching: find.text('carry')),
        cell('mode', 'a.png'),
      ]) {
        final render = tester.renderObject<RenderBox>(box);
        expect(
          render.size.height,
          greaterThanOrEqualTo(
            render.getMinIntrinsicHeight(render.size.width) - 0.5,
          ),
        );
      }
    });

    testWidgets('the narrowest width grows with the questions asked, and '
        'the preferred one is wider still', (tester) async {
      late double one;
      late double two;
      late double preferred;
      final rows = [row('a.png')];
      final q = question();
      final second = question().column;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              one = ImportFileTable.minimumWidth(
                context,
                rows: rows,
                columns: [q.column],
              );
              two = ImportFileTable.minimumWidth(
                context,
                rows: rows,
                columns: [q.column, second],
              );
              preferred = ImportFileTable.preferredWidth(
                context,
                rows: rows,
                columns: [q.column],
              );
              return const SizedBox();
            },
          ),
        ),
      );
      expect(two, greaterThan(one));
      expect(
        preferred - one,
        moreOrLessEquals(
          ImportFileTable.namePreferredWidth - ImportFileTable.nameMinWidth,
        ),
      );
    });
  });

  group('an on/off question is a switch', () {
    ({ImportColumn<Object?> column, List<Object?> picks}) toggle({
      bool locked = false,
    }) {
      final picks = <Object?>[];
      return (
        column: ImportColumn<Object?>(
          id: 'bake',
          label: 'Bake',
          style: ImportColumnStyle.toggle,
          values: const [false, true],
          labelOf: (value) => value == true ? 'On' : 'Off',
          valueOf: (path) => path.endsWith('b.png'),
          appliesTo: (path) => !path.endsWith('c.wav'),
          enabledFor: (path, value) => !locked || value == true,
          onPick: (paths, value) => picks.add(value),
        ),
        picks: picks,
      );
    }

    testWidgets('pressing the switch answers the OTHER value for that row', (
      tester,
    ) async {
      final t = toggle();
      await pumpTable(tester, extra: [t.column]);

      expect(find.byType(Switch), findsNWidgets(2), reason: 'c.wav is a dash');
      await tester.tap(cell('bake', 'a.png'));
      await tester.pumpAndSettle();
      await tester.tap(cell('bake', 'b.png'));
      await tester.pumpAndSettle();

      expect(t.picks, [true, false]);
    });

    testWidgets('a switch the context decided shows its answer and takes no '
        'press', (tester) async {
      final t = toggle(locked: true);
      await pumpTable(tester, extra: [t.column]);

      await tester.tap(cell('bake', 'b.png'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(t.picks, isEmpty);
      expect(
        tester.widget<Switch>(
          find.descendant(of: cell('bake', 'b.png'), matching: find.byType(Switch)),
        ).onChanged,
        isNull,
        reason: 'shown disabled, not hidden',
      );
    });
  });

  testWidgets('⛔the keys are the column\'s id, not its label — a label '
      'changes with the language', (tester) async {
    await pumpTable(tester);

    expect(cell('mode', 'a.png'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('import-column-mode')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('import-cell-Mode-/in/a.png')),
      findsNothing,
    );
  });
}
