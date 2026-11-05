part of '../timesheet_document_painter.dart';

/// THE XDTS VIEWER'S FORM — its rules, its blocks' names, its frame and
/// second numbers, its half-second marks and its info header — and the
/// length and the sheet count it writes in that header, as the viewer
/// draws them (I-162, 유저 2026-11-05: 「서식 바꾸면 xdts의 해당 서식에서
/// 보는거랑 똑같은 화면」).
///
/// 🚨IN THE VIEWER'S OWN PIXELS. Everything here is measured in the 250dpi
/// whole pixels [XdtsSheetForm] lays the page in, and the page is scaled to
/// the sheet's units once ([_XdtsSheetForm.unit]) — so a line lands where
/// the viewer's does, its pens two and five pixels wide.
///
/// ⛔The viewer's code is not ours to copy (BSD-3): what is kept is where
/// it draws and how large, read off its form; the drawing is our own.
///
/// ⚠️Mine: the form's words are the viewer's Japanese — its own language
/// by default, and the one these four sheets are made in (Ponoc's is a
/// Japanese studio's). Our notation language has no XDTS form to print in:
/// the viewer has Japanese and English only. Every word is set in the
/// app's face (documents-in-which-face-Q1), not the viewer's MS Gothic.
class _XdtsFormPass {
  _XdtsFormPass(this._painter, this._sheet);

  final TimesheetDocumentPainter _painter;
  final _XdtsSheetForm _sheet;

  XdtsSheetForm get _form => _sheet.form;

  /// The viewer's line colour, which its form's words are printed in too.
  static const Color _line = Color(0xFF9CC862);

  /// Its pens: thin, thick — the body's outline is a thick one.
  static final Paint _thin = _pen(2);
  static final Paint _thick = _pen(5);

  static Paint _pen(double width) => Paint()
    ..color = _line
    ..strokeWidth = width
    ..strokeCap = StrokeCap.butt
    ..strokeJoin = StrokeJoin.miter
    ..style = PaintingStyle.stroke;

  /// The blocks' names, the length's marks and the sheet count's.
  static const String _actionWord = 'アクション';
  static const String _dialogueWord = '台詞';
  static const String _cellsWord = 'セル';
  static const String _cameraWord = 'カメラ';
  static const String _secondsWord = '秒';
  static const String _framesWord = 'コマ';
  static const String _plusWord = '＋';
  static const String _sheetsWord = '枚';
  static const String _sheetWord = '枚目';

  static int _px(double mm) => XdtsSheetForm.px(mm);

  /// Runs [draw] in page [pageIndex]'s pixels.
  void _onPage(Canvas canvas, int pageIndex, void Function() draw) {
    final page = _painter.layout.pageRect(pageIndex);
    canvas
      ..save()
      ..translate(page.left, page.top)
      ..scale(_sheet.unit);
    draw();
    canvas.restore();
  }

  // ── the form ───────────────────────────────────────────────────────

  /// Page [pageIndex]'s form: the info header, then each body.
  void paintPage(Canvas canvas, int pageIndex) =>
      _onPage(canvas, pageIndex, () {
        _paintInfoHeader(canvas);
        for (var body = 0; body < _form.template.bodyAmount; body += 1) {
          _paintBody(canvas, body, pageIndex);
        }
      });

  void _rule(
    Canvas canvas,
    double x1,
    double y1,
    double x2,
    double y2,
    Paint pen,
  ) => canvas.drawLine(Offset(x1, y1), Offset(x2, y2), pen);

