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
import 'dart:ui' show Rect;

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

  /// The black of the silhouette around each picture window.
  double get silhouetteBorder => 3.2;
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

  /// The page's running total, under the table's right end.
  Rect get pageTotalSlot =>
      Rect.fromLTRB(timeLeft - 40, bodyBottom + 4, bodyRight, bodyBottom + 20);
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
  });

  final String cutId;
  final String cutName;

  /// Which cell of its cut this is — 0 is the one that opens the cut.
  final int cellIndex;
  final ConteCellSource source;

  /// The picture's box, thick black border and all. Wider than the picture
  /// column when the cell encroaches (a horizontal camera move).
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

  /// The cell's whole ROW BAND — cut column through the TIME column, the
  /// full rows the cell claims. The conte ink's anchor rect (R5) and the
  /// clip that keeps a cell's strokes off its neighbours; built exactly
  /// like [ContePlacedCutBand]'s merged box, per cell.
  Rect rowBandRect(ConteSheetMetrics metrics) => Rect.fromLTRB(
    metrics.cutColumnLeft,
    metrics.rowTop(rowOnPage),
    metrics.bodyRight,
    metrics.rowTop(rowOnPage + source.rowSpan),
  );
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
  /// the panel turns to and the paper-plane ink is keyed by.
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
        cells: cells,
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
      if (row + cell.rowSpan > metrics.rowsPerPage) {
        flushPage(hole: true);
        seenOnAPageAlready = true;
      }
      final top = metrics.rowTop(row);
      final bottom = metrics.rowTop(row + cell.rowSpan);
      final pictureRight =
          metrics.actionLeft + metrics.actionWidth * cell.encroachFraction;
      cells.add(
        ContePlacedCell(
          cutId: cut.cutId.value,
          cutName: cut.name,
          cellIndex: index,
          source: cell,
          pictureRect: Rect.fromLTRB(
            metrics.pictureLeft,
            top,
            pictureRight,
            bottom,
          ),
          // The text runs to the page's foot: the columns have no
          // horizontal rules, so the next cell's anchor is what ends it.
          actionRect: Rect.fromLTRB(
            math.max(metrics.actionLeft, pictureRight),
            top,
            metrics.dialogueLeft,
            metrics.bodyBottom,
          ),
          dialogueRect: Rect.fromLTRB(
            metrics.dialogueLeft,
            top,
            metrics.timeLeft,
            metrics.bodyBottom,
          ),
          rowOnPage: row,
        ),
      );
      bandStartRow.putIfAbsent(cut.cutId.value, () => row);
      bandFirstPage.putIfAbsent(cut.cutId.value, () => !seenOnAPageAlready);
      bandEndRow[cut.cutId.value] = row + cell.rowSpan;
      row += cell.rowSpan;
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
