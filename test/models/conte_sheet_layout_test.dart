import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/conte/conte_page_marks.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/conte/conte_sheet_source.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_range_policy.dart';

import '../helpers/conte_camera.dart';

/// The conte page: five cells, CUT/TIME merged per cut, and a cell that
/// does not fit moves WHOLE to the next page, leaving a hole.
ConteCellSource _cell(int start, int end, {ConteCameraWork? camera}) =>
    ConteCellSource(
      startFrame: start,
      endFrameExclusive: end,
      pictureFrame: start,
      camera: camera,
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

  test('the work may take the cover or its blank back out — the book is '
      'what is left, and the body still numbers its own pages', () {
    // 유저 2026-10-02 (I-59): 「1페이지 헤더 넣기/빼기, 2페이지 빈용지
    // 넣기빼기」.
    final cuts = [
      for (var index = 0; index < 7; index += 1)
        _cut(
          'c$index',
          duration: 24,
          cumulativeEnd: 24 * (index + 1),
          cells: [_cell(0, 24)],
        ),
    ];
    const body = ContePageKind.body;
    for (final (cover, blank, front) in [
      (false, true, [ContePageKind.blank]),
      (true, false, [ContePageKind.cover]),
      (false, false, <ContePageKind>[]),
    ]) {
      final book = layoutConteBook(
        ConteSheetSource(cuts: cuts, cover: cover, blankPage: blank),
      );
      final said = 'cover $cover, blank page $blank';
      expect(book.map((page) => page.kind), [
        ...front,
        body,
        body,
      ], reason: said);
      expect(
        book.map((page) => page.pageIndex),
        [for (var index = 0; index < book.length; index += 1) index],
        reason: said,
      );
      final bodyPages = book.where((page) => page.kind == body);
      expect(bodyPages.map((page) => page.bodyNumber), [1, 2], reason: said);
      expect(bodyPages.first.cells, hasLength(5), reason: said);
    }
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
          // Two rows tall — its camera pans down a screen — with only one
          // row left: it moves, and row 4 becomes a hole nobody fills.
          _cut(
            'e',
            duration: 48,
            cumulativeEnd: 144,
            cells: [_cell(0, 48, camera: conteCameraPan(down: 1))],
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
  group('camera work lays the cell out (유저 2026-09-30)', () {
    const metrics = ConteSheetMetrics();

    /// The page of [cells], each a cut of its own.
    ContePageLayout pageOf(List<ConteCellSource> cells) => layoutConteSheet(
      ConteSheetSource(
        cuts: [
          for (final (index, cell) in cells.indexed)
            _cut(
              '$index',
              duration: 24,
              cumulativeEnd: 24 * (index + 1),
              cells: [cell],
            ),
        ],
      ),
      metrics: metrics,
    ).first;

    test('a camera that moves down takes a row a screen, and its words stay '
        'beside it', () {
      final cell = pageOf([
        _cell(0, 24, camera: conteCameraPan(down: 1)),
      ]).cells.single;
      expect(cell.rowSpan, 2);
      expect(
        cell.pictureRect.height,
        closeTo(2 * metrics.windowHeight + 2 * metrics.silhouetteBorder, 1e-9),
        reason: 'two screens, and the black round them',
      );
      expect(cell.pictureRect.right, closeTo(metrics.actionLeft, 1e-9));
      expect(cell.wordsTop, metrics.rowTop(0));
      expect(cell.actionRect.left, closeTo(metrics.actionLeft, 1e-9));
    });

    test('🗣️H48: the rows are the cell\'s and the black box only its '
        'picture\'s, at the top of them — whatever shape the camera is (유저 '
        '2026-09-30: 「칸은 2칸공간 차지하더라도 검은칸은 필요한 만큼만」 · '
        '「위쪽정렬로 배치」 · 「카메라해상도는 유저가 마음껏 바꾸는거니까」)',
        () {
      for (final screen in const [
        Size(1920, 1080),
        Size(1440, 1080),
        Size(1080, 1920),
      ]) {
        final shaped = ConteSheetMetrics(
          cameraAspect: screen.width / screen.height,
        );
        final cell = layoutConteSheet(
          ConteSheetSource(
            cuts: [
              _cut(
                '0',
                duration: 24,
                cumulativeEnd: 24,
                cells: [
                  _cell(
                    0,
                    24,
                    camera: conteCameraPan(down: 0.4, screen: screen),
                  ),
                ],
              ),
            ],
          ),
          metrics: shaped,
        ).first.cells.single;
        final shape = '${screen.width} × ${screen.height}';
        expect(cell.rowSpan, 2, reason: 'fixture: 1.4 screens ($shape)');
        final box = cell.pictureRect;
        expect(box.top, closeTo(shaped.rowTop(0), 1e-9), reason: shape);
        expect(box.left, closeTo(shaped.pictureLeft, 1e-9), reason: shape);
        expect(
          box.height - 2 * shaped.silhouetteBorder,
          closeTo(1.4 * shaped.windowHeight, 1e-9),
          reason: 'as tall as its picture ($shape)',
        );
        expect(
          box.right,
          closeTo(shaped.actionLeft, 1e-9),
          reason: 'a screen wide: the column, in the camera\'s shape ($shape)',
        );
        expect(
          box.bottom,
          lessThan(shaped.rowTop(2) - shaped.rowHeight / 4),
          reason: 'the rest of its rows is not the box\'s ($shape)',
        );
        expect(cell.wordsTop, closeTo(shaped.rowTop(0), 1e-9), reason: shape);
      }
    });

    test('however far it moves, its picture takes four rows at most — the '
        'sweep is laid smaller instead (「그림으로서는 가로도 세로도 길면 '
        '4코마분까지만」)', () {
      final work = conteCameraPan(down: 6);
      final cell = pageOf([_cell(0, 24, camera: work)]).cells.single;
      expect(conteCameraPictureRowsMax, 4);
      expect(cell.rowSpan, 4);
      final plan = conteCameraPlan(metrics, work);
      final slot = cell.pictureRect.deflate(metrics.silhouetteBorder);
      expect(
        work.field.height * plan.scale,
        closeTo(slot.height, 1e-9),
        reason: 'seven screens in four rows',
      );
      expect(
        slot.width,
        closeTo(work.field.width * plan.scale, 1e-9),
        reason: 'and the box as wide as the picture laid smaller — short of '
            'the column (H48: 「검은칸은 필요한 만큼만」)',
      );
      expect(
        cell.pictureRect.right,
        lessThan(metrics.actionLeft - 1),
        reason: 'fixture: narrower than a screen',
      );
      expect(
        plan.scale,
        lessThan(metrics.windowHeight / work.screen.height),
        reason: 'smaller than a screen a window',
      );
    });

    test('a camera that moves across reaches into the ACTION column as far as '
        'it needs, and the ACTION words run on beside it', () {
      final cell = pageOf([
        _cell(0, 24, camera: conteCameraPan(across: 0.3)),
      ]).cells.single;
      expect(cell.rowSpan, 1);
      expect(cell.pictureRect.right, greaterThan(metrics.actionLeft + 1));
      expect(cell.pictureRect.right, lessThan(metrics.dialogueLeft));
      expect(cell.actionRect.left, cell.pictureRect.right);
      expect(cell.wordsTop, metrics.rowTop(0));
    });

    // ↩️This case read: 「past the ACTION column it reaches into the
    // dialogue's and the time's … (「초수칸까지도 확장가능하게해」)」, its
    // picture passing `timeLeft` at a screen a window. F-310 (유저
    // 2026-10-06) drew the line a column sooner: 「초수칸말고 se칸까지만
    // 최대치로 잡도록」.
    test('past the ACTION column it reaches through the dialogue\'s and '
        'stops where the time column begins, laid smaller to stay there — '
        'and with no room left beside it, ACTION, dialogue and length ALL '
        'move to the row under it (「내려갈땐 다 같이 내려가도록하자」)', () {
      final cell = pageOf([
        _cell(0, 24, camera: conteCameraPan(across: 0.9)),
      ]).cells.single;
      expect(
        cell.pictureRect.right,
        closeTo(metrics.timeLeft, 1e-9),
        reason: '「초수칸말고 se칸까지만 최대치로」 — at a screen a window '
            'this sweep would stand in the time column',
      );
      expect(
        conteCameraPlan(metrics, conteCameraPan(across: 0.9)).scale,
        lessThan(metrics.windowHeight / 1080),
        reason: 'so it is laid smaller than a screen a window',
      );
      expect(cell.rowSpan, 2, reason: 'its picture\'s row and the words\'');
      expect(
        cell.pictureRect.bottom,
        lessThan(metrics.rowTop(1)),
        reason: 'laid smaller, its black is only as tall as the picture '
            '(H48: 「검은칸은 필요한 만큼만」)',
      );
      expect(cell.wordsTop, closeTo(metrics.rowTop(1), 1e-9));
      expect(cell.dialogueRect.top, cell.wordsTop);
      expect(
        cell.actionRect.left,
        closeTo(metrics.actionLeft, 1e-9),
        reason: 'the whole ACTION column, under the picture',
      );
    });

    test('the words move down as soon as the ACTION column is gone — the '
        'dialogue\'s still half free', () {
      final cell = pageOf([
        _cell(0, 24, camera: conteCameraPan(across: 0.5)),
      ]).cells.single;
      expect(cell.pictureRect.right, greaterThan(metrics.dialogueLeft));
      expect(
        cell.pictureRect.right,
        lessThan(metrics.timeLeft),
        reason: 'fixture: the dialogue column only partly taken',
      );
      expect(cell.rowSpan, 2);
      expect(cell.wordsTop, closeTo(metrics.rowTop(1), 1e-9));
    });

    test('a sweep wider than the page is laid smaller: its picture stops '
        'where the time column begins (↩️it was the page\'s right edge)', () {
      final cell = pageOf([
        _cell(0, 24, camera: conteCameraPan(across: 3)),
      ]).cells.single;
      expect(cell.pictureRect.right, closeTo(metrics.timeLeft, 1e-9));
      expect(
        cell.pictureRect.right,
        lessThan(metrics.bodyRight - 1),
        reason: 'fixture: the time column has a width to stay clear of',
      );
    });

    test('a cell\'s words stop where a later picture stands in their column '
        '— a picture and a value never overlap', () {
      final page = pageOf([
        _cell(0, 24),
        _cell(0, 24, camera: conteCameraPan(across: 0.3)),
        _cell(0, 24, camera: conteCameraPan(across: 0.9)),
      ]);
      final [first, second, third] = page.cells;
      expect(
        first.actionRect.bottom,
        closeTo(second.pictureRect.top, 1e-9),
        reason: 'the second picture reaches into the ACTION column',
      );
      expect(
        first.dialogueRect.bottom,
        closeTo(third.pictureRect.top, 1e-9),
        reason: 'the third reaches into the dialogue\'s',
      );
      expect(
        second.actionRect.bottom,
        closeTo(third.pictureRect.top, 1e-9),
      );
      expect(
        third.actionRect.bottom,
        closeTo(metrics.bodyBottom, 1e-9),
        reason: 'nothing stands under the last one\'s words',
      );
    });
  });
}
