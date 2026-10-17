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
  /// this cut runs past its end — the mark straddles the cut's end line,
  /// centred on its SE column. START: a sound from an earlier cut
  /// spills into row 0 — the mark straddles the column's first row edge.
  /// Pure display, exactly the timeline rows' meaning, drawn by their own
  /// drawer standing down the column ([paintSeCrossingMark], F-358).
  void paintSeCrossingMarks(Canvas canvas) {
    // The `~` straddles the line the cut is DRAWN to, and follows the same
    // live length, or a drag leaves it hanging where the end used to be.
    // 🗣️F-358 (유저 2026-10-17): 「컷 엔드라인(OL여백이든 뭐든 총합적인
    // 엔드라인) 넘어가는건 안보이게하고, 물론 ~표시가 있는데」. ↩️F-227 moved
    // the END LINE to the drawn end and left this mark on the conte end —
    // 「a sound crossing into the next cut still crosses here」.
    final frameCount = _painter.liveDrawnFrameCount;
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
          frameCount <= _painter.document.rowCount) {
        final left =
            _painter.layout.halfLeft(endLine.page, endLine.half) +
            _painter.layout.columnLeftInHalf(column);
        paintSeCrossingMark(
          canvas,
          Offset(left + columnWidth / 2, endLine.y),
          Axis.vertical,
        );
      }
      if (spec.spillsInAtStart) {
        final left =
            _painter.layout.halfLeft(startPosition.page, startPosition.half) +
            _painter.layout.columnLeftInHalf(column);
        paintSeCrossingMark(
          canvas,
          Offset(left + columnWidth / 2, startTop),
          Axis.vertical,
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
  ///
  /// 🗣️F-358: a sound that spilled in from an earlier cut began [lead] rows
  /// before this one. Its HEAD — the opening bar, the delivery, the name
  /// box — is that cut's, and this row shows the words the block's one
  /// layout lays here ([paintSeDialogueShare]). ↩️It opened the block again
  /// at row 0, with the name box, and spread the whole line over the rows
  /// the cut had left.
  void paintSeEntryStart(
    Canvas canvas, {
    required TimesheetCell cell,
    required int lead,
    required int row,
    required int rowCount,
    required double columnLeft,
    required double columnWidth,
    required double centerX,
    required double cellTop,
  }) {
    final seName = cell.seName ?? '';
    if (lead == 0) {
      paintSeRedBar(
        canvas,
        columnLeft: columnLeft,
        columnWidth: columnWidth,
        y: cellTop + 1,
      );
      _paintDelivery(
        canvas,
        cell.seType,
        boundary: Offset(centerX, cellTop),
        maxWidth: columnWidth - 2,
      );
      if (seName.isNotEmpty) {
        _paintNameBox(
          canvas,
          seName,
          Rect.fromLTWH(columnLeft, cellTop + 2, columnWidth, _nameBoxHeight),
        );
      }
    }

    paintSeDialogueShare(
      canvas,
      start: cell,
      spanOffset: 0,
      lead: lead,
      row: row,
      rowCount: rowCount,
      centerX: centerX,
      cellTop: cellTop,
    );

    if ((cell.spanLength ?? 1) == 1) {
      paintSeRedBar(
        canvas,
        columnLeft: columnLeft,
        columnWidth: columnWidth,
        y: cellTop + TimesheetDocumentLayout.rowHeight - 1,
      );
    }
  }

  static const double _nameBoxHeight = 12.0;

  /// The entry's name chip, over [box].
  ///
  /// R6-②: a soft accent tint with dark ink writing — the full-strength
  /// accent read too loud against the paper. FULL column width (R7-②: the
  /// name box, the red bars and the SE column must share ONE exact width —
  /// the old 1px inset read as a mismatched overlay).
  void _paintNameBox(Canvas canvas, String seName, Rect box) {
    canvas.drawRect(
      box,
      Paint()..color = _painter.accent.withValues(alpha: 0.3),
    );
    _painter._text(
      canvas,
      seName,
      Offset(box.center.dx, box.top + 2),
      fontSize: 7,
      bold: true,
      color: TimesheetDocumentPainter._ink,
      centeredAtX: true,
      maxWidth: box.width - 4,
    );
  }

  /// How far above the entry's red bar the delivery's writing starts — one
  /// line of the name's size, so it sits on the bar rather than across it.
  static const double _deliveryLift = 9.0;

  /// 🗣️I-20 (유저 2026-09-30): the delivery over the name — 「타임시트에도
  /// 이름 위에 빨간 가로선 위에 배경색없이 텍스트만」 — and only where the
  /// sheets print it (「OFF거나 MONO일때만」, [SeLineType.printsOnSheets]).
  /// On the half's first row the row above IS the column's title, and it
  /// lands there on purpose: 「1콤마부터 대사 나올땐 … 1콤마의 위(SE1이나
  /// SE2 이런글자)에 겹치도록」.
  void _paintDelivery(
    Canvas canvas,
    SeLineType? delivery, {
    required Offset boundary,
    required double maxWidth,
  }) {
    if (delivery == null || !delivery.printsOnSheets) {
      return;
    }
    _painter._text(
      canvas,
      delivery.label,
      boundary.translate(0, -_deliveryLift),
      fontSize: 7,
      bold: true,
      color: TimesheetDocumentPainter._ink,
      centeredAtX: true,
      maxWidth: maxWidth,
    );
  }

  /// This page half's share of an SE entry's dialogue: the glyphs that the
  /// layout over the WHOLE span lands on this half's rows, from [row] down
  /// to [rowCount] — [start] is the span's first cell on this sheet, and
  /// carries the words and the name box they sit under; [spanOffset] is
  /// how far down the span this row is, and [lead] how many of its rows
  /// ran in earlier cuts.
  ///
  /// 🗣️F-358 (유저 2026-10-14 · 10-17): 「타임시트패널에도 타임라인에서
  /// 보이는 글자 나눠짐상태? 그대로 보이도록. 즉 오프셋 맞추듯이?」. The
  /// span is the block's TRUE one — from the head an earlier cut holds, to
  /// the end it reaches past the sheet's rows — and a half, or the cut, is
  /// a window on its one layout: each glyph shows whole, where that layout
  /// lays it, in the window holding its centre ([paintDialogueFitColumn]),
  /// as the timeline's rows show it. ↩️Each half wrote its share again,
  /// spread over its own rows.
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
    required int lead,
    required int row,
    required int rowCount,
    required double centerX,
    required double cellTop,
  }) {
    const rowHeight = TimesheetDocumentLayout.rowHeight;
    final spanTop = cellTop - (lead + spanOffset) * rowHeight;
    final spanBottom =
        spanTop + (lead + (start.spanLength ?? 1)) * rowHeight - 2;
    final dialogueTop =
        spanTop + ((start.seName ?? '').isEmpty ? 3 : _nameBoxHeight + 4);
    // The window: this half's rows of the span.
    final top = math.max(dialogueTop, cellTop);
    final bottom = math.min(spanBottom, cellTop + (rowCount - row) * rowHeight);
    if (bottom <= top) {
      return;
    }
    paintDialogueFitColumn(
      canvas,
      start.label ?? '',
      topCenter: Offset(centerX, dialogueTop),
      extent: spanBottom - dialogueTop,
      shownFrom: top - dialogueTop,
      shownTo: bottom - dialogueTop,
      style: _painter.face.copyWith(
        color: TimesheetDocumentPainter._ink,
        fontSize: 9,
      ),
      setWord: paintScaledText,
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
