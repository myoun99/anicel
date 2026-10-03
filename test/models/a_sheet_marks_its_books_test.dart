// D24 후반 — THE SHEET MARKS ITS BOOKS (유저 2026-09-25, 사진 셋; 09-26
// 「이름 bg든 북이든 구별없이 이미지레이어면서 미술이면 수정공정뭐던간에
// 북표시」): an image row labelled 美術, whatever its name and its revise,
// is a book; it sits at the boundary of the cel columns under it, tagged
// with its row's name and its picture's; several at one boundary share a
// tag (`a,b`); none under the first cel column, the one over the last
// marked.
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
  LayerMark mark = const LayerMark(process: LayerProcess.art),
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
            process: LayerProcess.art,
            revise: LayerRevise.director,
          ),
        ),
        picture(
          'BOOK',
          frame: '4',
          mark: const LayerMark(process: LayerProcess.layout),
        ),
      ]),
    ).books;

    expect(books, [
      (boundary: 1, label: 'BOOK1'),
      (boundary: 3, label: 'BOOK2,LO3'),
    ]);
  });

  test('a picture without a name tags the book with its row\'s alone', () {
    final books = SheetSources.of(
      cut: cutOf([cels('A'), picture('BOOK', frame: '  ')]),
    ).books;

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
          mark: const LayerMark(process: LayerProcess.art),
          frames: [cel('theirs', '7'), cel('mine', '2')],
          timeline: const {
            0: TimelineExposure.drawing(FrameId('mine'), length: 1),
          },
        ),
      ]),
    ).books;

    expect(books, [(boundary: 1, label: 'BOOK2')]);
  });

  test('a row whose sheet switch is off marks nothing — the switch an '
      'image row kept for this', () {
    final books = SheetSources.of(
      cut: cutOf([
        cels('A'),
        picture('BOOK', frame: '1', onTimesheet: false),
      ]),
    ).books;

    expect(books, isEmpty);
  });

  test('an attach row marks nothing — it carries no sheet switch of its '
      'own (W5)', () {
    final books = SheetSources.of(
      cut: cutOf([cels('A'), picture('BOOK', frame: '1', attachedTo: 'A')]),
    ).books;

    expect(books, isEmpty);
  });

  test('only an image row is a book — another row labelled 美術 is not', () {
    final books = SheetSources.of(
      cut: cutOf([
        cels('A'),
        Layer(
          id: const LayerId('board'),
          name: 'BOOK',
          kind: LayerKind.storyboard,
          frames: const [],
          mark: const LayerMark(process: LayerProcess.art),
        ),
      ]),
    ).books;

    expect(books, isEmpty);
  });

  test('the boundary counts the columns the sheet prints, not the rows', () {
    final books = SheetSources.of(
      cut: cutOf([
        cels('A'),
        cels('B', onTimesheet: false),
        picture('BOOK', frame: '1'),
      ]),
    ).books;

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
}
