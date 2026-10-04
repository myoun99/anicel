/// Where everything on a conte page goes.
///
/// Pure geometry over [ConteSheetSource]: no canvas, no widgets, no
/// project. The panel, the PNG export and the PDF export all draw THIS —
/// one layout engine, so what you see on screen is what lands on paper
/// (the timesheet export's precedent, generalized).
///
/// Measurements are in POINTS (1/72"), which is A4 at 595.28 x 841.89 and
/// also what a PDF wants natively; the screen just scales them.
library;

import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import '../canvas_size.dart';
import '../sheet_paper.dart';
import 'conte_sheet_source.dart';

/// The sheet's fixed measurements — the first preset's page (유저
/// 2026-09-25, the reference sheets: 「위에 헤더에 컷 화면 내용 초 … 아래부분은
/// 가로선으로 칸이 나뉘어져있지않아 … 컷 칸은 화면/내용/초랑 공간
/// 떨어져있어」).
class ConteSheetMetrics {
  const ConteSheetMetrics({
    this.pageWidth = 595.28,
    this.pageHeight = 841.89,
    this.cameraAspect = 16 / 9,
  });

  final double pageWidth;
  final double pageHeight;

  /// THE PAPER'S PIXELS A POINT TAKES (F-294, 유저 2026-10-05: 「콘티패널이랑
  /// 컷봉투패널의 용지는 300dpi인 2480x3508으로함」): this page laid on the
  /// conte's paper (`SheetPaper.conte`) as large as fits — the page is A4
  /// and so is the paper, so it fills it (to the point size's own rounding:
  /// 841.89pt come to 3507.4 of its 3508 pixels). What the panel shows the
  /// sheet at (`SheetCanvasPanel.paperScale`), and the conte ink's
  /// resolution: its surfaces' pixels per page point — what the ink is
  /// drawn at and what every printer lays it back at. A pixel of the ink is
  /// a pixel of the paper, so a brush of a size at 100% draws on the sheet
  /// as wide as on the canvas.
  ///
  /// ↩️It was `conteInkScale`, a number of the ink's own, and what follows
  /// is its history. ONE, the canvas's grade (유저 2026-09-26,
  /// one-paper-brush-width-Q2: 「해상도를 캔버스처럼 낮추기」): a brush of a
  /// size at 100% draws on the sheet as wide as on the canvas, and a surface
  /// pixel is a pixel of the brush's own size. It was 4 — a brush four times
  /// thinner than on the canvas at the same size, and sixteen times the
  /// memory. One pixel a point kept the brush as wide as on the canvas only
  /// because the paper itself was shown a point a pixel — a page 595 pixels
  /// across, and handwriting as coarse as that (「지금까지가 잉크가 이상하게
  /// 됬던거뿐이야」). The paper has a resolution of its own now; the ink is
  /// kept at it, and the brush is as wide as on the canvas still.
  ///
  /// ↩️The page painter kept a copy of the controller's number so as not to
  /// import the input side; two numbers that must agree are two chances to
  /// print ink at a scale it was not drawn at.
  ///
  /// ↩️↩️The conte's paper drew a brush as thin as the pictures beside it for
  /// two days (F-217-Q1 「종이에서는 붓을 그림 칸 비율로 줄여 긋기」, while
  /// a stroke crossed from a picture onto the paper); the user took it back
  /// once a stroke stays in the cell it starts in (2026-09-30, H50: 「원본
  /// 1:1그대로 공용로직 그대로 적용해서 원복하자. 지금 브러시 너무작은데
  /// 중요한건 너무작아서 브러시가 끊겨서」). The paper reads the brush in
  /// its own pixels, as the timesheet's and the envelope's do.
  double get paperScale =>
      SheetPaper.conte.around(Size(pageWidth, pageHeight)).scale;

  /// The paper of one page, in pixels — what a page image is at 1x.
  CanvasSize get paperPixelSize => SheetPaper.conte.pixelSize;

  /// Left and right: the cut box starts here, the table ends here.
  double get marginX => 30;

  /// The band above the table: the page number on its left, the company
  /// logo on its right (유저 답 conte-body-header: 「쪽번호를 왼쪽위로
  /// 옮기고(1/51이런식으로 전체 페이지도 표시), 오른쪽위는 회사로고」).
  double get topBandTop => 9;
  double get topBandHeight => 20;
  double get logoWidth => 72;

  double get tableTop => 34;

