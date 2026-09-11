part of '../timesheet_document_painter.dart';

/// THE CELLS PASS — one half of the sheet: the cells it shows for a
/// layer, the row range on the page, and painting them — as its own
/// object.
///
/// 🚨A collaborator carved out of `TimesheetDocumentPainter` (the audit's
/// SRP cut, 2026-09-02). It reaches the painter through `_painter`.
class _TimesheetCellsPass {
  _TimesheetCellsPass(this._painter);

  final TimesheetDocumentPainter _painter;

  /// The column's display cells, with an in-flight drag preview
  /// substituted for its layer. Every layer-backed column kind previews
  /// (UI-R18 #7 — action, SE, camera instruction): the column's own baked
  /// [TimesheetColumn.previewCellsBuilder] re-derives the cells, so the
  /// painter never learns each kind's recipe. SE previews arrive as
  /// DISPLAY clones under the same id (the timeline's seam), so the SE
  /// windowing stays the document's job.
  List<TimesheetCell> displayCellsFor(TimesheetColumn column) {
    final preview = _painter.dragPreview?.value;
    final layerId = column.layerId;
    final rebuild = column.previewCellsBuilder;
    if (preview == null || layerId == null || rebuild == null) {
      return column.cells;
    }
    final previewLayer = timelineDragPreviewLayerFor(preview, layerId);
    if (previewLayer == null) {
      return column.cells;
    }
    return rebuild(previewLayer);
  }

  /// The rows of a half starting at [rowsTop] that [_painter._cull] can reach.
  ///
  /// This is OpenToonz's move — it turns the damage rect into a CELL
  /// INDEX RANGE (`xyRectToRange` → `r0..r1`) and iterates only those,
  /// with no offscreen cache for the grid at all. That is the shape of
  /// the finding that sent us here: a sheet grid is not expensive, and
  /// ours only looked expensive because it was drawing a whole B4
  /// document — ~334 lines and ~111 paragraphs — to fill a dock a few
  /// hundred pixels tall.
  ///
  /// A row of slack each side, because a row's ink is allowed to reach a
  /// little past its own band (text baselines, the SE dotted guide).
  (int, int) _rowRange(double rowsTop, int rowCount) {
    final cull = _painter._cull;
    if (cull == null) {
      return (0, rowCount);
    }
    const height = TimesheetDocumentLayout.rowHeight;
    final first = ((cull.top - rowsTop) / height).floor() - 1;
    final last = ((cull.bottom - rowsTop) / height).ceil() + 1;
    return (first.clamp(0, rowCount), last.clamp(0, rowCount));
  }

  /// [firstRow], walked back to the start of the span that reaches it.
  ///
  /// 🗣️F-78 (유저 2026-09-11): 「타임시트의 se행. se블록의 이름란이 뷰포트에서
  /// 안보이면 대사 텍스트가 사라짐」. A span's START cell writes down the
  /// whole span — an SE entry its name and dialogue, a hold chain its word, a
  /// repeat chain its word — so culling the start row dropped ink the clip
  /// would have kept: the one thing [_rowRange] may not do. The rows a word
  /// runs down read as EMPTY, so the walk steps over empty rows up to the
  /// first cell that says where its span is.
  int _spanStartRow(List<TimesheetCell> cells, int startFrame, int firstRow) {
    for (var row = firstRow; row >= 0; row -= 1) {
      final frame = startFrame + row;
      if (frame >= cells.length) {
        return firstRow;
      }
      final cell = cells[frame];
      final length = cell.spanLength;
      if (length == null) {
        if (cell.kind == TimesheetCellKind.empty) {
          continue;
        }
        return firstRow;
      }
      final start = row - (cell.spanOffset ?? 0);
      return start + length > firstRow ? math.max(0, start) : firstRow;
    }
    return firstRow;
  }

