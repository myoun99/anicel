part of '../timesheet_document_painter.dart';

/// THE BANDS — the sheet's paper, the header band and its fields, the
/// memo band, the group titles and the cut's end line — as their own
/// object.
///
/// 🚨A collaborator carved out of `TimesheetDocumentPainter` (the audit's
/// SRP cut, 2026-09-02). It reaches the painter through `_painter`.
class _TimesheetBandsPass {
  _TimesheetBandsPass(this._painter);

  final TimesheetDocumentPainter _painter;

  /// The sheet of paper, and the printed edge around it — two strata that
  /// used to be one call: the fill is PAPER, the border is FORM.
  void paintPaper(Canvas canvas, int pageIndex) {
    final rect = _painter.layout.pageRect(pageIndex);
    if (_painter._drawPaper) {
      canvas.drawRect(rect, Paint()..color = TimesheetDocumentPainter._paper);
    }
    if (_painter._drawForm) {
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = TimesheetDocumentPainter._gridBold,
      );
    }
  }

  /// The header band: labeled boxes like the paper form —
  /// Ep.no | Title | Scene | Cut.no | Duration | Name | Page, minus hidden
  /// boxes. Reference-sheet layout (R7-⑥): the small gray label centers at
  /// the box top, the bold value centers underneath.
  void paintHeaderBand(
    Canvas canvas,
    int pageIndex, {
    required bool drawTexts,
  }) {
    final band = _painter.layout.headerBandRect(pageIndex);
    if (_painter._drawForm) {
      final boxPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = TimesheetDocumentPainter._gridBold;
      canvas.drawRect(band, boxPaint);
      for (final box in _painter.layout.headerFieldBoxes(pageIndex)) {
        canvas.drawRect(box.rect, boxPaint);
      }
    }
    if (!drawTexts) {
      return;
    }
    for (final box in _painter.layout.headerFieldBoxes(pageIndex)) {
      // The printed labels belong to the FORM; the user's values are
      // CONTENT (UI-R10 #9 — the PSD layer split, live).
      if (_painter._drawForm) {
        _painter._text(
          canvas,
          headerFieldLabel(box.field, _painter.notation),
          Offset(box.rect.center.dx, box.rect.top + 5),
          fontSize: 8,
          color: TimesheetDocumentPainter._gridMedium,
          centeredAtX: true,
        );
      }
      if (_painter._drawContent) {
        _painter._text(
          canvas,
          _headerFieldValue(box.field, pageIndex),
          Offset(box.rect.center.dx, box.rect.top + 26),
          fontSize: 14,
          bold: true,
          centeredAtX: true,
          maxWidth: box.rect.width - 12,
        );
      }
    }
  }

  /// The printed box label in the sheet's notation language (UI-R10 #7).
  static String headerFieldLabel(
    TimesheetHeaderField field, [
    TimesheetNotation notation = TimesheetNotation.english,
  ]) {
    return switch (field) {
      TimesheetHeaderField.episode => notation.episode,
      TimesheetHeaderField.title => notation.title,
      TimesheetHeaderField.scene => notation.scene,
      TimesheetHeaderField.cut => notation.cut,
      TimesheetHeaderField.time => notation.duration,
      TimesheetHeaderField.name => notation.name,
      TimesheetHeaderField.sheet => notation.page,
    };
  }

  String _headerFieldValue(TimesheetHeaderField field, int pageIndex) {
    return switch (field) {
      TimesheetHeaderField.episode => _painter.document.episode,
      TimesheetHeaderField.title => _painter.document.title,
      TimesheetHeaderField.scene => _painter.document.scene,
      TimesheetHeaderField.cut => _painter.document.cutName,
      // The sheet's 秒+コマ notation prints spaced ('2 + 6') like the
      // reference forms; the model label stays compact for row labels.
      TimesheetHeaderField.time => _painter.document.durationLabel.replaceAll(
        '+',
        ' + ',
      ),
      TimesheetHeaderField.name => _painter.document.artist,
      TimesheetHeaderField.sheet => _painter.layout.pageLabel(pageIndex),
    };
  }

  /// The Direction memo band under the header: COMPLETELY open handwriting
  /// space, exactly like the reference forms (R7-⑥ — the band outline and
  /// the top-right memo box frame are both retired). The cut's Direction
  /// memo (cut note) types into its top left, spanning the full width.
  void paintMemoBand(Canvas canvas, int pageIndex, {required bool drawTexts}) {
    if (!drawTexts) {
      return;
    }
    final band = _painter.layout.memoBandRect(pageIndex);
    if (_painter.document.memoText.isNotEmpty) {
      final painter = TextPainter(
        text: TextSpan(
          text: _painter.document.memoText,
          style: const TextStyle(
            color: TimesheetDocumentPainter._ink,
            fontSize: 11,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 8,
        ellipsis: '…',
      )..layout(maxWidth: band.width - 16);
      painter.paint(canvas, Offset(band.left + 8, band.top + 6));
    }
    // NO derived instruction lines here anymore (R5-⑥): the shorthand
    // ('A→B PAN …') writes itself INTO the cut note once when the
    // instruction is created, so it prints above as ordinary — editable —
    // note text.
  }

  /// The cut-end strikethrough at the bottom edge of the last playback
  /// frame row — DATA rendering (S2-0), the same visual language as the
  /// timeline's cut-end boundary, never ink.
  void paintCutEndLine(Canvas canvas) {
    final frameCount = _painter.livePlaybackFrameCount;
    if (frameCount < 1 || frameCount > _painter.document.rowCount) {
      return;
    }
    final line = _painter.layout.cutEndLineFor(frameCount);
    // In page view the cut may end on a page that isn't on screen (R26
    // #41) — its row geometry belongs to another sheet, so nothing prints.
    if (!_painter.layout.visiblePageIndexes.contains(line.page)) {
      return;
    }
    final left = _painter.layout.halfLeft(line.page, line.half);
    canvas.drawLine(
      Offset(left, line.y),
      Offset(left + _painter.layout.halfWidth, line.y),
      Paint()
        ..color = AppColors.danger
        ..strokeWidth = 2.4,
    );
  }

  void paintGroupTitles(Canvas canvas, double halfLeft, double groupTop) {
    // Contiguous kind runs become group headers (ACTION / SE / CELL / CAM).
    var runStart = 0;
    while (runStart < _painter.document.columns.length) {
      final kind = _painter.document.columns[runStart].kind;
      var runEnd = runStart;
      while (runEnd + 1 < _painter.document.columns.length &&
          _painter.document.columns[runEnd + 1].kind == kind) {
        runEnd += 1;
      }
      final leftX = halfLeft + _painter.layout.columnLeftInHalf(runStart);
      final rightX =
          halfLeft +
          _painter.layout.columnLeftInHalf(runEnd) +
          _painter.layout.columnWidthFor(kind);
      final title = switch (kind) {
        TimesheetColumnKind.action => 'ACTION',
        TimesheetColumnKind.se => 'SE',
        TimesheetColumnKind.cel => 'CELL',
        TimesheetColumnKind.camera => 'CAM',
      };
      _painter._text(
        canvas,
        title,
        Offset((leftX + rightX) / 2, groupTop + 2),
        fontSize: 9,
        bold: true,
        color: TimesheetDocumentPainter._ink,
        centeredAtX: true,
      );
      runStart = runEnd + 1;
    }
  }
}