  /// The header ROW — カット · 画面 · ACTION · DIALOGUE · 秒.
  double get headerRowHeight => 18;

  /// FIVE, fixed (design): a conte page is five cells, and a sheet whose
  /// row count drifts with content stops being a sheet.
  int get rowsPerPage => 5;

  /// The two number columns are as wide as their numbers set in the app's
  /// face (유저 2026-09-25: 「글꼴 앱에서 정한거 통일」), whose digits are
  /// wide — 0.76em. A four-digit cut number at 9pt bold measures 27.4pt.
  /// The numbers print on one line ([SheetWordsFit.oneLine]); ↩️in 28 and
  /// 32 a total broke into two lines and sat on the block length above it.
  double get cutColumnWidth => 34;

  /// The cut box stands apart from the table.
  double get cutGap => 6;

  /// Just 「00+00」 (유저 2026-09-25: 「초수 칸 너무 좌우 기니까 좀 더
  /// 슬림하게. 00+00 이정도 크기가 딱 들어갈정도로」): the total at 9pt bold
  /// in the app's face measures 34.9pt (BIZ's digits are all one width, so
  /// 「99+23」 too), and [timeInset] stands on each side. ↩️It was 44.
  double get timeColumnWidth => 39;

  /// What the time column's numbers keep off its two rules.
  double get timeInset => 2;

  /// The black of the silhouette around each picture window — heavier than
  /// a rule by far, toward the reference sheet's (유저 2026-09-25: 「지브리
  /// 콘티는 검정실루엣 더 두껍거든? 그정도까진 아니라도 지금 좀 더
  /// 두껍게」). ↩️It was 3.2.
  double get silhouetteBorder => 5;
  double get ruleWidth => 0.8;

  /// The project's camera ratio. Every picture WINDOW is exactly this shape
  /// and the column is the window plus the silhouette's black — the picture
  /// keeps the film's shape and the text columns take what is left. A
  /// window of another shape showed the well beside every picture as a pale
  /// sliver (measured 2026-09-25, one of the three lines round a frame).
  final double cameraAspect;

  double get bodyLeft => marginX;
  double get bodyRight => pageWidth - marginX;
  double get bodyTop => tableTop + headerRowHeight;
  double get bodyBottom => pageHeight - 56;
  double get bodyWidth => bodyRight - bodyLeft;
  double get bodyHeight => bodyBottom - bodyTop;
  double get rowHeight => bodyHeight / rowsPerPage;

  double get windowHeight => rowHeight - 2 * silhouetteBorder;
  double get pictureWidth =>
      windowHeight * cameraAspect + 2 * silhouetteBorder;

  double get cutColumnLeft => bodyLeft;
  double get cutColumnRight => cutColumnLeft + cutColumnWidth;
  double get pictureLeft => cutColumnRight + cutGap;
  double get actionLeft => pictureLeft + pictureWidth;
  double get timeLeft => bodyRight - timeColumnWidth;

  /// The two text columns split whatever the picture leaves.
  double get textWidth => math.max(0, timeLeft - actionLeft);
  double get actionWidth => textWidth / 2;
  double get dialogueLeft => actionLeft + actionWidth;
  double get dialogueWidth => textWidth - actionWidth;

  double rowTop(int rowOnPage) => bodyTop + rowOnPage * rowHeight;

  /// Row [row]'s picture window — the silhouette's hole.
  ///
  /// ↩️SQUARE, like every window of the sheet (유저 2026-09-30: 「칸 자체를
  /// 둥근걸 버리고 네모낳게 한다는게 맞아. 보통칸이든 뭐든 진짜 상관없이
  /// 그냥 기본을」). It wore the app's window corner from 09-25 (「지브리콘티
  /// 처럼 모서리 둥글게하자」) until a window grown by camera work had to be
  /// drawn: 「근데 그냥 둥근모서리 포기하자. 사각형으로하자」.
  Rect windowRect(int row) => Rect.fromLTRB(
    pictureLeft + silhouetteBorder,
    rowTop(row) + silhouetteBorder,
    actionLeft - silhouetteBorder,
    rowTop(row + 1) - silhouetteBorder,
  );

  Rect get pageNumberSlot =>
      Rect.fromLTWH(marginX, topBandTop, 120, topBandHeight);

  Rect get logoSlot => Rect.fromLTWH(
    bodyRight - logoWidth,
    topBandTop,
    logoWidth,
    topBandHeight,
  );

