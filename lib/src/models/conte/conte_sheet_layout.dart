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

import '../project_frame_rate.dart' show secondsPlusFramesLabel;
import 'conte_sheet_source.dart';

/// The sheet's fixed measurements.
class ConteSheetMetrics {
  const ConteSheetMetrics({
    this.pageWidth = 595.28,
    this.pageHeight = 841.89,
    this.margin = 28,
    this.headerHeight = 34,
    this.rowsPerPage = 5,
    this.cutColumnWidth = 30,
    this.timeColumnWidth = 38,
    this.cameraAspect = 16 / 9,
  });

  final double pageWidth;
  final double pageHeight;
  final double margin;
  final double headerHeight;

  /// FIVE, fixed (design): a conte page is five cells, and a sheet whose
  /// row count drifts with content stops being a sheet.
  final int rowsPerPage;

  final double cutColumnWidth;
  final double timeColumnWidth;

  /// The project's camera ratio. The PICTURE column is as wide as a row is
  /// tall times this — the picture keeps the film's shape and the text
  /// columns take what is left. Letterboxing it to a fixed column would
  /// make the cell's silhouette disagree with the cut's, which the design
  /// refuses.
  final double cameraAspect;

  double get bodyLeft => margin;
  double get bodyRight => pageWidth - margin;
  double get bodyTop => margin + headerHeight;
  double get bodyBottom => pageHeight - margin;
  double get bodyWidth => bodyRight - bodyLeft;
  double get bodyHeight => bodyBottom - bodyTop;
  double get rowHeight => bodyHeight / rowsPerPage;

  double get pictureWidth => rowHeight * cameraAspect;

  double get cutColumnLeft => bodyLeft;
  double get pictureLeft => cutColumnLeft + cutColumnWidth;
  double get actionLeft => pictureLeft + pictureWidth;
  double get timeLeft => bodyRight - timeColumnWidth;

  /// The two text columns split whatever the picture leaves.
  double get textWidth => math.max(0, timeLeft - actionLeft);
  double get actionWidth => textWidth / 2;
  double get dialogueLeft => actionLeft + actionWidth;
  double get dialogueWidth => textWidth - actionWidth;

  double rowTop(int rowOnPage) => bodyTop + rowOnPage * rowHeight;
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
}

/// A cut's CUT/TIME band on a page — merged across the cut's cells (design:
/// the number sits top-left of the merged box, the length bottom-right).
class ContePlacedCutBand {
  const ContePlacedCutBand({
    required this.cutId,
    required this.cutName,
    required this.cutRect,
    required this.timeRect,
    required this.lengthLabel,
    required this.showsNumber,
    required this.showsLength,
  });

  final String cutId;
  final String cutName;
  final Rect cutRect;
  final Rect timeRect;

  /// The cut's own length, printed bottom-right of the TIME box.
  final String lengthLabel;

  /// A cut split across pages prints its number on the first page it
  /// appears and its length on the last — the two ends of one box that
  /// happens to be cut in half by the page.
  final bool showsNumber;
  final bool showsLength;
}

/// One page of the sheet.
class ContePageLayout {
  const ContePageLayout({
    required this.pageIndex,
    required this.cells,
    required this.cutBands,
    required this.emptyRowsFrom,
    required this.pageTotalLabel,
    required this.metrics,
  });

  final int pageIndex;
  final List<ContePlacedCell> cells;
  final List<ContePlacedCutBand> cutBands;

  /// The first row a cell could not be placed on, or null when the page is
  /// full. The rows from here down get ONE big X (design): the hole is
  /// deliberate, and paper says so with a stroke rather than with grey.
  final int? emptyRowsFrom;

  /// The running total printed at the page's foot: the lengths of the cuts
  /// that END on this page (design — a cut spanning pages is counted where
  /// it finishes).
  final String pageTotalLabel;

  final ConteSheetMetrics metrics;

  bool get hasHole => emptyRowsFrom != null;
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
          lengthLabel: secondsPlusFramesLabel(
            cut.durationFrames,
            source.framesPerSecond,
          ),
          showsNumber: bandFirstPage[cutId] ?? true,
          showsLength: endingHere.any((c) => c.cutId.value == cutId),
        ),
      );
    }
    final total = endingHere.fold<int>(
      0,
      (sum, cut) => sum + cut.durationFrames,
    );
    pages.add(
      ContePageLayout(
        pageIndex: pages.length,
        cells: cells,
        cutBands: bands,
        emptyRowsFrom: hole ? row : null,
        pageTotalLabel: secondsPlusFramesLabel(total, source.framesPerSecond),
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
  return pages;
}
