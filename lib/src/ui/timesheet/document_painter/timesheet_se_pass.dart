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

    if (seName.isNotEmpty) {
      // R6-②: a soft accent tint with dark ink writing — the full-strength
      // accent read too loud against the paper. FULL column width (R7-②:
      // the name box, the red bars and the SE column must share ONE exact
      // width — the old 1px inset read as a mismatched overlay).
      canvas.drawRect(
        Rect.fromLTWH(columnLeft, cellTop + 2, columnWidth, _nameBoxHeight),
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
    }

    paintSeDialogueShare(
      canvas,
      start: cell,
      spanOffset: cell.spanOffset ?? 0,
      row: row,
      rowCount: rowCount,
      centerX: centerX,
      cellTop: cellTop,
    );

    if (spanLength == 1) {
      paintSeRedBar(
        canvas,
        columnLeft: columnLeft,
        columnWidth: columnWidth,
        y: spanBottom - 1,
      );
    }
  }

  static const double _nameBoxHeight = 12.0;

  /// This page half's share of an SE entry's dialogue: the glyphs that the
  /// layout over the WHOLE span lands on this half's rows, from [row] down —
  /// [start] is the span's first cell, and carries the words and the name
  /// box they sit under — written inside those rows, so a glyph never
  /// straddles the edge of the half.
  ///
  /// 🗣️F-165 (유저 2026-09-18): 「왼쪽영역에서 시작한 블록이면 대사가 다
  /// 왼쪽 시작한곳의 영역에 몰아서 써져있음. 오른쪽 영역에 나눠서
  /// 들어가야하는데 … 제대로 근본/구조적으로 해결」. The start cell fitted the
  /// whole dialogue into the rows its OWN half had left, and the half the
  /// entry ran on into wrote nothing. It is the law the camera marks already
  /// keep (`_paintInstructionMarkSlice`): the geometry derives from the
  /// cell's place in its span, and each half paints only its own rows.
  ///
  /// ↩️F-78 (09-11) pinned 「the half it runs on into keeps NONE of its
  /// writing」 — to kill a mutant of the culling walk, not by any decision
  /// about the page; F-165 is the decision, and it is the opposite.
  void paintSeDialogueShare(
    Canvas canvas, {
    required TimesheetCell start,
    required int spanOffset,
    required int row,
    required int rowCount,
    required double centerX,
    required double cellTop,
  }) {
    const rowHeight = TimesheetDocumentLayout.rowHeight;
    final glyphs = (start.label ?? '').characters.toList(growable: false);
    final spanTop = cellTop - spanOffset * rowHeight;
    final spanBottom = spanTop + (start.spanLength ?? 1) * rowHeight - 2;
    final dialogueTop =
        spanTop + ((start.seName ?? '').isEmpty ? 3 : _nameBoxHeight + 4);
    // Which words are this half's: where the whole span's layout lands them.
    final top = math.max(dialogueTop, cellTop);
    final bottom = math.min(spanBottom, cellTop + (rowCount - row) * rowHeight);
    final centers = dialogueGlyphCenters(
      glyphCount: glyphs.length,
      mainExtent: spanBottom - dialogueTop,
    );
    final share = [
      for (var i = 0; i < glyphs.length; i += 1)
        if (dialogueTop + centers[i] >= top && dialogueTop + centers[i] < bottom)
          glyphs[i],
    ];
    if (share.isEmpty || bottom - top <= 4) {
      return;
    }
    // …and written inside this half's rows, so no glyph straddles the edge
    // of the page half.
    paintDialogueFitColumn(
      canvas,
      share.join(),
      topCenter: Offset(centerX, top),
      extent: bottom - top,
      style: const TextStyle(color: TimesheetDocumentPainter._ink, fontSize: 9),
    );
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