  /// The page's running total, under the time column and centred on it
  /// like the lengths above it (유저 2026-09-25: 「컷 길이도 블록길이나
  /// 컷길이나 페이지 총 길이나 동일하게 좌우 중앙정렬」) — the slot runs
  /// past the column on both sides alike, so a total wider than the column
  /// still centres on it.
  Rect get pageTotalSlot => Rect.fromLTRB(
    timeLeft - 20,
    bodyBottom + 4,
    bodyRight + 20,
    bodyBottom + 20,
  );
}

/// One cell placed on a page.
class ContePlacedCell {
  const ContePlacedCell({
    required this.cutId,
    required this.cutName,
    required this.cellIndex,
    required this.source,
    required this.pictureRect,
    required this.actionRect,
    required this.dialogueRect,
    required this.rowOnPage,
    this.rowSpan = 1,
  });

  final String cutId;
  final String cutName;

  /// Which cell of its cut this is — 0 is the one that opens the cut.
  final int cellIndex;
  final ConteCellSource source;

  /// The picture's box, thick black border and all — over more rows and
  /// into the columns beside it when the camera works ([conteCameraPlan]),
  /// but only as far as the picture in it: the rows the cell takes are the
  /// cell's, and what the box leaves of them is paper.
  final Rect pictureRect;

  /// The ACTION and DIALOGUE text boxes.
  ///
  /// Their height reaches to the BOTTOM of the page body, not to the end of
  /// the cell: the text columns have no horizontal dividers (design), so
  /// what a cell's text really is is a flow ANCHORED at the cell's top that
  /// runs until the next cell's text starts. Overflow that reaches the next
  /// anchor is shrunk a step and then clipped — one rule, and spill,
  /// carry-over and blank space all fall out of it.
  final Rect actionRect;
  final Rect dialogueRect;

  final int rowOnPage;

  /// How many sheet ROWS the cell takes: its picture's, and one more under
  /// them where its words moved down ([conteCameraPlan]).
  final int rowSpan;

  /// Where the cell's words start — ACTION, dialogue and length alike: its
  /// first row, or the row under its picture
  /// ([ConteCameraPlan.wordsBelow]).
  double get wordsTop => actionRect.top;

  /// This cell with its text boxes ending at [action] and [dialogue] where
  /// those are given ([_wordsStopAtPictures]).
  ContePlacedCell _withWordsEndingAt({double? action, double? dialogue}) =>
      ContePlacedCell(
        cutId: cutId,
        cutName: cutName,
        cellIndex: cellIndex,
        source: source,
        pictureRect: pictureRect,
        actionRect: action == null
            ? actionRect
            : Rect.fromLTRB(
                actionRect.left,
                actionRect.top,
                actionRect.right,
                math.min(actionRect.bottom, action),
              ),
        dialogueRect: dialogue == null
            ? dialogueRect
            : Rect.fromLTRB(
                dialogueRect.left,
                dialogueRect.top,
                dialogueRect.right,
                math.min(dialogueRect.bottom, dialogue),
              ),
        rowOnPage: rowOnPage,
        rowSpan: rowSpan,
      );

  /// The cell's whole ROW BAND — cut column through the TIME column, the
  /// full rows the cell claims. The conte ink's anchor rect (R5) and the
  /// clip that keeps a cell's strokes off its neighbours; built exactly
  /// like [ContePlacedCutBand]'s merged box, per cell.
  Rect rowBandRect(ConteSheetMetrics metrics) => Rect.fromLTRB(
    metrics.cutColumnLeft,
    metrics.rowTop(rowOnPage),
    metrics.bodyRight,
    metrics.rowTop(rowOnPage + rowSpan),
  );
}

/// The most rows a cell's picture takes, however far its camera travels
/// (유저 2026-09-30: 「그림으로서는 가로도 세로도 길면 4코마분까지만
/// 차지하게 하고, 5코마째에서 해당 칸에 들어갔어야할 액션이랑 se
/// 넣는거지」) — a page's fifth row is left for the words it pushed down.
const int conteCameraPictureRowsMax = 4;

