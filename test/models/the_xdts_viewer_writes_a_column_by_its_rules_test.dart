import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/inbetween_mark.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/xdts_viewer_notation.dart';

/// A track spelled a frame a letter: a digit is that number, `.` holds on,
/// `x` is the null cell, `o` a mark.
List<Object?> _track(String spelled) => [
  for (final letter in spelled.split(''))
    switch (letter) {
      '.' => null,
      'x' => xdtsViewerNullCell,
      'o' => InbetweenMark.one,
      _ => letter,
    },
];

/// The inks spelled a row a letter: `v` the value, `b` the value in blue,
/// `|` a line, `~` a wave, `:` a repeat's dashes, `_` nothing.
String _inks(XdtsViewerNotation notation) => notation.inks
    .map(
      (ink) => switch (ink) {
        XdtsViewerInk.value => 'v',
        XdtsViewerInk.repeatValue => 'b',
        XdtsViewerInk.line => '|',
        XdtsViewerInk.wave => '~',
        XdtsViewerInk.repeat => ':',
        XdtsViewerInk.none => '_',
      },
    )
    .join();

XdtsViewerNotation _cells(String spelled, {int pageFrames = 144}) =>
    xdtsViewerNotation(
      _track(spelled),
      keyBlock: false,
      pageFrames: pageFrames,
    );

XdtsViewerNotation _key(String spelled) =>
    xdtsViewerNotation(_track(spelled), keyBlock: true, pageFrames: 144);

/// A round of [round] repeated over [frames] frames, then [after].
String _repeated(String round, int frames, String after) =>
    List.generate(frames, (frame) => round[frame % round.length]).join() +
    after;