  void paintHalf(
    Canvas canvas, {
    required int pageIndex,
    required int half,
    required int startFrame,
    required int rowCount,
    required bool drawTexts,
  }) {
    final left = _painter.layout.halfLeft(pageIndex, half);
    final rowsTop = _painter.layout.halfRowsTop(pageIndex);
    final rowsBottom = rowsTop + rowCount * TimesheetDocumentLayout.rowHeight;
    final right = left + _painter.layout.halfWidth;
    final columnsTop = rowsTop - _painter.layout.columnsHeaderHeight;
    final lettersTop = rowsTop - TimesheetDocumentLayout.letterRowHeight;

    final lightPaint = Paint()
      ..color = TimesheetDocumentPainter._gridLight
      ..strokeWidth = 0.6;
    final mediumPaint = Paint()
      ..color = TimesheetDocumentPainter._gridMedium
      ..strokeWidth = 1.0;
    final boldPaint = Paint()
      ..color = TimesheetDocumentPainter._gridBold
      ..strokeWidth = 1.6;
    final seRanges = _seColumnRanges(left);
    final (firstRow, lastRow) = _rowRange(rowsTop, rowCount);
    final sheet = _HalfFrame(
      left: left,
      right: right,
      rowsTop: rowsTop,
      rowsBottom: rowsBottom,
      columnsTop: columnsTop,
      lettersTop: lettersTop,
      startFrame: startFrame,
      rowCount: rowCount,
      firstRow: firstRow,
      lastRow: lastRow,
      numbersRight: left - 4,
      lightPaint: lightPaint,
      mediumPaint: mediumPaint,
      boldPaint: boldPaint,
      seRanges: seRanges,
    );

    // Group titles + letter row (printed form).
    _paintColumnTitles(canvas, sheet, drawTexts: drawTexts);
    if (_painter._drawForm) {
      canvas.drawLine(
        Offset(left, columnsTop),
        Offset(right, columnsTop),
        mediumPaint,
      );
      canvas.drawLine(
        Offset(left, lettersTop),
        Offset(right, lettersTop),
        lightPaint,
      );
    }

    // Row lines: light per frame, medium every 6 frames, bold on second
    // boundaries. SE columns print NO interior frame rules (R6-② — the
    // real Toei sheet leaves the S strip clean; its vertical borders and
    // the table's outer edges stay), so interior lines draw in segments
    // skipping the SE ranges.
    if (!_painter._drawForm) {
      // Content-only: skip the grid entirely and print the cells.
      _paintHalfCells(
        canvas,
        left: left,
        rowsTop: rowsTop,
        startFrame: startFrame,
        rowCount: rowCount,
        drawTexts: drawTexts,
      );
      return;
    }
    _paintRowLines(canvas, sheet);

    // Vertical lines: half edges + column separators (bold at section
    // changes). The number gutter draws NO lines — bare numbers on paper.
    canvas.drawLine(
      Offset(left, columnsTop),
      Offset(left, rowsBottom),
      boldPaint,
    );
    canvas.drawLine(
      Offset(right, columnsTop),
      Offset(right, rowsBottom),
      boldPaint,
    );
    for (
      var column = 1;
      column < _painter.document.columns.length;
      column += 1
    ) {
      final x = left + _painter.layout.columnLeftInHalf(column);
      final sectionEdge =
          _painter.document.columns[column].kind !=
          _painter.document.columns[column - 1].kind;
      canvas.drawLine(
        Offset(x, sectionEdge ? columnsTop : lettersTop),
        Offset(x, rowsBottom),
        sectionEdge ? boldPaint : lightPaint,
      );
    }

    // Gutter frame numbers on even frames, bare on the paper left of the
    // half — page-local on paper, global in the continuous strip. On each
    // second's LAST frame row (24, 48, …) the second index prints BOLD in
    // place of the frame number — the paper convention (A-1 form).
    _paintRowNumbers(canvas, sheet, drawTexts: drawTexts);

    if (_painter._drawContent) {
      _paintHalfCells(
        canvas,
        left: left,
        rowsTop: rowsTop,
        startFrame: startFrame,
        rowCount: rowCount,
        drawTexts: drawTexts,
      );
    }
  }

