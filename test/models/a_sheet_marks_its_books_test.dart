// D24 후반 — THE SHEET MARKS ITS BOOKS (유저 2026-09-25, 사진 셋; F-578
// 11-10 「이미지레이어고 타임시트on이면 북으로 인식」): an image row the
// ACTION block counts — LO, ラフ原, 原画 or no label —, whatever its name
// and its revise, is a book; it sits at the boundary of the cel columns
// under it, tagged with its row's name and its picture's; several at one
// boundary share a tag (`a,b`); none under the first cel column, the one
// over the last marked. ↩️An image row labelled 美術 was the book (09-26).
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/sheet_sources.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_info.dart';

Layer cels(String name, {bool onTimesheet = true}) => Layer(
  id: LayerId(name),
  name: name,
  frames: const [],
  onTimesheet: onTimesheet,
);

var _pictures = 0;

/// An image row holding one picture named [frame] — attached to the row
/// [attachedTo] names when it is given.
Layer picture(
  String name, {
  String? frame,
  LayerMark mark = const LayerMark(process: LayerProcess.layout),
  bool onTimesheet = true,
  String? attachedTo,
}) {
  _pictures += 1;
  return Layer(
    id: LayerId('picture-$_pictures'),
    name: name,
    kind: LayerKind.image,
    mark: mark,
    onTimesheet: onTimesheet,
    attachedToLayerId: attachedTo == null ? null : LayerId(attachedTo),
    frames: [
      Frame(
        id: FrameId('picture-$_pictures-f'),
        duration: 1,
        strokes: const [],
        name: frame,
      ),
    ],
  );
}

/// A cut of [layers], bottom first.
Cut cutOf(List<Layer> layers) => Cut(
  id: const CutId('cut'),
  name: '1',
  duration: 24,
  canvasSize: const CanvasSize(width: 1920, height: 1080),
  layers: layers,
);

extension on List<SheetBooks> {
  /// Each boundary's books as a sheet tags them with every name written
  /// out ([sheetBookTag] unshortened).
  List<SheetBook> get tagged => [
    for (final (:boundary, :books) in this)
      (boundary: boundary, label: sheetBookTag(books, shortened: false)),
  ];
}

/// [names] as books, each `row` or `row:picture`.
List<SheetBookName> booksNamed(List<String> names) => [
  for (final name in names)
    switch (name.split(':')) {
      [final row, final picture] => (row: row, picture: picture),
      _ => (row: name, picture: null),
    },
];