void main() {
  group('a value\'s line (I-162-Q1)', () {
    test('lasts down from the first held frame where three hold on, and '
        'nowhere a shorter run holds', () {
      expect(_inks(_cells('1...2..3')), 'v|||v__v');
    });

    test('needs its three held frames inside the track', () {
      expect(_inks(_cells('1..')), 'v__');
      expect(_inks(_cells('1...')), 'v|||');
    });

    test('reaches nine rows down the key block, its value\'s included, and '
        'all the way down the cells block', () {
      final frames = '1${'.' * 12}2';
      expect(_inks(_key(frames)), 'v${'|' * 8}${'_' * 4}v');
      expect(_inks(_cells(frames)), 'v${'|' * 12}v');
    });

    test('from a null cell is a wave, and from a mark a line', () {
      expect(_inks(_cells('x...1')), 'v~~~v');
      expect(_inks(_cells('o...1')), 'v|||v');
    });

    test('a page that opens on a held frame takes its line from the value '
        'it holds, however short the run', () {
      expect(_inks(_cells('123..4', pageFrames: 4)), 'vvv_|v');
    });
  });

  group('the key block\'s repeats', () {
    test('a round written twice over and 24 frames past its first: its next '
        'round\'s first value in blue, nine rows of dashes from there, the '
        'rest nothing, to the value that breaks it — リピート under the '
        'blue value', () {
      final key = _key(_repeated('12', 30, '3'));
      expect(_inks(key), 'vvb${':' * 8}${'_' * 19}v');
      expect(key.words, [(frame: 3, repeat: true)]);
      expect(
        _inks(_cells(_repeated('12', 30, '3'))),
        'v' * 31,
        reason: 'the cells block writes every value',
      );
    });

    test('24 frames past its first round is the least', () {
      expect(xdtsViewerRepeats(_track(_repeated('12', 26, '3'))), [
        (start: 0, round: 2, end: 26),
      ]);
      expect(xdtsViewerRepeats(_track(_repeated('12', 25, '3'))), isEmpty);
    });

    test('a round with held frames repeats to the last written frame before '
        'the one that breaks it', () {
      final key = _key(_repeated('1.2.', 32, '3'));
      expect(xdtsViewerRepeats(_track(_repeated('1.2.', 32, '3'))), [
        (start: 0, round: 4, end: 32),
      ]);
      expect(_inks(key), 'v_v_b${':' * 8}${'_' * 19}v');
      expect(key.words, [(frame: 5, repeat: true)]);
    });

    test('one value held through the whole column is 止メ from its second '
        'frame: its line one row, then nothing', () {
      final key = _key('1${'.' * 30}');
      expect(xdtsViewerRepeats(_track('1${'.' * 30}')), [
        (start: 0, round: 1, end: 31),
      ]);
      expect(_inks(key), 'v|${'_' * 29}');
      expect(key.words, [(frame: 1, repeat: false)]);
    });

    test('a column of nothing is not 止メ (「×止メ」という書き方はしない)', () {
      final key = _key('x${'.' * 12}');
      expect(xdtsViewerRepeats(_track('x${'.' * 12}')), isEmpty);
      expect(_inks(key), 'v${'~' * 8}${'_' * 4}');
      expect(key.words, isEmpty);
    });

    test('a mark or a held frame that breaks the round is not written: the '
        'repeat ends on the last number before it', () {
      final marked = _repeated('12', 30, 'o3');
      expect(xdtsViewerRepeats(_track(marked)), [
        (start: 0, round: 2, end: 29),
      ]);
      expect(_inks(_key(marked)), 'vvb${':' * 8}${'_' * 18}vvv');
      final held = _repeated('12', 30, '.3');
      expect(xdtsViewerRepeats(_track(held)), [
        (start: 0, round: 2, end: 29),
      ]);
      expect(_inks(_key(held)), 'vvb${':' * 8}${'_' * 18}v_v');
    });

    test('a round whose first number comes twice in it is not one: the '
        'repeat starts a frame later, where the first comes once', () {
      expect(xdtsViewerRepeats(_track(_repeated('1213', 40, '4'))), [
        (start: 1, round: 4, end: 40),
      ]);
    });

    test('a round whose first number came already since the last repeat '
        'is not one either', () {
      expect(xdtsViewerRepeats(_track('13${_repeated('12', 30, '4')}')), [
        (start: 3, round: 2, end: 32),
      ]);
    });

    test('a round comes round twice at least: 24 frames past a round of 25 '
        'are not enough', () {
      final round = [for (var number = 1; number <= 25; number += 1) number];
      List<Object?> track(int past) => [
        for (final number in round) '$number',
        for (final number in round.take(past)) '$number',
        '99',
      ];
      expect(xdtsViewerRepeats(track(24)), isEmpty);
      expect(xdtsViewerRepeats(track(25)), [(start: 0, round: 25, end: 50)]);
    });
  });

  test('an empty track writes nothing', () {
    expect(_inks(_key('')), '');
    expect(_key('').words, isEmpty);
  });

  group('the values a sheet column hands the viewer', () {
    const held = TimesheetCell(TimesheetCellKind.held);

    test('a drawing its number or its mark where it starts, a breakdown its '
        'mark, a held row nothing', () {
      expect(
        xdtsViewerFramesOf(const [
          TimesheetCell(TimesheetCellKind.drawing, label: '1'),
          held,
          TimesheetCell(TimesheetCellKind.mark, mark: InbetweenMark.two),
          held,
          TimesheetCell(
            TimesheetCellKind.drawing,
            label: '',
            mark: InbetweenMark.one,
          ),
        ], duration: 5),
        ['1', null, InbetweenMark.two, null, InbetweenMark.one],
      );
    });

    test('a run of nothing its null cell where it starts, however the sheet '
        'spells the run — past the conte end too, up to the drawn end', () {
      const cells = [
        TimesheetCell.blank,
        TimesheetCell(TimesheetCellKind.drawing, label: '1'),
        TimesheetCell(TimesheetCellKind.emptyRunStart),
        TimesheetCell(TimesheetCellKind.emptyRunSpan),
        TimesheetCell(TimesheetCellKind.drawing, label: '2'),
        // Past the conte end our sheet writes no ×.
        TimesheetCell.blank,
        TimesheetCell.blank,
      ];
      const nullCell = xdtsViewerNullCell;
      expect(xdtsViewerFramesOf(cells, duration: 7), [
        nullCell,
        '1',
        nullCell,
        null,
        '2',
        nullCell,
        null,
      ]);
      expect(xdtsViewerFramesOf(cells, duration: 3), [nullCell, '1', nullCell]);
      expect(
        xdtsViewerFramesOf(cells.sublist(0, 2), duration: 4),
        [nullCell, '1', nullCell, null],
        reason: 'a frame past the cells holds nothing',
      );
    });
  });
}