  /// The second numbers: one per [fps] rows, right-aligned in the margin,
  /// bold; the other rows print their frame number small.
  void _paintRowNumbers(
    Canvas canvas,
    _HalfFrame sheet, {
    required bool drawTexts,
  }) {
    if (drawTexts) {
      for (var row = sheet.firstRow; row < sheet.lastRow; row += 1) {
        final frame = sheet.startFrame + row;
        final printed = _painter.layout.continuous
            ? frame + 1
            : frame % _painter.document.pageFrameCount + 1;
        final rowTop = sheet.rowsTop + row * TimesheetDocumentLayout.rowHeight;
        if (printed % _painter.document.fps == 0) {
          _painter._text(
            canvas,
            '${printed ~/ _painter.document.fps}',
            Offset(sheet.numbersRight, rowTop + 3),
            fontSize: 10,
            bold: true,
            color: TimesheetDocumentPainter._gridBold,
            rightAlignedAtX: true,
          );
          continue;
        }
        if (printed.isOdd) {
          continue;
        }
        _painter._text(
          canvas,
          '$printed',
          Offset(sheet.numbersRight, rowTop + 4),
          fontSize: 8,
          color: TimesheetDocumentPainter._gridMedium,
          rightAlignedAtX: true,
        );
      }
    }
  }

  /// The row rules: bold on the second, medium on the half-second, light
  /// elsewhere — and skipping the SE columns, whose rows are their own.
  void _paintRowLines(Canvas canvas, _HalfFrame sheet) {
    for (var row = sheet.firstRow; row <= sheet.lastRow; row += 1) {
      final frame = sheet.startFrame + row;
      final y = sheet.rowsTop + row * TimesheetDocumentLayout.rowHeight;
      final Paint paint;
      if (frame % _painter.document.fps == 0 || row == sheet.rowCount) {
        paint = sheet.boldPaint;
      } else if (frame % 6 == 0) {
        paint = sheet.mediumPaint;
      } else {
        paint = sheet.lightPaint;
      }
      if (row == 0 || row == sheet.rowCount || sheet.seRanges.isEmpty) {
        // The table's outer edges close full width.
        canvas.drawLine(Offset(sheet.left, y), Offset(sheet.right, y), paint);
        continue;
      }
      var segmentStart = sheet.left;
      for (final (seLeft, seRight) in sheet.seRanges) {
        if (seLeft > segmentStart) {
          canvas.drawLine(Offset(segmentStart, y), Offset(seLeft, y), paint);
        }
        segmentStart = seRight;
      }
      if (segmentStart < sheet.right) {
        canvas.drawLine(Offset(segmentStart, y), Offset(sheet.right, y), paint);
      }
    }
  }

  /// The SE columns as left/right ranges, adjacent ones merged.
  List<(double, double)> _seColumnRanges(double left) {
    final seRanges = <(double, double)>[];
    for (
      var column = 0;
      column < _painter.document.columns.length;
      column += 1
    ) {
      if (_painter.document.columns[column].kind != TimesheetColumnKind.se) {
        continue;
      }
      final seLeft = left + _painter.layout.columnLeftInHalf(column);
      final seRight =
          seLeft + _painter.layout.columnWidthFor(TimesheetColumnKind.se);
      if (seRanges.isNotEmpty && seRanges.last.$2 >= seLeft) {
        seRanges[seRanges.length - 1] = (seRanges.last.$1, seRight);
      } else {
        seRanges.add((seLeft, seRight));
      }
    }
    return seRanges;
  }

