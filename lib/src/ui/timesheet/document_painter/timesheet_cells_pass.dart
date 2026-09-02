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

    // Group titles + letter row (printed form).
    if (drawTexts && _painter._drawForm) {
      _painter._bands.paintGroupTitles(canvas, left, columnsTop);
      for (
        var column = 0;
        column < _painter.document.columns.length;
        column += 1
      ) {
        // Unbacked slots print nothing — no placeholder letters.
        if (_painter.document.columns[column].label.isEmpty) {
          continue;
        }
        final columnLeft = left + _painter.layout.columnLeftInHalf(column);
        final columnWidth = _painter.layout.columnWidthFor(
          _painter.document.columns[column].kind,
        );
        _painter._text(
          canvas,
          _painter.document.columns[column].label,
          Offset(columnLeft + columnWidth / 2, lettersTop + 2),
          fontSize: 9,
          color: TimesheetDocumentPainter._ink,
          centeredAtX: true,
          maxWidth: columnWidth - 2,
        );
      }
    }
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
    final numbersRight = left - 4;
    final (firstRow, lastRow) = _rowRange(rowsTop, rowCount);
    for (var row = firstRow; row <= lastRow; row += 1) {
      final frame = startFrame + row;
      final y = rowsTop + row * TimesheetDocumentLayout.rowHeight;
      final Paint paint;
      if (frame % _painter.document.fps == 0 || row == rowCount) {
        paint = boldPaint;
      } else if (frame % 6 == 0) {
        paint = mediumPaint;
      } else {
        paint = lightPaint;
      }
      if (row == 0 || row == rowCount || seRanges.isEmpty) {
        // The table's outer edges close full width.
        canvas.drawLine(Offset(left, y), Offset(right, y), paint);
        continue;
      }
      var segmentStart = left;
      for (final (seLeft, seRight) in seRanges) {
        if (seLeft > segmentStart) {
          canvas.drawLine(Offset(segmentStart, y), Offset(seLeft, y), paint);
        }
        segmentStart = seRight;
      }
      if (segmentStart < right) {
        canvas.drawLine(Offset(segmentStart, y), Offset(right, y), paint);
      }
    }

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
    if (drawTexts) {
      for (var row = firstRow; row < lastRow; row += 1) {
        final frame = startFrame + row;
        final printed = _painter.layout.continuous
            ? frame + 1
            : frame % _painter.document.pageFrameCount + 1;
        final rowTop = rowsTop + row * TimesheetDocumentLayout.rowHeight;
        if (printed % _painter.document.fps == 0) {
          _painter._text(
            canvas,
            '${printed ~/ _painter.document.fps}',
            Offset(numbersRight, rowTop + 3),
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
          Offset(numbersRight, rowTop + 4),
          fontSize: 8,
          color: TimesheetDocumentPainter._gridMedium,
          rightAlignedAtX: true,
        );
      }
    }

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
      for (var row = firstRow; row < lastRow; row += 1) {
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
        switch (cell.kind) {
          case TimesheetCellKind.drawing:
            if (drawTexts) {
              if (seColumn) {
                _painter._se.paintSeEntryStart(
                  canvas,
                  cell: cell,
                  row: row,
                  rowCount: rowCount,
                  columnLeft: columnLeft,
                  columnWidth: columnWidth,
                  centerX: centerX,
                  cellTop: cellTop,
                );
              } else {
                _painter._text(
                  canvas,
                  cell.label ?? '',
                  Offset(centerX, cellTop + 3),
                  fontSize: 10,
                  color: TimesheetDocumentPainter._ink,
                  centeredAtX: true,
                );
              }
            }
          case TimesheetCellKind.held:
            if (seColumn) {
              // Toei SE notation: no hold line down the dialogue; the
              // block's END closes with the full-width red bar instead.
              if ((cell.spanOffset ?? 0) == (cell.spanLength ?? 1) - 1) {
                _painter._se.paintSeRedBar(
                  canvas,
                  columnLeft: columnLeft,
                  columnWidth: columnWidth,
                  y: cellBottom - 1,
                );
              }
              break;
            }
            // ACTION hold bar: off by default; with a threshold N it runs
            // from the (N+1)th comma of N+ holds only (industry N=3).
            final threshold = _painter.document.exposureBarThreshold;
            if (threshold != null && (cell.spanOffset ?? 0) >= threshold) {
              canvas.drawLine(
                Offset(centerX, cellTop),
                Offset(centerX, cellBottom),
                Paint()
                  ..color = TimesheetDocumentPainter._ink
                  ..strokeWidth = 1.0,
              );
            }
          case TimesheetCellKind.cameraSpan:
            canvas.drawLine(
              Offset(centerX, cellTop),
              Offset(centerX, cellBottom),
              Paint()
                ..color = TimesheetDocumentPainter._ink
                ..strokeWidth = 1.6,
            );
          case TimesheetCellKind.mark:
            // Block-owned inbetween dot: FILLED ● (same glyph as the
            // timeline cells), not the legacy hollow ○.
            canvas.drawCircle(
              Offset(centerX, cellCenterY),
              2.8,
              Paint()..color = TimesheetDocumentPainter._ink,
            );
          case TimesheetCellKind.repeatStart:
            // A repeat ghost chain prints the sheet CONVENTION (UI-R13
            // #4): its first row writes the cel it restarts on, and the
            // NOTATION-language repeat word runs VERTICALLY from the
            // next row (UI-R11 #14) — the expanded cel numbers live in
            // the timeline for exporters, never here. No guide line.
            if (drawTexts) {
              _painter._text(
                canvas,
                cell.label ?? '',
                Offset(centerX, cellTop + 3),
                fontSize: 10,
                color: TimesheetDocumentPainter._ink,
                centeredAtX: true,
              );
              final wordRows = (cell.spanLength ?? 1) - 1;
              if (wordRows > 0) {
                _painter._paintVerticalWord(
                  canvas,
                  _painter.notation.repeat,
                  centerX: centerX,
                  top: cellTop + TimesheetDocumentLayout.rowHeight,
                  rows: wordRows,
                  columnWidth: columnWidth,
                );
              }
            }
          case TimesheetCellKind.repeatSpan:
            break; // The word above covers the chain (UI-R11 #14).
          case TimesheetCellKind.holdStart:
            // One cel held from row 1: the rear hold chain prints the
            // notation hold word (止め) vertically (UI-R11 #15).
            if (drawTexts) {
              _painter._paintVerticalWord(
                canvas,
                _painter.notation.hold,
                centerX: centerX,
                top: cellTop,
                rows: cell.spanLength ?? 1,
                columnWidth: columnWidth,
              );
            }
          case TimesheetCellKind.emptyRunStart:
            if (drawTexts) {
              _painter._text(
                canvas,
                '×',
                Offset(centerX, cellTop + 2),
                fontSize: 11,
                color: TimesheetDocumentPainter._gridMedium,
                centeredAtX: true,
              );
            }
          case TimesheetCellKind.cameraKey:
            canvas.drawCircle(
              Offset(centerX, cellCenterY),
              3.4,
              Paint()..color = TimesheetDocumentPainter._ink,
            );
          case TimesheetCellKind.instructionStart:
          case TimesheetCellKind.instructionSpan:
          case TimesheetCellKind.instructionEnd:
            // One shared per-row renderer — the printed sheet mirrors the
            // X-sheet column verbatim: the mark owns the whole cell width,
            // A/B center in their endpoint cells (frame-name style) and
            // the writing centers on the span's middle row.
            _painter._instructions.paintInstructionRow(
              canvas,
              cell: cell,
              columnLeft: columnLeft,
              columnWidth: columnWidth,
              centerX: centerX,
              cellTop: cellTop,
              drawTexts: drawTexts,
            );
          case TimesheetCellKind.empty:
            break;
        }
      }
    }
  }
}
