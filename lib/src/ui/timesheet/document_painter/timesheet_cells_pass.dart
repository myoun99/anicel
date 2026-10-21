part of '../timesheet_document_painter.dart';

/// What the gutter prints beside the row of [frame] (from 0): the frame's
/// number — on an even frame, and on the frame that closes a second — and,
/// on that row, the second it closes. The cut's own count, sheet after
/// sheet, its seconds included.
///
/// 🗣️유저 2026-10-09 (F-252): 「페이지별로 프레임번호 초기화한거
/// 되돌려줘」 — ↩️each sheet counted its frames from 1 (the paper-faithful
/// form's choice, 07-07), and the continuous view deleted on 10-08 was the
/// one place the cut's count showed — and 「초수도 반영해서 7부터
/// 시작한다던가」: a 24fps cut's second sheet opens its seconds at 7. And
/// 「24라는 숫자 제대로 오게하고 그 왼쪽에 초 텍스트 넣어줘. 그리고 위치는
/// 24 바로 옆이아니라 1초마다 진한 가로선있잖아. 그 가로선 옆에 오도록」 —
/// ↩️the second's index printed in place of its last frame's number; it
/// stands left of the numbers now, on the second's bold rule.
///
/// The index is the ruler's mark ([timelineRulerSecondsLabel]): the rule
/// under a row is the next frame's head, where the seconds before it have
/// gone by — the boundary the ruler and the x-sheet write on.
({int? number, String? second}) timesheetGutterMarks(
  int frame, {
  required int fps,
}) {
  final printed = frame + 1;
  final second = timelineRulerSecondsLabel(
    frameIndex: frame + 1,
    framesPerSecond: fps,
  );
  return (
    number: printed.isEven || second.isNotEmpty ? printed : null,
    second: second.isEmpty ? null : second,
  );
}

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
  /// substituted for its layer ([timesheetColumnCellsShowing]).
  List<TimesheetCell> displayCellsFor(TimesheetColumn column) =>
      timesheetColumnCellsShowing(column, _painter.dragPreview?.value);

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
  }) {
    final left = _painter.layout.halfLeft(pageIndex, half);
    final rowsTop = _painter.layout.halfRowsTop(pageIndex);
    final rowsBottom = rowsTop + rowCount * TimesheetDocumentLayout.rowHeight;
    final right = left + _painter.layout.halfWidth;
    final columnsTop = _painter.layout.gridTop(pageIndex);
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
      // Clear of the numbers' gutter: in the paper's margin beside the
      // first half, in the gap between halves beside the second.
      secondsRight: left - TimesheetDocumentLayout.frameNumberGutterWidth - 2,
      lightPaint: lightPaint,
      mediumPaint: mediumPaint,
      boldPaint: boldPaint,
      seRanges: seRanges,
    );

    // Group titles + letter row (printed form).
    _paintColumnTitles(canvas, sheet);
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
      // No form: no grid — and the cells only where the values are printed,
      // as the form's own branch below asks.
      //
      // 🚨F-269 (유저 2026-10-03): 「off해서 껐는데 글자가 남아있고, 글자가
      // 연하게 됬을뿐」 · 「다른탭 갔다 돌아오면 정상적으로 사라져있음」. This
      // branch was written when a sheet had two strata, form and content, so
      // 「not the form」 meant the values. The ink stratum (09-26) is not the
      // form either, and printed every cell a second time — into a bake that
      // re-records for the ink alone, so a value turned off stayed in it
      // until the panel was built again. The export printed them a third
      // time, once a stratum.
      if (_painter._drawContent) {
        _paintHalfCells(
          canvas,
          left: left,
          rowsTop: rowsTop,
          startFrame: startFrame,
          rowCount: rowCount,
        );
      }
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

    // The gutter, bare on the paper left of the half ([timesheetGutterMarks]).
    _paintRowNumbers(canvas, sheet);

    if (_painter._drawContent) {
      _paintHalfCells(
        canvas,
        left: left,
        rowsTop: rowsTop,
        startFrame: startFrame,
        rowCount: rowCount,
      );
    }
  }

  /// The gutter's marks ([timesheetGutterMarks]): a frame's number small,
  /// right-aligned beside its row, and a second's index bold, further
  /// left, on the bold rule that closes that second.
  void _paintRowNumbers(Canvas canvas, _HalfFrame sheet) {
    for (var row = sheet.firstRow; row < sheet.lastRow; row += 1) {
      final marks = timesheetGutterMarks(
        sheet.startFrame + row,
        fps: _painter.document.fps,
      );
      final rowTop = sheet.rowsTop + row * TimesheetDocumentLayout.rowHeight;
      if (marks.number case final number?) {
        _painter._text(
          canvas,
          '$number',
          Offset(sheet.numbersRight, rowTop + 4),
          fontSize: 8,
          color: TimesheetDocumentPainter._gridMedium,
          rightAlignedAtX: true,
        );
      }
      if (marks.second case final second?) {
        _painter._text(
          canvas,
          second,
          Offset(
            sheet.secondsRight,
            rowTop + TimesheetDocumentLayout.rowHeight,
          ),
          fontSize: 10,
          bold: true,
          color: TimesheetDocumentPainter._gridBold,
          rightAlignedAtX: true,
          centeredAtY: true,
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

  /// The column titles on the letter row, when the form draws.
  void _paintColumnTitles(Canvas canvas, _HalfFrame sheet) {
    if (_painter._drawForm) {
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
      final seColumn = spec.kind == TimesheetColumnKind.se;
      // 🗣️F-358 (유저 2026-10-17): 「컷 엔드라인(OL여백이든 뭐든 총합적인
      // 엔드라인) 넘어가는건 안보이게하고」 — an SE column's rows end at the
      // line the cut is DRAWN to, so a sound running past it prints no
      // words there, and no closing bar where it does not close.
      final rowsShown = seColumn
          ? (_painter.liveDrawnFrameCount - startFrame).clamp(0, rowCount)
          : rowCount;
      // How far before row 0 the block there began: the spill-in's head is
      // an earlier cut's (F-358).
      int leadOf(int blockStart) =>
          blockStart == 0 ? spec.spillInLeadFrames ?? 0 : 0;
      final (firstRow, lastRow) = _rowRange(rowsTop, rowsShown);
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
          stretchFrom: _painter.document.stretchLineFrom(spec.kind),
          lead: leadOf(frame),
        );
        _paintCellOfKind(
          canvas,
          slot,
          rowCount: rowsShown,
        );
        // F-165: an entry that began in an earlier half writes the rest of
        // its dialogue here, from this half's top — its share of the words
        // laid over the whole span ([_TimesheetSePass.paintSeDialogueShare]).
        final offset = cell.spanOffset ?? 0;
        if (seColumn && row == 0 && offset > 0) {
          _painter._se.paintSeDialogueShare(
            canvas,
            start: cells[frame - offset],
            spanOffset: offset,
            lead: leadOf(frame - offset),
            row: row,
            rowCount: rowsShown,
            centerX: centerX,
            cellTop: cellTop,
          );
        }
      }
    }
  }

  /// A drawing cell's label — or, in an SE column, the SE entry start.
  void _paintDrawingCell(
    Canvas canvas,
    _CellSlot slot, {
    required int rowCount,
  }) {
    if (slot.seColumn) {
      _painter._se.paintSeEntryStart(
        canvas,
        cell: slot.cell,
        lead: slot.lead,
        row: slot.row,
        rowCount: rowCount,
        columnLeft: slot.columnLeft,
        columnWidth: slot.columnWidth,
        centerX: slot.centerX,
        cellTop: slot.cellTop,
      );
    } else {
      _paintHead(canvas, slot);
    }
  }

  /// What a drawing's head row writes: its cel number, or — with none —
  /// its mark, the dot a block's in-between rows wear (one mark, 유저
  /// 2026-09-24: 「타임시트패널에서 동그라미는 작은걸로 통일」).
  void _paintHead(Canvas canvas, _CellSlot slot) {
    final mark = slot.cell.mark;
    if (mark != null) {
      _paintMark(canvas, slot, mark);
      return;
    }
    _painter._text(
      canvas,
      slot.cell.label ?? '',
      Offset(slot.centerX, slot.cellTop + 3),
      fontSize: 10,
      color: TimesheetDocumentPainter._ink,
      centeredAtX: true,
    );
  }

  /// An in-between mark, at the centre of its row.
  void _paintMark(Canvas canvas, _CellSlot slot, InbetweenMark mark) =>
      paintInbetweenMark(canvas, mark, (
        center: Offset(slot.centerX, slot.cellCenterY),
        size: const Size.square(timesheetInbetweenMarkRadius * 2),
      ), TimesheetDocumentPainter._ink);

  /// A held cell's bar, by column: the SE red bar or the block's stretch line.
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
    slot.paintStretchLine(canvas);
  }

  /// A repeat chain's first cell: the cel it restarts on, then the
  /// notation repeat word down the rest of the chain.
  void _paintRepeatStart(Canvas canvas, _CellSlot slot) {
    // A repeat ghost chain prints the sheet CONVENTION (UI-R13
    // #4): its first slot.row writes the cel it restarts on, and the
    // NOTATION-language repeat word runs VERTICALLY from the
    // next slot.row (UI-R11 #14) — the expanded cel numbers live in
    // the timeline for exporters, never here. No guide line.
    _paintHead(canvas, slot);
    final wordRows = (slot.cell.spanLength ?? 1) - 1;
    if (wordRows > 0) {
      _painter._paintVerticalWord(
        canvas,
        _painter.words.repeat,
        centerX: slot.centerX,
        top: slot.cellTop + TimesheetDocumentLayout.rowHeight,
        rows: wordRows,
        columnWidth: slot.columnWidth,
      );
    }
  }

  /// One non-empty cell, by kind: a drawing's label (or the SE entry
  /// start), a hold's exposure bar past the threshold (or the SE red bar
  /// at its end), the camera span line, a mark, a repeat's label and word,
  /// a hold's word, an empty run's cross, a camera key, an instruction row.
  void _paintCellOfKind(
    Canvas canvas,
    _CellSlot slot, {
    required int rowCount,
  }) {
    switch (slot.cell.kind) {
      case TimesheetCellKind.drawing:
        _paintDrawingCell(
          canvas,
          slot,
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
        _painter._instructions.paintSpanNameOn(
          canvas,
          slot,
          rows: _gridOf(slot, rowCount: rowCount),
        );
      case TimesheetCellKind.mark:
        // Block-owned inbetween dot: FILLED ● (same glyph as the
        // timeline cells), not the legacy hollow ○.
        if (slot.cell.mark case final mark?) {
          _paintMark(canvas, slot, mark);
        }
      case TimesheetCellKind.repeatStart:
        _paintRepeatStart(canvas, slot);
      case TimesheetCellKind.repeatSpan:
        break; // The word above covers the chain (UI-R11 #14).
      case TimesheetCellKind.holdStart:
        // One cel held from slot.row 1: the rear hold chain prints the
        // notation hold word (止め) vertically (UI-R11 #15).
        _painter._paintVerticalWord(
          canvas,
          _painter.words.hold,
          centerX: slot.centerX,
          top: slot.cellTop,
          rows: slot.cell.spanLength ?? 1,
          columnWidth: slot.columnWidth,
        );
      case TimesheetCellKind.emptyRunStart:
        _painter._text(
          canvas,
          '×',
          Offset(slot.centerX, slot.cellTop + 2),
          fontSize: 11,
          color: TimesheetDocumentPainter._gridMedium,
          centeredAtX: true,
        );
      case TimesheetCellKind.cameraKey:
        if (slot.cell.keyLabel case final name?) {
          _painter._instructions.paintEndpointName(canvas, slot, name);
        }
        _painter._instructions.paintSpanNameOn(
          canvas,
          slot,
          rows: _gridOf(slot, rowCount: rowCount),
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
          slot,
          rows: _gridOf(slot, rowCount: rowCount),
        );
      case TimesheetCellKind.emptyRunSpan:
        slot.paintStretchLine(canvas);
      case TimesheetCellKind.empty:
        break;
    }
  }
}

/// [firstRow], walked back to the start of the span that reaches it.
///
/// 🗣️F-78 (유저 2026-09-11): 「타임시트의 se행. se블록의 이름란이 뷰포트에서
/// 안보이면 대사 텍스트가 사라짐」. A span's START cell writes down the
/// whole span — an SE entry its name and dialogue, a hold chain its word, a
/// repeat chain its word — so culling the start row dropped ink the clip
/// would have kept: the one thing [_TimesheetCellsPass._rowRange] may not
/// do. The rows a word runs down read as EMPTY, so the walk steps over
/// empty rows up to the first cell that says where its span is.
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

/// The top and the bottom of the grid [slot] is printed in — its half page.
({double top, double bottom}) _gridOf(_CellSlot slot, {required int rowCount}) {
  final top = slot.cellTop - slot.row * TimesheetDocumentLayout.rowHeight;
  return (top: top, bottom: top + rowCount * TimesheetDocumentLayout.rowHeight);
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
    required this.stretchFrom,
    required this.lead,
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

  /// Where a run in this column starts its stretch line, or null for none
  /// ([TimesheetDocument.stretchLineFrom]).
  final int? stretchFrom;

  /// The block's stretch line down this cell's run — a held drawing's, or
  /// the empty run past an × — from the (N+1)th comma of a run of N+
  /// (industry N=3), each block by its own N ([stretchFrom]).
  void paintStretchLine(Canvas canvas) {
    final threshold = stretchFrom;
    if (threshold != null && (cell.spanOffset ?? 0) >= threshold) {
      canvas.drawLine(
        Offset(centerX, cellTop),
        Offset(centerX, cellBottom),
        Paint()
          ..color = TimesheetDocumentPainter._ink
          ..strokeWidth = 1.0,
      );
    }
  }

  /// How many rows before the sheet's first the span this cell starts
  /// began — a sound spilled in from an earlier cut (F-358) — else 0.
  final int lead;
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
    required this.secondsRight,
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

  /// Where a second's index ends — left of the numbers.
  final double secondsRight;
  final Paint lightPaint;
  final Paint mediumPaint;
  final Paint boldPaint;
  final List<(double, double)> seRanges;
}