  /// The info header: each box's walls, the rule under its label and the
  /// label spread over it — the first box's left wall and the last's right
  /// one, the top and the bottom in the outline's pen — and in the length's
  /// box and the sheet count's, the marks their values are written by.
  void _paintInfoHeader(Canvas canvas) {
    final top = _form.infoTop.toDouble();
    final middle = _form.infoTitleBottom.toDouble();
    final bottom = _form.infoBottom.toDouble();
    for (final (index, place) in _form.info.indexed) {
      final left = place.left.toDouble();
      final right = left + place.width;
      _rule(canvas, left, top, left, bottom, index == 0 ? _thick : _thin);
      _rule(canvas, left, middle, right, middle, _thin);
      _rule(canvas, left, top, right, top, _thick);
      _rule(canvas, left, bottom, right, bottom, _thick);
      _spread(
        canvas,
        place.box.label,
        Rect.fromLTRB(left, top, right, middle),
        size: middle - top - _px(1),
      );
      final value = _valueBox(place);
      switch (place.box.field) {
        case TimesheetHeaderField.time:
          _paintTimeMarks(canvas, value);
        case TimesheetHeaderField.sheet:
          _paintSheetMarks(canvas, value);
        case _:
          break;
      }
    }
    final last = _form.info.last;
    final right = (last.left + last.width).toDouble();
    _rule(canvas, right, top, right, bottom, _thick);
  }

  /// The row a box's value is written in, under its label.
  ({int left, int top, int width, int height}) _valueBox(
    XdtsInfoPlace place,
  ) => (
    left: place.left,
    top: _form.infoTitleBottom,
    width: place.width,
    height: _form.infoBottom - _form.infoTitleBottom,
  );

  /// The length's marks: 秒 over the seconds' half, コマ over the frames'
  /// and ＋ under it, as large as lets ＋ stand within a twelfth of the box.
  void _paintTimeMarks(Canvas canvas, XdtsPixelRect box) {
    final half = box.width ~/ 2;
    final rows = box.height ~/ 2;
    final size = _fitSize(
      _plusWord,
      start: (rows - _px(1)).toDouble(),
      room: box.width / 12,
    );
    final left = box.left.toDouble();
    final top = box.top.toDouble();
    _words(
      canvas,
      _secondsWord,
      Rect.fromLTWH(left, top, half.toDouble(), rows.toDouble()),
      size: size,
      color: _line,
      across: TextAlign.right,
    );
    _words(
      canvas,
      _framesWord,
      Rect.fromLTWH(
        left + half,
        top,
        half.toDouble(),
        (rows - _px(0.5)).toDouble(),
      ),
      size: size,
      color: _line,
      across: TextAlign.right,
    );
    _words(
      canvas,
      _plusWord,
      Rect.fromLTWH(left + half, top + rows, half.toDouble(), rows.toDouble()),
      size: size,
      color: _line,
      across: TextAlign.left,
    );
  }

  /// The sheet count's marks: the stroke between its two numbers, and 枚 ·
  /// 枚目 by the one over and the one under — which is which the template
  /// says ([XdtsSheetTemplate.totalOverCurrent]).
  void _paintSheetMarks(Canvas canvas, XdtsPixelRect box) {
    final left = box.left;
    final top = box.top;
    final right = left + box.width - 1;
    final bottom = top + box.height - 1;
    final centre = (left + right) ~/ 2;
    _rule(
      canvas,
      ((right + centre) ~/ 2).toDouble(),
      top.toDouble(),
      ((left + centre) ~/ 2).toDouble(),
      bottom.toDouble(),
      _thin,
    );
    final half = box.width ~/ 2;
    final rows = box.height ~/ 2;
    final size = _fitSize(
      _sheetsWord,
      start: (rows - _px(1)).toDouble(),
      room: box.width / 6,
    );
    final totalOver = _form.template.totalOverCurrent;
    _words(
      canvas,
      totalOver ? _sheetsWord : _sheetWord,
      Rect.fromLTWH(
        left.toDouble(),
        top.toDouble(),
        half.toDouble(),
        rows.toDouble(),
      ),
      size: size,
      color: _line,
      across: TextAlign.right,
    );
    _words(
      canvas,
      totalOver ? _sheetWord : _sheetsWord,
      Rect.fromLTWH(
        (left + half).toDouble(),
        (top + rows).toDouble(),
        (half - _px(0.5)).toDouble(),
        rows.toDouble(),
      ),
      size: size,
      color: _line,
      across: TextAlign.right,
    );
  }