/// Where a cell's camera work lays its picture on the page.
typedef ConteCameraPlan = ({
  /// The rows the picture takes.
  int pictureRows,

  /// Where the picture's box ends on the right, and how tall it is — the
  /// picture and the silhouette's black round it, and not a row more (유저
  /// 2026-09-30, H48: 「칸은 2칸공간 차지하더라도 검은칸은 필요한 만큼만」):
  /// past the picture column's edge into the columns beside it, or short
  /// of it.
  double pictureRight,
  double pictureHeight,

  /// Whether the cell's words — ACTION, dialogue and its length — print on
  /// the row under the picture instead of beside it.
  bool wordsBelow,

  /// The paper a pixel of the swept canvas takes: a screen to a row's
  /// window, less where the sweep would pass the picture's rows or the
  /// page's right edge.
  double scale,
});

/// How much of the page [work] takes (유저 2026-09-30).
///
/// The picture shows the canvas the camera sweeps at a screen a row: down
/// over as many rows as it is screens tall, up to
/// [conteCameraPictureRowsMax], and right as far as it is wide — into the
/// ACTION column, then the dialogue's, then the time's (「필요한만큼 알아서
/// 침범」 · 「se칸까지」 · 「초수칸까지도 확장가능하게해」). A sweep larger than
/// that is laid smaller ([ConteCameraPlan.scale]).
///
/// Once the picture takes the whole ACTION column there is no room for the
/// cell's words beside it, and they ALL move to the row under it — the
/// length too (「침범해서 공간없으면 아래칸을 쓰는게」 · 「초수도
/// 다음코마에 넣으면되니까」 · 「내려갈땐 다 같이 내려가도록하자」).
ConteCameraPlan conteCameraPlan(ConteSheetMetrics m, ConteCameraWork? work) {
  if (work == null) {
    return (
      pictureRows: 1,
      pictureRight: m.actionLeft,
      pictureHeight: m.rowHeight,
      wordsBelow: false,
      scale: 1,
    );
  }
  final screensTall = work.field.height / work.screen.height;
  final rows = (screensTall - 1e-9).ceil().clamp(1, conteCameraPictureRowsMax);
  final scale = _fieldScale(m, work, rows);
  final right =
      m.pictureLeft + work.field.width * scale + 2 * m.silhouetteBorder;
  return (
    pictureRows: rows,
    pictureRight: right,
    pictureHeight: work.field.height * scale + 2 * m.silhouetteBorder,
    wordsBelow: right >= m.dialogueLeft - 1e-9,
    scale: scale,
  );
}

/// [ConteCameraPlan.scale] for a picture [pictureRows] rows tall.
double _fieldScale(
  ConteSheetMetrics m,
  ConteCameraWork work,
  int pictureRows,
) {
  final tallest = pictureRows * m.rowHeight - 2 * m.silhouetteBorder;
  final widest = m.bodyRight - m.pictureLeft - 2 * m.silhouetteBorder;
  return [
    m.windowHeight / work.screen.height,
    tallest / work.field.height,
    widest / work.field.width,
  ].reduce(math.min);
}

/// The lines that START in [cell]'s span, in the sheet's printed shape —
/// the ONE reading both renderers (panel painter and PDF writer) share.
/// Dialogue is the SE blocks' (design G), so a cell prints whatever was
/// said while it was on screen.
String contePrintedDialogueFor(ConteSheetSource source, ContePlacedCell cell) {
  for (final cut in source.cuts) {
    if (cut.cutId.value != cell.cutId) {
      continue;
    }
    return [
      for (final line in cut.dialogue)
        if (line.startFrame >= cell.source.startFrame &&
            line.startFrame < cell.source.endFrameExclusive)
          line.printed,
    ].join('\n');
  }
  return '';
}

/// A cut's CUT/TIME band on a page — merged across the cut's cells (design:
/// the number sits top-left of the merged box, the length bottom-right).
class ContePlacedCutBand {
  const ContePlacedCutBand({
    required this.cutId,
    required this.cutName,
    required this.cutRect,
    required this.timeRect,
    required this.showsNumber,
    required this.showsLength,
  });

  final String cutId;
  final String cutName;
  final Rect cutRect;
  final Rect timeRect;

  /// A cut split across pages prints its number on the first page it
  /// appears and its length on the last — the two ends of one box that
  /// happens to be cut in half by the page.
  final bool showsNumber;
  final bool showsLength;
}

/// What a page of the conte IS (유저 2026-09-25: 「보통 1페이지는 표지,
/// 2페이지는 인쇄할때 생각해서 빈용지, 3페이지부터 콘티 본 페이지」).
enum ContePageKind {
  /// The work, its episode, its picture, its length and its conte artist.
  cover,

