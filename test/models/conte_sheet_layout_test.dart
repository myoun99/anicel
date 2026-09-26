import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/conte/conte_page_marks.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_range_policy.dart';

/// The conte page: five cells, CUT/TIME merged per cut, and a cell that
/// does not fit moves WHOLE to the next page, leaving a hole.
ConteCellSource _cell(int start, int end, {int rowSpan = 1}) => ConteCellSource(
  startFrame: start,
  endFrameExclusive: end,
  pictureFrame: start,
  rowSpan: rowSpan,
);

ConteCutSource _cut(
  String id, {
  required int duration,
  required int cumulativeEnd,
  required List<ConteCellSource> cells,
}) => ConteCutSource(
  cutId: CutId(id),
  name: id,
  durationFrames: duration,
  cumulativeEndFrames: cumulativeEnd,
  cells: cells,
);

void main() {
  test('the sheet is five rows a page', () {
    final pages = layoutConteSheet(
      ConteSheetSource(
        cuts: [
          for (var index = 0; index < 7; index += 1)
            _cut(
              'c$index',
              duration: 24,
              cumulativeEnd: 24 * (index + 1),
              cells: [_cell(0, 24)],
            ),
        ],
      ),
    );

    expect(pages, hasLength(2));
    expect(pages.first.cells, hasLength(5));
    expect(pages.last.cells, hasLength(2));
  });

  test('the book is the cover, its blank back, then the body — and the body '
      'numbers its own pages', () {
    // 유저 2026-09-25: 「1페이지는 표지, 2페이지는 인쇄할때 생각해서
    // 빈용지, 3페이지부터 콘티 본 페이지」 · 「표지는 번호로 인식안하게하자.
    // 콘티 본문만 번호 명명해서 늘어나도록」.
    final book = layoutConteBook(
      ConteSheetSource(
        cuts: [
          for (var index = 0; index < 7; index += 1)
            _cut(
              'c$index',
              duration: 24,
              cumulativeEnd: 24 * (index + 1),
              cells: [_cell(0, 24)],
            ),
        ],
      ),
    );

    expect(book.map((page) => page.kind), [
      ContePageKind.cover,
      ContePageKind.blank,
      ContePageKind.body,
      ContePageKind.body,
    ]);
    expect(book.map((page) => page.pageIndex), [0, 1, 2, 3]);
    expect(book[0].cells, isEmpty);
    expect(book[1].cells, isEmpty);
    final body = book.skip(2).toList();
    expect(body.map((page) => page.bodyNumber), [1, 2]);
    expect(body.map((page) => page.bodyCount), [2, 2]);
    expect(body.first.cells, hasLength(5));
  });

  test('a cut merges its CUT and TIME boxes across its own cells', () {
    final pages = layoutConteSheet(
      ConteSheetSource(
        cuts: [
          _cut(
            'a',
            duration: 30,
            cumulativeEnd: 30,
            cells: [_cell(0, 10), _cell(10, 20), _cell(20, 30)],
          ),
        ],
      ),
    );

    final band = pages.single.cutBands.single;
    expect(band.cutName, 'a');
    expect(band.showsNumber, isTrue);
    expect(band.showsLength, isTrue);
    // Three rows tall: the merge is what makes one cut read as one box.
    expect(
      band.cutRect.height,
      closeTo(pages.single.metrics.rowHeight * 3, 0.001),
    );
  });

  test('a cell that will not fit moves WHOLE, and the rows it left behind '
      'are the hole', () {
    final pages = layoutConteSheet(
      ConteSheetSource(
        cuts: [
          _cut('a', duration: 24, cumulativeEnd: 24, cells: [_cell(0, 24)]),
          _cut('b', duration: 24, cumulativeEnd: 48, cells: [_cell(0, 24)]),
          _cut('c', duration: 24, cumulativeEnd: 72, cells: [_cell(0, 24)]),
          _cut('d', duration: 24, cumulativeEnd: 96, cells: [_cell(0, 24)]),
          // Two rows tall with only one row left: it moves, and row 4
          // becomes a hole nobody fills.
          _cut(
            'e',
            duration: 48,
            cumulativeEnd: 144,
            cells: [_cell(0, 48, rowSpan: 2)],
          ),
        ],
      ),
    );

    expect(pages, hasLength(2));
    expect(pages.first.cells, hasLength(4));
    expect(pages.first.emptyRowsFrom, 4);
    expect(pages.first.hasHole, isTrue);
    expect(pages.last.cells.single.cutName, 'e');
    expect(pages.last.cells.single.rowOnPage, 0);
  });

  test('the page total counts the cuts that END on it', () {
    final source = ConteSheetSource(
      framesPerSecond: 24,
      cuts: [
        _cut('a', duration: 24, cumulativeEnd: 24, cells: [_cell(0, 24)]),
        _cut('b', duration: 36, cumulativeEnd: 60, cells: [_cell(0, 36)]),
      ],
    );
    final pages = layoutConteSheet(source);

    // 60 frames at 24fps: two seconds and twelve frames, printed bare.
    expect(conteLiveTotalOf(pages.single, source, null), '2+12');
  });

  test('the time notation is bare digits — and it is the TIMELINE\'s too '
      '(feedback #12: one notation, not one per surface)', () {
    expect(secondsPlusFramesLabel(51, 24), '2+3');
    expect(secondsPlusFramesLabel(60, 24), '2+12');
    expect(secondsPlusFramesLabel(0, 24), '0+0');
    // What the timeline prints for the same count, through its own entry
    // point: the two used to differ by a zero pad.
    expect(
      timelineDurationLabel(51, showSeconds: true, countingBase: 24),
      secondsPlusFramesLabel(51, 24),
    );
  });

  test('every picture WINDOW is the camera\'s shape exactly, and the text '
      'takes what the column leaves', () {
    for (final aspect in const [16 / 9, 4 / 3, 2.39]) {
      final metrics = ConteSheetMetrics(cameraAspect: aspect);
      for (var row = 0; row < metrics.rowsPerPage; row += 1) {
        final window = metrics.windowRect(row);
        expect(
          window.width / window.height,
          closeTo(aspect, 1e-9),
          reason: 'a window of another shape shows the well beside the '
              'picture as a pale sliver (measured 2026-09-25)',
        );
      }
      expect(
        metrics.actionLeft,
        closeTo(metrics.pictureLeft + metrics.pictureWidth, 0.001),
      );
      expect(metrics.dialogueLeft, greaterThan(metrics.actionLeft));
      expect(metrics.timeLeft, greaterThan(metrics.dialogueLeft));
    }
  });

  test('the cut box stands apart from the table', () {
    const metrics = ConteSheetMetrics();
    expect(
      metrics.pictureLeft - metrics.cutColumnRight,
      metrics.cutGap,
    );
    expect(metrics.cutGap, greaterThan(0));
  });

  test('a cell\'s text reaches the page foot: the columns have no rules to '
      'stop it', () {
    final pages = layoutConteSheet(
      ConteSheetSource(
        cuts: [
          _cut('a', duration: 24, cumulativeEnd: 24, cells: [_cell(0, 24)]),
          _cut('b', duration: 24, cumulativeEnd: 48, cells: [_cell(0, 24)]),
        ],
      ),
    );

    final page = pages.single;
    for (final cell in page.cells) {
      expect(cell.actionRect.bottom, closeTo(page.metrics.bodyBottom, 0.001));
      expect(cell.dialogueRect.bottom, closeTo(page.metrics.bodyBottom, 0.001));
    }
    // But each one is ANCHORED at its own cell's top.
    expect(
      page.cells.first.actionRect.top,
      closeTo(page.metrics.bodyTop, 0.001),
    );
    expect(
      page.cells.last.actionRect.top,
      closeTo(page.metrics.rowTop(1), 0.001),
    );
  });
}
