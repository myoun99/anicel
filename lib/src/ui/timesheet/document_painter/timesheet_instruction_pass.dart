part of '../timesheet_document_painter.dart';

/// THE INSTRUCTION PASS — the instruction row of the sheet: its bar, its
/// label, the mark slices along it and the triangles at its ends — as
/// its own object.
///
/// 🚨A collaborator carved out of `TimesheetDocumentPainter` (the audit's
/// SRP cut, 2026-09-02). Measured before cutting: the ink and the text
/// helper shared, nothing else. It reaches the painter through
/// `_painter`.
class _TimesheetInstructionPass {
  _TimesheetInstructionPass(this._painter);

  final TimesheetDocumentPainter _painter;

  /// One row of an instruction span, in the X-sheet's exact visual
  /// language (R4): the bar mark is ONE unadorned continuous line between
  /// the endpoint rows' centers — no end ticks, never broken for text —
  /// and FI/FO/O.L marks are light-gray filled wedges owning the full
  /// column width; the A/B names center in the start/end cells like frame
  /// names and the writing centers on the SPAN's true center, drawn over
  /// the mark.
  void paintInstructionRow(
    Canvas canvas, {
    required TimesheetCell cell,
    required double columnLeft,
    required double columnWidth,
    required double centerX,
    required double cellTop,
  }) {
    const rowHeight = TimesheetDocumentLayout.rowHeight;
    final cellBottom = cellTop + rowHeight;
    final spanLength = cell.spanLength ?? 1;
    final offset = cell.spanOffset ?? 0;
    final isFirst = offset == 0;
    final isLast = offset == spanLength - 1;

    if ((cell.markType ?? CameraInstructionMarkType.bar) ==
        CameraInstructionMarkType.bar) {
      // R5-⑤: the endpoint cells carry NO line — the names own them. Each
      // row between draws edge to edge (R6-①a: the per-cell padding made
      // the bar read as broken dashes), thin like a ruled sheet line. A
      // NAMELESS endpoint carries the solid triangle cap instead (real
      // sheets, R7-①) and the line runs through its row to meet it.
      final linePaint = Paint()
        ..color = TimesheetDocumentPainter._ink
        ..strokeWidth = 0.9;
      final hasA = (cell.valueA ?? '').isNotEmpty;
      final hasB = (cell.valueB ?? '').isNotEmpty;
      final triangleLength = math.min(
        7.0,
        TimesheetDocumentLayout.rowHeight - 4,
      );
      if (!isFirst && !isLast) {
        canvas.drawLine(
          Offset(centerX, cellTop),
          Offset(centerX, cellBottom),
          linePaint,
        );
      } else if (isFirst && isLast) {
        if (!hasA && !hasB) {
          // Single-row nameless span: both caps in the one cell (▼ over ▲).
          _paintBarEndpointTriangle(
            canvas,
            centerX: centerX,
            columnWidth: columnWidth,
            baseY: cellTop,
            apexDown: true,
          );
          _paintBarEndpointTriangle(
            canvas,
            centerX: centerX,
            columnWidth: columnWidth,
            baseY: cellBottom,
            apexDown: false,
          );
        }
      } else if (isFirst) {
        if (!hasA) {
          _paintBarEndpointTriangle(
            canvas,
            centerX: centerX,
            columnWidth: columnWidth,
            baseY: cellTop,
            apexDown: true,
          );
          canvas.drawLine(
            Offset(centerX, cellTop + triangleLength),
            Offset(centerX, cellBottom),
            linePaint,
          );
        }
      } else if (!hasB) {
        _paintBarEndpointTriangle(
          canvas,
          centerX: centerX,
          columnWidth: columnWidth,
          baseY: cellBottom,
          apexDown: false,
        );
        canvas.drawLine(
          Offset(centerX, cellTop),
          Offset(centerX, cellBottom - triangleLength),
          linePaint,
        );
      }
    } else {
      _paintInstructionMarkSlice(
        canvas,
        cell: cell,
        centerX: centerX,
        halfWidth: columnWidth / 2 - 1,
        cellTop: cellTop,
      );
    }

    // Writing goes BOLD (R6-①a): it sits directly on the bar/mark and has
    // to stay readable over it.
    if (isFirst && (cell.valueA ?? '').isNotEmpty) {
      _painter._text(
        canvas,
        cell.valueA!,
        Offset(centerX, cellTop + 3),
        fontSize: 10,
        bold: true,
        color: TimesheetDocumentPainter._ink,
        centeredAtX: true,
        maxWidth: columnWidth - 2,
      );
    }
    if (isLast && !isFirst && (cell.valueB ?? '').isNotEmpty) {
      _painter._text(
        canvas,
        cell.valueB!,
        Offset(centerX, cellTop + 3),
        fontSize: 10,
        bold: true,
        color: TimesheetDocumentPainter._ink,
        centeredAtX: true,
        maxWidth: columnWidth - 2,
      );
    }
    if (isFirst && isLast && (cell.valueB ?? '').isNotEmpty) {
      // Single-row span: B shares the row under A.
      _painter._text(
        canvas,
        cell.valueB!,
        Offset(centerX, cellBottom - 9),
        fontSize: 7,
        bold: true,
        color: TimesheetDocumentPainter._ink,
        centeredAtX: true,
        maxWidth: columnWidth - 2,
      );
    }
    if (offset == (spanLength - 1) ~/ 2 && (cell.label ?? '').isNotEmpty) {
      _paintInstructionLabel(
        canvas,
        cell.label!,
        columnLeft: columnLeft,
        columnWidth: columnWidth,
        spanTop: cellTop - offset * rowHeight,
        spanLength: spanLength,
      );
    }
  }