  /// The cover's back when printed on both sides — nothing on it, so the
  /// body's first page lands on a right-hand page.
  blank,

  /// The sheet proper: five cells a page.
  body,
}

/// One page of the sheet.
class ContePageLayout {
  const ContePageLayout({
    required this.pageIndex,
    required this.cells,
    required this.cutBands,
    required this.emptyRowsFrom,
    required this.metrics,
    this.kind = ContePageKind.body,
    int? bodyIndex,
    this.bodyCount = 1,
  }) : bodyIndex = bodyIndex ?? pageIndex;

  /// Where the page stands in the whole conte, cover included — the index
  /// the panel turns to.
  final int pageIndex;
  final ContePageKind kind;
  final List<ContePlacedCell> cells;
  final List<ContePlacedCutBand> cutBands;

  /// Where a BODY page stands among the body's pages, from 0.
  final int bodyIndex;

  /// How many body pages the sheet has — the N of the 「n / N」 a body page
  /// prints top-left.
  final int bodyCount;

  /// This page's number among the body's pages, from 1 — the cover and the
  /// blank page carry none (유저 답 conte-page-numbering: 「그냥 표지는
  /// 번호로 인식안하게하자. 콘티 본문만 번호 명명해서 늘어나도록」).
  int get bodyNumber => bodyIndex + 1;

  /// The first row a cell could not be placed on, or null when the page is
  /// full. Nothing marks the hole on paper any more (user, 2026-08-06: the
  /// big X is gone) — a blank row is just a blank row.
  final int? emptyRowsFrom;

  final ConteSheetMetrics metrics;

  bool get hasHole => emptyRowsFrom != null;
}

/// The whole conte as printed: the cover, the blank page behind it, then
/// the body [layoutConteSheet] lays out — the order the panel turns through
/// and the exports print.
List<ContePageLayout> layoutConteBook(
  ConteSheetSource source, {
  ConteSheetMetrics metrics = const ConteSheetMetrics(),
}) {
  final body = layoutConteSheet(source, metrics: metrics);
  ContePageLayout bare(int index, ContePageKind kind) => ContePageLayout(
    pageIndex: index,
    kind: kind,
    cells: const [],
    cutBands: const [],
    emptyRowsFrom: null,
    metrics: metrics,
    bodyCount: body.length,
  );
  return [
    bare(0, ContePageKind.cover),
    bare(1, ContePageKind.blank),
    for (final page in body)
      ContePageLayout(
        pageIndex: page.pageIndex + 2,
        bodyIndex: page.pageIndex,
        cells: page.cells,
        cutBands: page.cutBands,
        emptyRowsFrom: page.emptyRowsFrom,
        metrics: metrics,
        bodyCount: body.length,
      ),
  ];
}

/// [cells] as their words read on the page: a cell's text runs to the
/// page's foot, but not into a later cell's picture standing in its column
/// (camera work, [conteCameraPlan]) — a picture and a value never overlap,
/// which is what lets the page's strata stack in any order.
List<ContePlacedCell> _wordsStopAtPictures(List<ContePlacedCell> cells) => [
  for (final (index, cell) in cells.indexed)
    cell._withWordsEndingAt(
      action: _firstPictureIn(cells.skip(index + 1), cell.actionRect),
      dialogue: _firstPictureIn(cells.skip(index + 1), cell.dialogueRect),
    ),
];

/// The top of the first of the [later] cells' pictures that stands in
/// [words]' column, below where they start — or null.
double? _firstPictureIn(Iterable<ContePlacedCell> later, Rect words) {
  for (final cell in later) {
    final picture = cell.pictureRect;
    if (picture.right > words.left &&
        picture.left < words.right &&
        picture.top >= words.top) {
      return picture.top;
    }
  }
  return null;
}

