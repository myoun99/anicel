import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/conte/conte_sheet_layout.dart';
import 'package:quick_animaker_v2/src/models/conte/conte_sheet_source.dart';
import 'package:quick_animaker_v2/src/models/cut_id.dart';

/// The conte page: five cells, CUT/TIME merged per cut, and a cell that
/// does not fit moves WHOLE to the next page leaving a marked hole.
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
    final pages = layoutConteSheet(
      ConteSheetSource(
        framesPerSecond: 24,
        cuts: [
          _cut('a', duration: 24, cumulativeEnd: 24, cells: [_cell(0, 24)]),
          _cut('b', duration: 36, cumulativeEnd: 60, cells: [_cell(0, 36)]),
        ],
      ),
    );

    // 60 frames at 24fps: two seconds and twelve frames, printed bare.
    expect(pages.single.pageTotalLabel, '2+12');
  });

  test('the time notation drops the padding the timeline keeps', () {
    expect(conteTimeLabel(51, 24), '2+3');
    expect(conteTimeLabel(60, 24), '2+12');
    expect(conteTimeLabel(0, 24), '0+0');
  });

  test('the picture column keeps the camera ratio and the text takes what '
      'is left', () {
    const metrics = ConteSheetMetrics(cameraAspect: 16 / 9);

    expect(metrics.pictureWidth, closeTo(metrics.rowHeight * 16 / 9, 0.001));
    expect(
      metrics.actionLeft,
      closeTo(metrics.pictureLeft + metrics.pictureWidth, 0.001),
    );
    expect(metrics.dialogueLeft, greaterThan(metrics.actionLeft));
    expect(metrics.timeLeft, greaterThan(metrics.dialogueLeft));
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