  /// One body of page [pageIndex]: its outline, then the ACTION block, the
  /// dialogue column, the CELL block and the camera block, left to right.
  void _paintBody(Canvas canvas, int body, int pageIndex) {
    final left = _form.bodyLeft(body).toDouble();
    canvas.drawRect(
      Rect.fromLTWH(
        left,
        _bodyTop,
        _form.bodyWidth.toDouble(),
        _form.bodyHeight.toDouble(),
      ),
      _thick,
    );
    _paintActionBlock(canvas, left, body, pageIndex);
    _paintDialogueColumn(canvas, left + _form.dialogLeft, body, pageIndex);
    _paintCellsBlock(canvas, left + _form.cellsLeft);
    _paintCameraBlock(canvas, left + _form.cameraLeft);
  }

  double get _bodyTop => _form.bodyTop.toDouble();
  double get _bodyBottom => (_form.bodyTop + _form.bodyHeight).toDouble();

  /// A block's head over [columns] columns [columnWidth] wide: the rule
  /// halving it, the thick rule closing it, and the walls between the
  /// columns in its lower half.
  void _paintHeadGrid(
    Canvas canvas,
    double left, {
    required int columns,
    required double columnWidth,
    required double width,
  }) {
    final middle = _bodyTop + _form.headerHeight ~/ 2;
    final bottom = _bodyTop + _form.headerHeight;
    _rule(canvas, left, middle, left + width, middle, _thin);
    _rule(canvas, left, bottom, left + width, bottom, _thick);
    for (var column = 1; column < columns; column += 1) {
      final x = left + column * columnWidth;
      _rule(canvas, x, middle, x, bottom, _thin);
    }
  }

  /// A block's rows: each row's rule, thick on every sixth, and a second's
  /// double rule — then [walls] walls, [columnWidth] apart, down them.
  void _paintRowGrid(
    Canvas canvas,
    double left, {
    required int walls,
    required double columnWidth,
    required double width,
  }) {
    final rowsTop = _form.rowsTop.toDouble();
    const perSecond = XdtsSheetForm.rowsPerSecond;
    for (var second = 0; second < XdtsSheetForm.bodySeconds; second += 1) {
      final secondTop = rowsTop + second * _form.secondHeight;
      for (var row = 1; row <= perSecond; row += 1) {
        final y = secondTop + row * _form.rowHeight;
        _rule(canvas, left, y, left + width, y, row % 6 == 0 ? _thick : _thin);
      }
      final y = secondTop + _form.secondHeight;
      _rule(canvas, left, y, left + width, y, _thick);
    }
    final rowsBottom =
        rowsTop + XdtsSheetForm.bodySeconds * _form.secondHeight;
    for (var wall = 1; wall <= walls; wall += 1) {
      final x = left + wall * columnWidth;
      _rule(canvas, x, rowsTop, x, rowsBottom, _thin);
    }
  }

  /// Where a block writes its name small: its head's upper half.
  Rect _upperHead(double left, double width) => Rect.fromLTWH(
    left,
    _bodyTop,
    width,
    (_form.headerHeight ~/ 2).toDouble(),
  );

  double get _smallName => (_form.headerHeight ~/ 2 - _px(1)).toDouble();
  double get _largeName => (_form.headerHeight - _px(4)).toDouble();

  void _paintActionBlock(Canvas canvas, double left, int body, int page) {
    final width = _form.keyBlockWidth.toDouble();
    final columnWidth = _form.keyColWidth.toDouble();
    _paintHeadGrid(
      canvas,
      left,
      columns: _form.keyColumns,
      columnWidth: columnWidth,
      width: width,
    );
    if (_form.template.drawKeysHeaderLabel) {
      _spread(canvas, _actionWord, _upperHead(left, width), size: _smallName);
    }
    _paintRowGrid(
      canvas,
      left,
      walls: _form.keyColumns,
      columnWidth: columnWidth,
      width: width,
    );
    _paintFrameNumbers(canvas, left, body, page);
    _rule(canvas, left + width, _bodyTop, left + width, _bodyBottom, _thin);
  }