  /// The instruction's NAME, written DOWN the column beside its mark — the
  /// x-sheet's treatment, in print (user, 2026-08-08).
  ///
  /// Two things were wrong with the horizontal line it replaces. It was
  /// centred on `centerX`, which is where the duration bar is drawn, so
  /// the two were printed through each other. And it ran ACROSS, so
  /// `FOLLOW PAN` reached well past a 36px CAM column into whatever was
  /// beside it.
  ///
  /// It hangs off the column's RIGHT wall now, one glyph wide, centred on
  /// the span along the frame axis. Long names SPILL past their span
  /// rather than pack: the sheet's usual squeeze would put ten letters in
  /// a three-row span at 2.4pt, which is the very failure sideways Latin
  /// was invented to avoid. Writing that runs past its span is what a hand
  /// does on paper anyway.
  void _paintInstructionLabel(
    Canvas canvas,
    String label, {
    required double columnLeft,
    required double columnWidth,
    required double spanTop,
    required int spanLength,
  }) {
    const fontSize = 9.0;
    const lineHeight = 1.15;
    const naturalCellExtent = fontSize * lineHeight;
    // The right HALF of the column, inside its wall AND clear of the
    // centre line: the mark owns that line and the writing may never come
    // back over it. Both insets count — a CAM group past two columns
    // halves its column to 18px, and with only the wall subtracted the
    // clamped glyph landed exactly on the bar.
    final room = columnWidth / 2 - 2 * instructionLabelInset;
    if (room <= 0) {
      return;
    }
    final glyphWidth = math.min(fontSize, room);
    final cellCount = verticalTextSpanCount(
      verticalTextCells(label, latinForm: VerticalLatinForm.upright),
    );
    // The extent the column ACTUALLY needs, handed in as the span: with
    // supply equal to demand the shrink rule is a no-op, which is how
    // "spill, never pack" is stated to a painter that only knows how to
    // pack.
    final needed = cellCount * naturalCellExtent;
    paintVerticalText(
      canvas,
      label,
      style: _painter.face.copyWith(
        color: TimesheetDocumentPainter._ink,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
      ),
      centerX:
          columnLeft + columnWidth - instructionLabelInset - glyphWidth / 2,
      top:
          spanTop +
          spanLength * TimesheetDocumentLayout.rowHeight / 2 -
          needed / 2,
      mainExtent: needed,
      naturalCellExtent: naturalCellExtent,
      cellPadding: fontSize * (lineHeight - 1),
      maxCellWidth: glyphWidth,
      latinForm: VerticalLatinForm.upright,
    );
  }

