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

  /// The sheet of paper — no printed edge around it ([paintSheetPaper]).
  void paintPaper(Canvas canvas, int pageIndex) {
    if (_painter._drawPaper) {
      paintSheetPaper(
        canvas,
        _painter.layout.pageRect(pageIndex),
        TimesheetDocumentPainter._paper,
        // With no view it is an export, whose canvas lands on its pixels
        // already: its ratio says what its photos are sampled for.
        pixelRatio: _painter.viewport == null ? 1 : _painter.effectiveRatio,
      );
    }
  }

  /// The header band: labeled boxes like the paper form —
  /// Ep.no | Title | Scene | Cut.no | Duration | Name | Page, minus hidden
  /// boxes. Reference-sheet layout (R7-⑥): the small gray label centers at
  /// the box top, the bold value centers underneath.
  void paintHeaderBand(Canvas canvas, int pageIndex) {
    final boxes = _painter.layout.headerFieldBoxes(pageIndex);
    if (_painter._drawsOurForm) {
      _paintOurHeaderForm(canvas, pageIndex, boxes);
    }
    for (final box in boxes) {
      _paintHeaderValue(canvas, box, pageIndex);
    }
  }

  /// Our form's header: the band and its boxes ruled, each box's label
  /// small at its top. The printed labels belong to the FORM; the user's
  /// values are CONTENT (UI-R10 #9 — the PSD layer split, live).
  void _paintOurHeaderForm(
    Canvas canvas,
    int pageIndex,
    List<TimesheetHeaderBox> boxes,
  ) {
    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = TimesheetDocumentPainter._gridBold;
    canvas.drawRect(_painter.layout.headerBandRect(pageIndex), boxPaint);
    for (final box in boxes) {
      canvas.drawRect(box.rect, boxPaint);
      _painter._text(
        canvas,
        headerFieldLabel(box.field, _painter.words),
        Offset(box.rect.center.dx, box.rect.top + 5),
        fontSize: 8,
        color: TimesheetDocumentPainter._gridMedium,
        centeredAtX: true,
      );
    }
  }

  /// [box]'s value where the header's values print, and — under the cut's
  /// name — the cuts it is 겸용 with, where those do: they hang from where
  /// the name stands, printed or not. On an XDTS sheet the length and the
  /// sheet count are written the viewer's way ([_XdtsCountsPass]).
  void _paintHeaderValue(
    Canvas canvas,
    TimesheetHeaderBox box,
    int pageIndex,
  ) {
    final field = box.field;
    final values = _painter._drawsPart(TimesheetContentPart.header);
    if (_painter._xdts case final xdts? when _XdtsCountsPass.writes(field)) {
      if (values) {
        xdts.counts.paint(canvas, field, pageIndex);
      }
      return;
    }
    final linked =
        field == TimesheetHeaderField.cut &&
        _painter._drawsPart(TimesheetContentPart.linkedCuts);
    if (!values && !linked) {
      return;
    }
    final value = box.value;
    final line = sheetLine(
      headerFieldValue(field, pageIndex),
      TimesheetDocumentPainter.wordsStyle(
        _painter.face,
        fontSize: TimesheetDocumentPainter.headerValueSize,
        bold: true,
      ),
    );
    final place = SheetLinePlace.of(
      line.size,
      value,
      SheetTextForm.centredLine,
    );
    if (values) {
      place.paint(canvas, line);
      if (field == TimesheetHeaderField.time && _owesNoriShiro) {
        _paintDrawnLength(canvas, value);
      }
    }
    line.dispose();
    if (linked) {
      _paintLinkedCuts(canvas, place.rect, value);
    }
  }

  /// The DRAWN length, small, under the conte 尺 in the duration box.
  ///
  /// 🗣️F-227 (유저 2026-09-29): 「ol여백이 있는 컷은 초수에도 기입함. 2+0
  /// 이라는 기존 초수가 있고, 그 밑에 작게, (2+12)라는 여백포함한 초수를
  /// 기입해주는것이 관례. 즉 초수가 두개가 생기는거지」. The big number stays
  /// the conte 尺 — the one that sums to the running time (撮ま!).
  void _paintDrawnLength(Canvas canvas, Rect value) {
    _painter._text(
      canvas,
      '(${_spacedLength(_painter.liveDrawnFrameCount)})',
      Offset(
        value.center.dx,
        value.top + TimesheetDocumentPainter.headerValueSize + 4,
      ),
      fontSize: TimesheetDocumentPainter.headerUnderSize,
      centeredAtX: true,
      maxWidth: value.width,
    );
  }

  /// The cuts the cut is 겸용 with, small, a line each under its [name],
  /// from its left, a 「(」 binding the name and them — in the box label's
  /// grey, so the cut's own name is the one that reads. [value] is the
  /// room the box sets its value in.
  ///
  /// 🗣️F-558 (유저 2026-11-04): 「고정텍스트 on이든 off이든 연관없음. 항상
  /// 보여줌. 위치는 헤더의 컷 번호 아래에 겸용컷들을 텍스트로 둠. 심플하게
  /// 텍스트로만 쭉 나열. 그러고 왼쪽에 ( 이 모양으로 컷들 묶는느낌」 · 「다른
  /// 겸용컷 보여주는 텍스트는 텍스트색이랑 ( 아이콘 동일하게 연하게 표시하자.
  /// 겸용컷의 컷이름 글자도 헤더 컷이름 텍스트보다 작게」 · 「작게하고
  /// (아이콘에 붙여야하니까 왼쪽정렬」 · F-558-Q1 「손글씨(잉크?)로 말고 텍스트
  /// 층으로만」. In the sketch the list ran on past the box's foot, over the
  /// memo band — so it does here.
  void _paintLinkedCuts(Canvas canvas, Rect name, Rect value) {
    final cuts = _painter.document.linkedCuts;
    if (cuts.isEmpty) {
      return;
    }
    var top = name.bottom;
    for (final cut in cuts) {
      final line = sheetLine(
        cut,
        TimesheetDocumentPainter.wordsStyle(
          _painter.face,
          fontSize: TimesheetDocumentPainter.headerUnderSize,
          color: TimesheetDocumentPainter._gridMedium,
        ),
      );
      final place = SheetLinePlace.of(
        line.size,
        Rect.fromLTRB(name.left, top, value.right, top + line.height),
        SheetTextForm.leftLine,
      )..paint(canvas, line);
      line.dispose();
      top = place.rect.bottom;
    }
    _paintBinding(canvas, Rect.fromLTRB(name.left, name.top, name.left, top));
  }

  /// A 「(」 standing just left of [lines], from their top to their foot.
  void _paintBinding(Canvas canvas, Rect lines) {
    const gap = 2.0;
    const bow = 3.0;
    final x = lines.left - gap;
    canvas.drawPath(
      Path()
        ..moveTo(x, lines.top)
        ..quadraticBezierTo(x - bow * 2, lines.center.dy, x, lines.bottom),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = TimesheetDocumentPainter._gridMedium,
    );
  }

  /// A length in the sheet's 秒+コマ notation, spaced ('2 + 6') like the
  /// reference forms; the model label stays compact for row labels.
  String _spacedLength(int frames) =>
      _painter.document.frameLabel(frames).replaceAll('+', ' + ');

  /// The printed box label in the sheet's notation language (UI-R10 #7).
  static String headerFieldLabel(
    TimesheetHeaderField field,
    TimesheetWords words,
  ) {
    return switch (field) {
      TimesheetHeaderField.episode => words.episode,
      TimesheetHeaderField.title => words.title,
      TimesheetHeaderField.scene => words.scene,
      TimesheetHeaderField.cut => words.cut,
      TimesheetHeaderField.time => words.duration,
      TimesheetHeaderField.name => words.name,
      TimesheetHeaderField.sheet => words.page,
    };
  }

  /// The value a header box prints — the CONTENT stratum's text.
  ///
  /// The length and the sheet count are read LIVE, so the header follows a
  /// cut-length drag instead of waiting for the release (F-88); the rest
  /// is typed ([TimesheetDocumentLayout.typedHeaderValue]).
  String headerFieldValue(TimesheetHeaderField field, int pageIndex) =>
      switch (field) {
        TimesheetHeaderField.time => _spacedLength(
          _painter.livePlaybackFrameCount,
        ),
        TimesheetHeaderField.sheet => _painter.layout.pageLabel(
          pageIndex,
          pageCount: _painter.livePageCount,
        ),
        _ => _painter.layout.typedHeaderValue(field)!,
      };

  /// The Direction memo band under the header: COMPLETELY open handwriting
  /// space, exactly like the reference forms (R7-⑥ — the band outline and
  /// the top-right memo box frame are both retired). The page's Direction
  /// memo types into its top left, spanning the full width (F-301: each
  /// page its own).
  void paintMemoBand(Canvas canvas, int pageIndex) {
    for (final side in SheetMemoSide.values) {
      _paintFixedLines(canvas, pageIndex, side);
      _paintMemo(canvas, pageIndex, side);
    }
    // Since I-72 no line is written INTO a memo: it is the person's alone.
    // ↩️F-542 took back R5-⑥'s 「no derived lines in the band」: they stand
    // over the memos, as the conte cell's over its ACTION words.
  }

  /// The memo on [side] of the page, wrapped at its width.
  void _paintMemo(Canvas canvas, int pageIndex, SheetMemoSide side) {
    final memo = _painter.layout.memoWordsRect(pageIndex, side);
    final text = _painter.document.memoTextOf(pageIndex, side: side);
    if (text.isEmpty) {
      return;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TimesheetDocumentPainter.wordsStyle(
          _painter.face,
          fontSize: TimesheetDocumentPainter.memoSize,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: memo.height ~/ TimesheetDocumentPainter.memoLine,
      ellipsis: '…',
    )..layout(maxWidth: memo.width);
    painter.paint(canvas, memo.topLeft);
  }

  /// What the page writes of itself on [side], a line each down from the
  /// top, shrunk to the side's width as the conte's are.
  void _paintFixedLines(Canvas canvas, int pageIndex, SheetMemoSide side) {
    const size = TimesheetDocumentPainter.memoSize;
    const line = TimesheetDocumentPainter.memoLine;
    final lines = _painter.layout.fixedLinesOn(pageIndex, side);
    final room = _painter.layout.memoSideRect(pageIndex, side);
    for (final (index, text) in lines.indexed) {
      final top = room.top + index * line;
      _painter._text(
        canvas,
        text,
        Offset(room.left, top),
        fontSize: sheetWordsSize(
          SheetWords(
            SheetPaintLayer.content,
            text: text,
            slot: Rect.fromLTWH(room.left, top, room.width, line),
            size: size,
            argb: TimesheetDocumentPainter._ink.toARGB32(),
            fit: SheetWordsFit.shrink,
          ),
          (size, {required bold, required color}) =>
              TimesheetDocumentPainter.wordsStyle(
                _painter.face,
                fontSize: size,
                color: color,
                bold: bold,
              ),
        ),
        maxWidth: room.width,
      );
    }
  }

  /// The cut-end strikethrough at the bottom edge of the last row the
  /// animator fills — DATA rendering (S2-0), the same visual language as the
  /// timeline's cut-end boundary, never ink.
  ///
  /// 🗣️F-227 (유저 2026-09-29): 「컷ol만들면 … 진짜 엔드라인은 여백라인이
  /// 엔드라인이됨. 즉 타임시트패널에서 엔드라인을 여백엔드라인에 맞춰서
  /// 위치시키고, 여백엔드라인이라 여기 그려졌다는 암묵적인 표시용으로 라인을
  /// 빨간색이 아닌 여백 엔드라인색으로 그림」. A cut that owes のりしろ ends
  /// its sheet at the DRAWN end, in the のりしろ colour — ONE line, moved;
  /// the red one at the conte end is not kept beside it.
  void paintCutEndLine(Canvas canvas) {
    final frameCount = _painter.liveDrawnFrameCount;
    if (frameCount < 1 || frameCount > _painter.document.rowCount) {
      return;
    }
    final line = _painter.layout.cutEndLineFor(frameCount);
    final left = _painter.layout.halfLeft(line.page, line.half);
    canvas.drawLine(
      Offset(left, line.y),
      Offset(left + _painter.layout.halfWidth, line.y),
      Paint()
        // The のりしろ colour IS the accent ([AppColors.noriShiro]); the
        // painter reads the one it was built with, for the reason its
        // `accent` field gives.
        ..color = _owesNoriShiro ? _painter.accent : AppColors.danger
        ..strokeWidth = 2.4,
    );
  }

  /// Whether this paint's cut is drawn past its conte end — the one fact
  /// the end line's place and colour and the header's second length follow.
  bool get _owesNoriShiro =>
      _painter.liveDrawnFrameCount > _painter.livePlaybackFrameCount;

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