void main() {
  test('a book sits at the boundary of the cel columns under it, tagged '
      'with its row\'s name and its picture\'s — by its label, never by '
      'its name', () {
    final books = SheetSources.of(
      cut: cutOf([
        picture('BG', frame: '1'),
        cels('A'),
        picture('BOOK', frame: '1'),
        cels('B'),
        cels('C'),
        picture('BOOK', frame: '2'),
        picture(
          'LO',
          frame: '3',
          mark: const LayerMark(
            process: LayerProcess.layout,
            revise: LayerRevise.director,
          ),
        ),
        picture(
          'BOOK',
          frame: '4',
          mark: const LayerMark(process: LayerProcess.paper),
        ),
      ]),
    ).actionBooks.tagged;

    expect(books, [
      (boundary: 1, label: 'BOOK1'),
      (boundary: 3, label: 'BOOK2,LO3'),
    ]);
  });

  test('🗣️F-578: an image row is a book where a cel row would print in '
      'the ACTION block — LO, ラフ原, 原画 and no label; never the conte\'s, '
      'the paper\'s, 動画 or 仕上げ', () {
    // 유저 2026-11-10: Q3 「용지라벨만 북에서 빼는거 ok이고, 애초에
    // 레이아웃,러프원,원화 이외 공정이면 북쪽에 안넣음」 · Q5 「라벨없음도
    // 액션란 취급인걸로 ok」.
    const books = {
      null,
      LayerProcess.layout,
      LayerProcess.roughKey,
      LayerProcess.key,
    };
    for (final process in [null, ...LayerProcess.values]) {
      final marked = SheetSources.of(
        cut: cutOf([
          cels('A'),
          picture('BOOK', frame: '1', mark: LayerMark(process: process)),
        ]),
      ).actionBooks.tagged;

      expect(
        marked,
        books.contains(process) ? [(boundary: 1, label: 'BOOK1')] : isEmpty,
        reason: '$process',
      );
    }
  });

  test('a picture without a name tags the book with its row\'s alone', () {
    final books = SheetSources.of(
      cut: cutOf([cels('A'), picture('BOOK', frame: '  ')]),
    ).actionBooks.tagged;

    expect(books, [(boundary: 1, label: 'BOOK')]);
  });

  test('⛔the tag names the picture the row SHOWS — its bank holds a 겸용 '
      'cut\'s picture of the row too', () {
    // F-98 (유저 2026-09-12: 「이름 안정해지면 별개것임」): each 겸용 cut's
    // image row is born with a picture of its own, and every member's bank
    // holds all of them.
    Frame cel(String id, String name) =>
        Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);
    final books = SheetSources.of(
      cut: cutOf([
        cels('A'),
        Layer(
          id: const LayerId('book'),
          name: 'BOOK',
          kind: LayerKind.image,
          mark: const LayerMark(process: LayerProcess.layout),
          frames: [cel('theirs', '7'), cel('mine', '2')],
          timeline: const {
            0: TimelineExposure.drawing(FrameId('mine'), length: 1),
          },
        ),
      ]),
    ).actionBooks.tagged;

    expect(books, [(boundary: 1, label: 'BOOK2')]);
  });

  test('a row whose sheet switch is off marks nothing — the switch an '
      'image row kept for this', () {
    final books = SheetSources.of(
      cut: cutOf([
        cels('A'),
        picture('BOOK', frame: '1', onTimesheet: false),
      ]),
    ).actionBooks.tagged;

    expect(books, isEmpty);
  });

  test('an attach row marks nothing — it carries no sheet switch of its '
      'own (W5)', () {
    final books = SheetSources.of(
      cut: cutOf([cels('A'), picture('BOOK', frame: '1', attachedTo: 'A')]),
    ).actionBooks.tagged;

    expect(books, isEmpty);
  });

  test('only an image row is a book — another row labelled LO is not', () {
    final books = SheetSources.of(
      cut: cutOf([
        cels('A'),
        Layer(
          id: const LayerId('board'),
          name: 'BOOK',
          kind: LayerKind.storyboard,
          frames: const [],
          mark: const LayerMark(process: LayerProcess.layout),
        ),
      ]),
    ).actionBooks.tagged;

    expect(books, isEmpty);
  });

  test('the boundary counts the columns the sheet prints, not the rows', () {
    final books = SheetSources.of(
      cut: cutOf([
        cels('A'),
        cels('B', onTimesheet: false),
        picture('BOOK', frame: '1'),
      ]),
    ).actionBooks.tagged;

    expect(books, [(boundary: 1, label: 'BOOK1')]);
  });

  test('the sheet carries the books its sources give it', () {
    final document = TimesheetDocument.fromCut(
      cut: cutOf([cels('A'), picture('BOOK', frame: '1'), cels('B')]),
      projectName: 'P',
      fps: 24,
    );

    expect(document.books, [(boundary: 1, label: 'BOOK1')]);
  });

  group('🗣️F-576 (유저 2026-11-09): a tag leaves out the names the book '
      'before it wrote', () {
    test('a row named as the one before prints its picture alone — the '
        'user\'s own example', () {
      expect(
        sheetBookTag(
          booksNamed(['BOOK:1', 'BOOK:2', 'BOOK:3', 'boo:1', 'boo:2', 'BOOK:4']),
          shortened: true,
        ),
        'BOOK1,2,3,boo1,2,BOOK4',
      );
    });

    test('a book named as the one before, picture and all, is left out — '
        'and one with no picture name keeps its row\'s', () {
      expect(
        sheetBookTag(
          booksNamed(['BOOK:1', 'BOOK:2', 'BOOK:2', 'BOOK', 'BOOK']),
          shortened: true,
        ),
        'BOOK1,2,BOOK',
      );
    });

    test('taken off, every name is written out', () {
      expect(
        sheetBookTag(
          booksNamed(['BOOK:1', 'BOOK:2', 'BOOK:2', 'BOOK']),
          shortened: false,
        ),
        'BOOK1,BOOK2,BOOK2,BOOK',
      );
    });

    test('the sheet tags its books as the work\'s format says — shortened '
        'unless taken off', () {
      final cut = cutOf([
        cels('A'),
        picture('BOOK', frame: '1'),
        picture('BOOK', frame: '2'),
      ]);
      TimesheetDocument sheet(TimesheetInfo info) => TimesheetDocument.fromCut(
        cut: cut,
        projectName: 'P',
        fps: 24,
        info: info,
      );

      expect(sheet(TimesheetInfo.empty).books, [
        (boundary: 1, label: 'BOOK1,2'),
      ]);
      expect(
        sheet(
          TimesheetInfo.empty.copyWith(sheetBookNamesShortened: false),
        ).books,
        [(boundary: 1, label: 'BOOK1,BOOK2')],
      );
    });
  });
}