  /// Every second row's frame number, the cut's count — in the column after
  /// the ACTION block's, or where a sheet keeps none, outside the body.
  void _paintFrameNumbers(Canvas canvas, double left, int body, int page) {
    final rowHeight = _form.rowHeight.toDouble();
    final size = rowHeight - _px(2);
    final inside = _form.lastKeyColWidth > 0;
    final numbersLeft = inside
        ? left + _form.keyColumns * _form.keyColWidth
        : left - 2 * _form.keyColWidth;
    final numbersWidth = inside
        ? _form.lastKeyColWidth - _px(0.5)
        : 2 * _form.keyColWidth - _px(0.5);
    for (var second = 0; second < XdtsSheetForm.bodySeconds; second += 1) {
      for (var row = 2; row <= XdtsSheetForm.rowsPerSecond; row += 2) {
        final frame =
            body * XdtsSheetForm.bodyRows +
            second * XdtsSheetForm.rowsPerSecond +
            row +
            _form.template.frameLength * page;
        _words(
          canvas,
          '$frame',
          Rect.fromLTWH(
            numbersLeft,
            _form.rowsTop + second * _form.secondHeight + (row - 1) * rowHeight,
            numbersWidth.toDouble(),
            rowHeight,
          ),
          size: size,
          color: _line,
          across: TextAlign.right,
          middle: true,
        );
      }
    }
  }

  /// The dialogue column: its name as large as it fits, no rows, a
  /// half-second mark on its right wall in each second and the second's
  /// number by its end.
  void _paintDialogueColumn(Canvas canvas, double left, int body, int page) {
    final width = _form.dialogColWidth.toDouble();
    final head = _form.headerHeight.toDouble();
    _words(
      canvas,
      _dialogueWord,
      Rect.fromLTWH(left, _bodyTop, width, head),
      size: math.max(
        _fitSize(_dialogueWord, start: _largeName, room: width - _px(2)),
        _px(1).toDouble(),
      ),
      color: _line,
      across: TextAlign.center,
      middle: true,
    );
    if (_form.template.drawDialogHeaderLine) {
      final y = _bodyTop + head;
      _rule(canvas, left, y, left + width, y, _thin);
    }
    final rowHeight = _form.rowHeight.toDouble();
    final mark = Paint()..color = _line;
    for (var second = 1; second <= XdtsSheetForm.bodySeconds; second += 1) {
      final secondTop =
          _form.rowsTop + (second - 1) * _form.secondHeight.toDouble();
      final point = Offset(left + width, secondTop + 12 * rowHeight);
      canvas.drawPath(
        Path()
          ..moveTo(point.dx - _px(0.8), point.dy)
          ..lineTo(point.dx - _px(2.8), point.dy + _px(1.25))
          ..lineTo(point.dx - _px(2.8), point.dy - _px(1.25))
          ..close(),
        mark,
      );
      final last = second == XdtsSheetForm.bodySeconds;
      final secondsBefore =
          body * XdtsSheetForm.bodySeconds +
          page * _form.template.frameLength ~/ XdtsSheetForm.rowsPerSecond;
      _words(
        canvas,
        '${secondsBefore + second}',
        Rect.fromLTWH(
          left,
          secondTop + rowHeight * (last ? 23 : 23.5),
          width - _px(1),
          rowHeight,
        ),
        size: rowHeight - _px(1.5),
        color: _line,
        across: TextAlign.right,
        middle: true,
      );
    }
  }

  void _paintCellsBlock(Canvas canvas, double left) {
    final width = _form.cellsBlockWidth.toDouble();
    final columnWidth = _form.cellsColWidth.toDouble();
    _rule(canvas, left, _bodyTop, left, _bodyBottom, _thin);
    _paintHeadGrid(
      canvas,
      left,
      columns: _form.cellsColumns,
      columnWidth: columnWidth,
      width: width,
    );
    if (_form.template.drawCellsHeaderLabel) {
      _spread(canvas, _cellsWord, _upperHead(left, width), size: _smallName);
    }
    _paintRowGrid(
      canvas,
      left,
      walls: _form.cellsColumns - 1,
      columnWidth: columnWidth,
      width: width,
    );
    _rule(canvas, left + width, _bodyTop, left + width, _bodyBottom, _thin);
  }