/// Lays [source] out onto pages.
///
/// The rule for breaking is the design's: a cell never straddles a page. A
/// tall cell that will not fit in the rows left moves WHOLE to the next
/// page, and the rows it vacated become the hole.
List<ContePageLayout> layoutConteSheet(
  ConteSheetSource source, {
  ConteSheetMetrics metrics = const ConteSheetMetrics(),
}) {
  final pages = <ContePageLayout>[];

  var row = 0;
  var cells = <ContePlacedCell>[];
  var bands = <ContePlacedCutBand>[];
  var endingHere = <ConteCutSource>[];
  // Per page, where each cut's band starts and how far it reaches.
  var bandStartRow = <String, int>{};
  var bandEndRow = <String, int>{};
  var bandFirstPage = <String, bool>{};

  void flushPage({required bool hole}) {
    for (final entry in bandStartRow.entries) {
      final cutId = entry.key;
      final startRow = entry.value;
      final endRow = bandEndRow[cutId]!;
      final cut = source.cuts.firstWhere((c) => c.cutId.value == cutId);
      final top = metrics.rowTop(startRow);
      final bottom = metrics.rowTop(endRow);
      bands.add(
        ContePlacedCutBand(
          cutId: cutId,
          cutName: cut.name,
          cutRect: Rect.fromLTRB(
            metrics.cutColumnLeft,
            top,
            metrics.cutColumnLeft + metrics.cutColumnWidth,
            bottom,
          ),
          timeRect: Rect.fromLTRB(
            metrics.timeLeft,
            top,
            metrics.bodyRight,
            bottom,
          ),
          showsNumber: bandFirstPage[cutId] ?? true,
          showsLength: endingHere.any((c) => c.cutId.value == cutId),
        ),
      );
    }
    pages.add(
      ContePageLayout(
        pageIndex: pages.length,
        cells: _wordsStopAtPictures(cells),
        cutBands: bands,
        emptyRowsFrom: hole ? row : null,
        metrics: metrics,
      ),
    );
    row = 0;
    cells = <ContePlacedCell>[];
    bands = <ContePlacedCutBand>[];
    endingHere = <ConteCutSource>[];
    bandStartRow = <String, int>{};
    bandEndRow = <String, int>{};
    bandFirstPage = <String, bool>{};
  }

  for (final cut in source.cuts) {
    var seenOnAPageAlready = false;
    for (var index = 0; index < cut.cells.length; index += 1) {
      final cell = cut.cells[index];
      // A cell never straddles a page: one that does not fit moves whole,
      // and what it leaves behind is the hole the big X marks.
      final plan = conteCameraPlan(metrics, cell.camera);
      final rowSpan = plan.pictureRows + (plan.wordsBelow ? 1 : 0);
      if (row + rowSpan > metrics.rowsPerPage) {
        flushPage(hole: true);
        seenOnAPageAlready = true;
      }
      final top = metrics.rowTop(row);
      final wordsTop = plan.wordsBelow
          ? metrics.rowTop(row + plan.pictureRows)
          : top;
      cells.add(
        ContePlacedCell(
          cutId: cut.cutId.value,
          cutName: cut.name,
          cellIndex: index,
          source: cell,
          // At the top of the cell's rows (유저 2026-09-30, H48:
          // 「위쪽정렬로 배치」).
          pictureRect: Rect.fromLTRB(
            metrics.pictureLeft,
            top,
            plan.pictureRight,
            top + plan.pictureHeight,
          ),
          // The text runs to the page's foot: the columns have no
          // horizontal rules, so the next cell's anchor is what ends it.
          actionRect: Rect.fromLTRB(
            plan.wordsBelow
                ? metrics.actionLeft
                : math.max(metrics.actionLeft, plan.pictureRight),
            wordsTop,
            metrics.dialogueLeft,
            metrics.bodyBottom,
          ),
          dialogueRect: Rect.fromLTRB(
            metrics.dialogueLeft,
            wordsTop,
            metrics.timeLeft,
            metrics.bodyBottom,
          ),
          rowOnPage: row,
          rowSpan: rowSpan,
        ),
      );
      bandStartRow.putIfAbsent(cut.cutId.value, () => row);
      bandFirstPage.putIfAbsent(cut.cutId.value, () => !seenOnAPageAlready);
      bandEndRow[cut.cutId.value] = row + rowSpan;
      row += rowSpan;
      if (row >= metrics.rowsPerPage) {
        if (index == cut.cells.length - 1) {
          endingHere.add(cut);
        }
        flushPage(hole: false);
        seenOnAPageAlready = true;
      } else if (index == cut.cells.length - 1) {
        endingHere.add(cut);
      }
    }
  }
  if (cells.isNotEmpty || pages.isEmpty) {
    flushPage(hole: row < metrics.rowsPerPage);
  }
  return [
    for (final page in pages)
      ContePageLayout(
        pageIndex: page.pageIndex,
        cells: page.cells,
        cutBands: page.cutBands,
        emptyRowsFrom: page.emptyRowsFrom,
        metrics: page.metrics,
        bodyCount: pages.length,
      ),
  ];
}