  /// The column titles on the letter row, when the form and its texts draw.
  void _paintColumnTitles(
    Canvas canvas,
    _HalfFrame sheet, {
    required bool drawTexts,
  }) {
    if (drawTexts && _painter._drawForm) {
      _painter._bands.paintGroupTitles(canvas, sheet.left, sheet.columnsTop);
      for (
        var column = 0;
        column < _painter.document.columns.length;
        column += 1
      ) {
        // Unbacked slots print nothing — no placeholder letters.
        if (_painter.document.columns[column].label.isEmpty) {
          continue;
        }
        final columnLeft =
            sheet.left + _painter.layout.columnLeftInHalf(column);
        final columnWidth = _painter.layout.columnWidthFor(
          _painter.document.columns[column].kind,
        );
        _painter._text(
          canvas,
          _painter.document.columns[column].label,
          Offset(columnLeft + columnWidth / 2, sheet.lettersTop + 2),
          fontSize: 9,
          color: TimesheetDocumentPainter._ink,
          centeredAtX: true,
          maxWidth: columnWidth - 2,
        );
      }
    }
  }

  /// The CONTENT stratum of one half (UI-R10 #9): every column's cell
  /// texts/marks/lines, with in-flight drag previews substituted per
  /// column — this is what re-prints per drag step while the form
  /// underneath never re-records.
  void _paintHalfCells(
    Canvas canvas, {
    required double left,
    required double rowsTop,
    required int startFrame,
    required int rowCount,
    required bool drawTexts,
  }) {
    for (
      var column = 0;
      column < _painter.document.columns.length;
      column += 1
    ) {
      final spec = _painter.document.columns[column];
      final cells = displayCellsFor(spec);
      final columnLeft = left + _painter.layout.columnLeftInHalf(column);
      final columnWidth = _painter.layout.columnWidthFor(spec.kind);
      final centerX = columnLeft + columnWidth / 2;
      final (firstRow, lastRow) = _rowRange(rowsTop, rowCount);
      for (
        var row = _spanStartRow(cells, startFrame, firstRow);
        row < lastRow;
        row += 1
      ) {
        final frame = startFrame + row;
        if (frame >= cells.length) {
          break;
        }
        final cell = cells[frame];
        final seColumn = spec.kind == TimesheetColumnKind.se;
        final cellTop = rowsTop + row * TimesheetDocumentLayout.rowHeight;
        final cellBottom = cellTop + TimesheetDocumentLayout.rowHeight;
        final cellCenterY = cellTop + TimesheetDocumentLayout.rowHeight / 2;
        if (cell.kind == TimesheetCellKind.empty) {
          // SE columns mark their empty stretches the print-sheet way: a
          // dotted center guide, washed light gray while the toggle is on.
          if (seColumn && frame < _painter.document.playbackFrameCount) {
            _painter._se.paintSeEmptyRow(
              canvas,
              columnLeft: columnLeft,
              columnWidth: columnWidth,
              centerX: centerX,
              cellTop: cellTop,
            );
          }
          continue;
        }
        final slot = _CellSlot(
          cell: cell,
          row: row,
          columnLeft: columnLeft,
          columnWidth: columnWidth,
          centerX: centerX,
          cellTop: cellTop,
          cellBottom: cellBottom,
          cellCenterY: cellCenterY,
          seColumn: seColumn,
        );
        _paintCellOfKind(
          canvas,
          slot,
          drawTexts: drawTexts,
          rowCount: rowCount,
        );
      }
    }
  }

  /// A drawing cell's label — or, in an SE column, the SE entry start.
  void _paintDrawingCell(
    Canvas canvas,
    _CellSlot slot, {
    required bool drawTexts,
    required int rowCount,
  }) {
    if (drawTexts) {
      if (slot.seColumn) {
        _painter._se.paintSeEntryStart(
          canvas,
          cell: slot.cell,
          row: slot.row,
          rowCount: rowCount,
          columnLeft: slot.columnLeft,
          columnWidth: slot.columnWidth,
          centerX: slot.centerX,
          cellTop: slot.cellTop,
        );
      } else {
        _painter._text(
          canvas,
          slot.cell.label ?? '',
          Offset(slot.centerX, slot.cellTop + 3),
          fontSize: 10,
          color: TimesheetDocumentPainter._ink,
          centeredAtX: true,
        );
      }
    }
  }