  /// The camera block — its walls between the camera columns the sheet
  /// prints, the template's or the more a cut's instruction rows split it
  /// into ([TimesheetDocumentLayout.columnWidthFor]).
  void _paintCameraBlock(Canvas canvas, double left) {
    final template = _form.template;
    final width = _form.cameraBlockWidth.toDouble();
    final columns = _painter.layout._columnCountOf(TimesheetColumnKind.camera);
    final columnWidth =
        _painter.layout.columnWidthFor(TimesheetColumnKind.camera) /
        _sheet.unit;
    if (template.drawCameraHeaderGrid) {
      _paintHeadGrid(
        canvas,
        left,
        columns: columns,
        columnWidth: columnWidth,
        width: width,
      );
      if (template.drawCameraHeaderLabel) {
        _spread(
          canvas,
          _cameraWord,
          _upperHead(left, width),
          size: _smallName,
        );
      }
    } else {
      final bottom = _bodyTop + _form.headerHeight;
      _rule(canvas, left, bottom, left + width, bottom, _thick);
      if (template.drawCameraHeaderLabel) {
        _spread(
          canvas,
          _cameraWord,
          Rect.fromLTWH(left, _bodyTop, width, _form.headerHeight.toDouble()),
          size: _largeName,
        );
      }
    }
    if (template.drawCameraGrid) {
      _paintRowGrid(
        canvas,
        left,
        walls: columns - 1,
        columnWidth: columnWidth,
        width: width,
      );
    }
  }

  // ── the values the viewer writes ───────────────────────────────────

  /// Whether the header box of [field] holds a value the viewer counts
  /// and writes its own way — the length and the sheet count.
  static bool counts(TimesheetHeaderField field) =>
      field == TimesheetHeaderField.time || field == TimesheetHeaderField.sheet;

  /// The value of [field]'s box on page [pageIndex] — the length in seconds
  /// and frames, or the sheet count — each number as large as its half of
  /// the box lets it be.
  void paintCount(Canvas canvas, TimesheetHeaderField field, int pageIndex) {
    for (final place in _form.info) {
      if (place.box.field != field) {
        continue;
      }
      final box = _valueBox(place);
      _onPage(canvas, pageIndex, () {
        switch (field) {
          case TimesheetHeaderField.time:
            _paintLength(canvas, box);
          case TimesheetHeaderField.sheet:
            _paintSheetCount(canvas, box, pageIndex);
          case _:
            break;
        }
      });
    }
  }

  /// The cut's length: its whole seconds over the left half — from a
  /// second on — and the frames past them over the right.
  void _paintLength(Canvas canvas, XdtsPixelRect box) {
    final frames = _painter.livePlaybackFrameCount;
    const perSecond = XdtsSheetForm.rowsPerSecond;
    final half = box.width ~/ 2;
    if (frames >= perSecond) {
      _fitted(
        canvas,
        '${frames ~/ perSecond}',
        Rect.fromLTWH(
          box.left.toDouble(),
          box.top.toDouble(),
          half.toDouble(),
          box.height.toDouble(),
        ),
        across: TextAlign.center,
      );
    }
    if (frames > 0) {
      _fitted(
        canvas,
        '${frames % perSecond}',
        Rect.fromLTWH(
          (box.left + half).toDouble(),
          box.top.toDouble(),
          half.toDouble(),
          box.height.toDouble(),
        ),
        across: TextAlign.center,
      );
    }
  }