  /// The solid triangle capping a NAMELESS bar endpoint (R7-①, real-sheet
  /// convention), APEX pointing INTO the span (R8-① direction fix): the
  /// start cap reads ▼ from the span's top edge, the end cap ▲ from its
  /// bottom edge — both bases sit FLUSH on the cell edge (compact, no
  /// inset). The duration line meets the apex. Mirrors the X-sheet
  /// overlay's mark.
  void _paintBarEndpointTriangle(
    Canvas canvas, {
    required double centerX,
    required double columnWidth,
    required double baseY,
    required bool apexDown,
  }) {
    final length = math.min(7.0, TimesheetDocumentLayout.rowHeight - 4);
    final halfWidth = math.min(4.0, columnWidth / 2 - 2);
    final apexY = apexDown ? baseY + length : baseY - length;
    canvas.drawPath(
      Path()..addPolygon([
        Offset(centerX - halfWidth, baseY),
        Offset(centerX, apexY),
        Offset(centerX + halfWidth, baseY),
      ], true),
      Paint()..color = TimesheetDocumentPainter._ink,
    );
  }

  /// One row's slice of an instruction span's FI/FO wedge or O.L bowtie:
  /// the mark geometry derives span-globally from the cell's
  /// spanOffset/spanLength and clips to this row, so spans crossing page
  /// halves paint seamlessly (each half paints only its own rows). The
  /// mark owns the column's full width ([halfWidth] from the caller),
  /// exactly like the X-sheet overlay.
  void _paintInstructionMarkSlice(
    Canvas canvas, {
    required TimesheetCell cell,
    required double centerX,
    required double halfWidth,
    required double cellTop,
  }) {
    const rowHeight = TimesheetDocumentLayout.rowHeight;
    final shaftX = centerX;
    final spanTop = cellTop - (cell.spanOffset ?? 0) * rowHeight;
    final spanBottom = spanTop + (cell.spanLength ?? 1) * rowHeight;
    final mid = (spanTop + spanBottom) / 2;
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(
        shaftX - halfWidth - 1,
        cellTop,
        (halfWidth + 1) * 2,
        rowHeight,
      ),
    );
    // R4: dedicated marks are plain LIGHT-GRAY FILLS laid under the grid
    // and the writing — no hatching, no outline (user sketch).
    final fill = Paint()
      ..color = TimesheetDocumentPainter._ink.withValues(alpha: 0.15);
    switch (cell.markType ?? CameraInstructionMarkType.bar) {
      case CameraInstructionMarkType.ol:
        canvas.drawPath(
          Path()..addPolygon([
            Offset(shaftX - halfWidth, spanTop),
            Offset(shaftX + halfWidth, spanTop),
            Offset(shaftX, mid),
          ], true),
          fill,
        );
        canvas.drawPath(
          Path()..addPolygon([
            Offset(shaftX - halfWidth, spanBottom),
            Offset(shaftX + halfWidth, spanBottom),
            Offset(shaftX, mid),
          ], true),
          fill,
        );
      case CameraInstructionMarkType.fi:
      case CameraInstructionMarkType.fo:
        // The fade wedge follows the light: FI opens narrow → wide (the
        // picture grows in), FO wide → narrow (R4 orientation fix).
        final fadeIn = cell.markType == CameraInstructionMarkType.fi;
        final wideY = fadeIn ? spanBottom - 1 : spanTop + 1;
        final pointY = fadeIn ? spanTop + 1 : spanBottom - 1;
        canvas.drawPath(
          Path()..addPolygon([
            Offset(shaftX - halfWidth, wideY),
            Offset(shaftX, pointY),
            Offset(shaftX + halfWidth, wideY),
          ], true),
          fill,
        );
      case CameraInstructionMarkType.bar:
        // Dispatched to the straight-line path before reaching here.
        break;
    }
    canvas.restore();
  }
}