  /// A held cell's bar, by column: the SE red bar or the action hold bar.
  void _paintHeldCell(Canvas canvas, _CellSlot slot) {
    if (slot.seColumn) {
      // Toei SE notation: no hold line down the dialogue; the
      // block's END closes with the full-width red bar instead.
      if ((slot.cell.spanOffset ?? 0) == (slot.cell.spanLength ?? 1) - 1) {
        _painter._se.paintSeRedBar(
          canvas,
          columnLeft: slot.columnLeft,
          columnWidth: slot.columnWidth,
          y: slot.cellBottom - 1,
        );
      }
      return;
    }
    // ACTION hold bar: off by default; with a threshold N it runs
    // from the (N+1)th comma of N+ holds only (industry N=3).
    final threshold = _painter.document.exposureBarThreshold;
    if (threshold != null && (slot.cell.spanOffset ?? 0) >= threshold) {
      canvas.drawLine(
        Offset(slot.centerX, slot.cellTop),
        Offset(slot.centerX, slot.cellBottom),
        Paint()
          ..color = TimesheetDocumentPainter._ink
          ..strokeWidth = 1.0,
      );
    }
  }

  /// A repeat chain's first cell: the cel it restarts on, then the
  /// notation repeat word down the rest of the chain.
  void _paintRepeatStart(
    Canvas canvas,
    _CellSlot slot, {
    required bool drawTexts,
  }) {
    // A repeat ghost chain prints the sheet CONVENTION (UI-R13
    // #4): its first slot.row writes the cel it restarts on, and the
    // NOTATION-language repeat word runs VERTICALLY from the
    // next slot.row (UI-R11 #14) — the expanded cel numbers live in
    // the timeline for exporters, never here. No guide line.
    if (drawTexts) {
      _painter._text(
        canvas,
        slot.cell.label ?? '',
        Offset(slot.centerX, slot.cellTop + 3),
        fontSize: 10,
        color: TimesheetDocumentPainter._ink,
        centeredAtX: true,
      );
      final wordRows = (slot.cell.spanLength ?? 1) - 1;
      if (wordRows > 0) {
        _painter._paintVerticalWord(
          canvas,
          _painter.notation.repeat,
          centerX: slot.centerX,
          top: slot.cellTop + TimesheetDocumentLayout.rowHeight,
          rows: wordRows,
          columnWidth: slot.columnWidth,
        );
      }
    }
  }