  /// The sheets the cut fills, centred, and the one this is, from the
  /// left — over and under the stroke as the marks say.
  void _paintSheetCount(Canvas canvas, XdtsPixelRect box, int pageIndex) {
    final width = 3 * (box.width ~/ 8).toDouble();
    final height = (box.height ~/ 2 + _px(1)).toDouble();
    final over = Rect.fromLTWH(
      box.left.toDouble(),
      box.top.toDouble(),
      width,
      height,
    );
    final under = Rect.fromLTWH(
      (box.left + box.width ~/ 2).toDouble(),
      (box.top + box.height ~/ 2 - _px(1)).toDouble(),
      width,
      height,
    );
    final totalOver = _form.template.totalOverCurrent;
    _fitted(
      canvas,
      '${_painter.livePageCount}',
      totalOver ? over : under,
      across: TextAlign.center,
    );
    _fitted(
      canvas,
      '${pageIndex + 1}',
      totalOver ? under : over,
      across: TextAlign.left,
    );
  }

  // ── setting words ──────────────────────────────────────────────────

  /// The largest size up to [start] that sets [text] within [room] across,
  /// but never below the viewer's floor — the sheet's one shrinking law
  /// ([sheetWordsSize]).
  double _fitSize(
    String text, {
    required double start,
    required double room,
  }) {
    final size = sheetWordsSize(
      SheetWords(
        SheetPaintLayer.form,
        text: text,
        slot: Rect.fromLTWH(0, 0, room, start),
        size: start,
        argb: _line.toARGB32(),
        fit: SheetWordsFit.shrink,
      ),
      (size, {required bold, required color}) =>
          TimesheetDocumentPainter.wordsStyle(
            _painter.face,
            fontSize: size,
            color: color,
            bold: bold,
          ),
    );
    return math.max(size, _px(2).toDouble());
  }

  /// A value as the viewer fits it: from its box's height down, until it
  /// stands within the box less a margin — vertically centred.
  void _fitted(
    Canvas canvas,
    String text,
    Rect box, {
    required TextAlign across,
  }) => _words(
    canvas,
    text,
    box,
    size: _fitSize(
      text,
      start: box.height - _px(0.5),
      room: box.width - _px(1),
    ),
    color: TimesheetDocumentPainter._ink,
    across: across,
    middle: true,
  );

  /// [text] set [size] large in [box]: [across] it, and from its top or
  /// on its middle.
  void _words(
    Canvas canvas,
    String text,
    Rect box, {
    required double size,
    required Color color,
    required TextAlign across,
    bool middle = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TimesheetDocumentPainter.wordsStyle(
          _painter.face,
          fontSize: size,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final x = switch (across) {
      TextAlign.right || TextAlign.end => box.right - painter.width,
      TextAlign.center => box.center.dx - painter.width / 2,
      _ => box.left,
    };
    final y = middle ? box.center.dy - painter.height / 2 : box.top;
    painter
      ..paint(canvas, Offset(x, y))
      ..dispose();
  }

  /// A block's or a box's name spread over [box] as the viewer spreads it:
  /// its letters a letter's width apart — or two, where the box has room —
  /// centred; too tight for either, set as it is.
  void _spread(Canvas canvas, String text, Rect box, {required double size}) {
    final style = TimesheetDocumentPainter.wordsStyle(
      _painter.face,
      fontSize: size,
      color: _line,
    );
    TextPainter set(String letters) => TextPainter(
      text: TextSpan(text: letters, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final letters = text.characters.toList();
    final glyphs = [for (final letter in letters) set(letter)];
    final step = set('A');
    final gap = step.width;
    step.dispose();
    var natural = 0.0;
    for (final glyph in glyphs) {
      natural += glyph.width;
    }
    final gaps = letters.length - 1;
    final once = natural + gap * gaps;
    final twice = natural + 2 * gap * gaps;
    final spread = gaps <= 0 || box.width - 2 * gap <= once
        ? natural
        : box.width - 4 * gap > twice
        ? twice
        : once;
    final between = gaps <= 0 ? 0.0 : (spread - natural) / gaps;
    var x = box.center.dx - spread / 2;
    for (final glyph in glyphs) {
      glyph.paint(canvas, Offset(x, box.center.dy - glyph.height / 2));
      x += glyph.width + between;
      glyph.dispose();
    }
  }
}
