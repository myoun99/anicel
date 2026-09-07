part of '../timesheet_document_painter.dart';

/// THE SE PASS — the sheet's SE columns: an entry's start, the red bar
/// it runs, the crossing marks, an empty row, and the vertical text fitted
/// into a cell — as its own object.
///
/// 🚨A collaborator carved out of `TimesheetDocumentPainter` (the audit's
/// SRP cut, 2026-09-02). It reaches the painter through `_painter`.
class _TimesheetSePass {
  _TimesheetSePass(this._painter);

  final TimesheetDocumentPainter _painter;

  /// The timeline's `~` continuation marks, printed (SE globalization
  /// round: "타임시트에도 동일하게 추가"). END: a sound starting inside
  /// this cut runs past its end — the mark straddles the red cut-end
  /// line, centred on its SE column. START: a sound from an earlier cut
  /// spills into row 0 — the mark sits on the column's first row edge.
  /// Pure display, exactly the timeline rows' meaning.
  void paintSeCrossingMarks(Canvas canvas) {
    // The `~` straddles the red line, so it follows the same live length —
    // otherwise a drag leaves the mark hanging where the line used to be.
    final frameCount = _painter.livePlaybackFrameCount;
    final endLine = _painter.layout.cutEndLineFor(frameCount);
    final startTop = _painter.layout.frameRowTop(0);
    final startPosition = _painter.layout.positionOfFrame(0);
    for (
      var column = 0;
      column < _painter.document.columns.length;
      column += 1
    ) {
      final spec = _painter.document.columns[column];
      if (spec.kind != TimesheetColumnKind.se ||
          (!spec.crossesCutEnd && !spec.spillsInAtStart)) {
        continue;
      }
      final columnWidth = _painter.layout.columnWidthFor(spec.kind);
      if (spec.crossesCutEnd &&
          frameCount >= 1 &&
          frameCount <= _painter.document.rowCount &&
          _painter.layout.visiblePageIndexes.contains(endLine.page)) {
        final left =
            _painter.layout.halfLeft(endLine.page, endLine.half) +
            _painter.layout.columnLeftInHalf(column);
        _painter._text(
          canvas,
          '~',
          Offset(left + columnWidth / 2, endLine.y - 5),
          fontSize: 10,
          bold: true,
          centeredAtX: true,
        );
      }
      if (spec.spillsInAtStart &&
          _painter.layout.visiblePageIndexes.contains(startPosition.page)) {
        final left =
            _painter.layout.halfLeft(startPosition.page, startPosition.half) +
            _painter.layout.columnLeftInHalf(column);
        _painter._text(
          canvas,
          '~',
          Offset(left + columnWidth / 2, startTop - 5),
          fontSize: 10,
          bold: true,
          centeredAtX: true,
        );
      }
    }
  }

  /// An SE entry's start cell (R5-⑦, user-approved mockup v4): a full-width
  /// thin red bar RIGHT BEFORE the block start, a compact ACCENT name box
  /// (the app's shared accent — same chip as the timeline/X-sheet rows)
  /// hugging the boundary, the dialogue distributed vertically over the
  /// REST of the span — no duration bar. Single-row entries close with the
  /// red end bar right here; longer ones close from their last held row.
  void paintSeEntryStart(
    Canvas canvas, {
    required TimesheetCell cell,
    required int row,
    required int rowCount,
    required double columnLeft,
    required double columnWidth,
    required double centerX,
    required double cellTop,
  }) {
    const rowHeight = TimesheetDocumentLayout.rowHeight;
    const nameBoxHeight = 12.0;
    final spanLength = cell.spanLength ?? 1;
    final rowsHere = spanLength.clamp(1, rowCount - row);
    final spanBottom = cellTop + rowsHere * rowHeight;
    final seName = cell.seName ?? '';

    // The opening red bar sits ON the start boundary only when this row
    // really is the span's first (page-half continuations skip it).
    if ((cell.spanOffset ?? 0) == 0) {
      paintSeRedBar(
        canvas,
        columnLeft: columnLeft,
        columnWidth: columnWidth,
        y: cellTop + 1,
      );
    }

    var dialogueTop = cellTop + 3;
    if (seName.isNotEmpty) {
      // R6-②: a soft accent tint with dark ink writing — the full-strength
      // accent read too loud against the paper. FULL column width (R7-②:
      // the name box, the red bars and the SE column must share ONE exact
      // width — the old 1px inset read as a mismatched overlay).
      canvas.drawRect(
        Rect.fromLTWH(columnLeft, cellTop + 2, columnWidth, nameBoxHeight),
        Paint()..color = _painter.accent.withValues(alpha: 0.3),
      );
      _painter._text(
        canvas,
        seName,
        Offset(centerX, cellTop + 4),
        fontSize: 7,
        bold: true,
        color: TimesheetDocumentPainter._ink,
        centeredAtX: true,
        maxWidth: columnWidth - 4,
      );
      dialogueTop = cellTop + nameBoxHeight + 4;
    }

    final dialogueExtent = spanBottom - 2 - dialogueTop;
    if (dialogueExtent > 4 && (cell.label ?? '').isNotEmpty) {
      paintDialogueFitColumn(
        canvas,
        cell.label!,
        topCenter: Offset(centerX, dialogueTop),
        extent: dialogueExtent,
        style: const TextStyle(
          color: TimesheetDocumentPainter._ink,
          fontSize: 9,
        ),
      );
    }

    if (spanLength == 1) {
      paintSeRedBar(
        canvas,
        columnLeft: columnLeft,
        columnWidth: columnWidth,
        y: spanBottom - 1,
      );
    }
  }

  /// The full-width thin red bar closing an SE block (and mirrored before
  /// its start) — Toei notation, R5-⑦: frame-width, not a short tick. ONE
  /// geometry with the name box and the SE column itself (R7-②).
  void paintSeRedBar(
    Canvas canvas, {
    required double columnLeft,
    required double columnWidth,
    required double y,
  }) {
    canvas.drawLine(
      Offset(columnLeft, y),
      Offset(columnLeft + columnWidth, y),
      Paint()
        ..color = AppColors.danger
        ..strokeWidth = 2,
    );
  }

  /// An SE column's empty row: the light-gray "no SE here" wash (project
  /// toggle). Print-sheet only — the timeline/X-sheet's dark uncovered
  /// cells already read as empty, and the dotted center guide is retired
  /// everywhere (R5-②).
  void paintSeEmptyRow(
    Canvas canvas, {
    required double columnLeft,
    required double columnWidth,
    required double centerX,
    required double cellTop,
  }) {
    const rowHeight = TimesheetDocumentLayout.rowHeight;
    if (_painter.document.seEmptyFill) {
      canvas.drawRect(
        Rect.fromLTWH(columnLeft, cellTop, columnWidth, rowHeight),
        Paint()..color = TimesheetDocumentPainter._ink.withValues(alpha: 0.05),
      );
    }
  }
}