  /// One non-empty cell, by kind: a drawing's label (or the SE entry
  /// start), a hold's exposure bar past the threshold (or the SE red bar
  /// at its end), the camera span line, a mark, a repeat's label and word,
  /// a hold's word, an empty run's cross, a camera key, an instruction row.
  void _paintCellOfKind(
    Canvas canvas,
    _CellSlot slot, {
    required bool drawTexts,
    required int rowCount,
  }) {
    switch (slot.cell.kind) {
      case TimesheetCellKind.drawing:
        _paintDrawingCell(
          canvas,
          slot,
          drawTexts: drawTexts,
          rowCount: rowCount,
        );
      case TimesheetCellKind.held:
        _paintHeldCell(canvas, slot);
      case TimesheetCellKind.cameraSpan:
        canvas.drawLine(
          Offset(slot.centerX, slot.cellTop),
          Offset(slot.centerX, slot.cellBottom),
          Paint()
            ..color = TimesheetDocumentPainter._ink
            ..strokeWidth = 1.6,
        );
      case TimesheetCellKind.mark:
        // Block-owned inbetween dot: FILLED ● (same glyph as the
        // timeline cells), not the legacy hollow ○.
        canvas.drawCircle(
          Offset(slot.centerX, slot.cellCenterY),
          2.8,
          Paint()..color = TimesheetDocumentPainter._ink,
        );
      case TimesheetCellKind.repeatStart:
        _paintRepeatStart(canvas, slot, drawTexts: drawTexts);
      case TimesheetCellKind.repeatSpan:
        break; // The word above covers the chain (UI-R11 #14).
      case TimesheetCellKind.holdStart:
        // One cel held from slot.row 1: the rear hold chain prints the
        // notation hold word (止め) vertically (UI-R11 #15).
        if (drawTexts) {
          _painter._paintVerticalWord(
            canvas,
            _painter.notation.hold,
            centerX: slot.centerX,
            top: slot.cellTop,
            rows: slot.cell.spanLength ?? 1,
            columnWidth: slot.columnWidth,
          );
        }
      case TimesheetCellKind.emptyRunStart:
        if (drawTexts) {
          _painter._text(
            canvas,
            '×',
            Offset(slot.centerX, slot.cellTop + 2),
            fontSize: 11,
            color: TimesheetDocumentPainter._gridMedium,
            centeredAtX: true,
          );
        }
      case TimesheetCellKind.cameraKey:
        canvas.drawCircle(
          Offset(slot.centerX, slot.cellCenterY),
          3.4,
          Paint()..color = TimesheetDocumentPainter._ink,
        );
      case TimesheetCellKind.instructionStart:
      case TimesheetCellKind.instructionSpan:
      case TimesheetCellKind.instructionEnd:
        // One shared per-slot.row renderer — the printed sheet mirrors the
        // X-sheet column verbatim: the mark owns the whole slot.cell width,
        // A/B center in their endpoint cells (frame-name style) and
        // the writing centers on the span's middle slot.row.
        _painter._instructions.paintInstructionRow(
          canvas,
          cell: slot.cell,
          columnLeft: slot.columnLeft,
          columnWidth: slot.columnWidth,
          centerX: slot.centerX,
          cellTop: slot.cellTop,
          drawTexts: drawTexts,
        );
      case TimesheetCellKind.empty:
        break;
    }
  }
}

/// One cell's place on the half page: the cell itself, its row, and the
/// geometry the column and row give it. The per-kind painters read it
/// instead of nine captured locals.
class _CellSlot {
  const _CellSlot({
    required this.cell,
    required this.row,
    required this.columnLeft,
    required this.columnWidth,
    required this.centerX,
    required this.cellTop,
    required this.cellBottom,
    required this.cellCenterY,
    required this.seColumn,
  });

  final TimesheetCell cell;
  final int row;
  final double columnLeft;
  final double columnWidth;
  final double centerX;
  final double cellTop;
  final double cellBottom;
  final double cellCenterY;
  final bool seColumn;
}

/// One half page's frame: where it sits, which rows are visible, the three
/// grid paints, and the SE column ranges the row lines skip. The steps of
/// [_TimesheetCellsPass.paintHalf] read it instead of a dozen parameters.
class _HalfFrame {
  const _HalfFrame({
    required this.left,
    required this.right,
    required this.rowsTop,
    required this.rowsBottom,
    required this.columnsTop,
    required this.lettersTop,
    required this.startFrame,
    required this.rowCount,
    required this.firstRow,
    required this.lastRow,
    required this.numbersRight,
    required this.lightPaint,
    required this.mediumPaint,
    required this.boldPaint,
    required this.seRanges,
  });

  final double left;
  final double right;
  final double rowsTop;
  final double rowsBottom;
  final double columnsTop;
  final double lettersTop;
  final int startFrame;
  final int rowCount;
  final int firstRow;
  final int lastRow;
  final double numbersRight;
  final Paint lightPaint;
  final Paint mediumPaint;
  final Paint boldPaint;
  final List<(double, double)> seRanges;
}
