part of '../timesheet_document_painter.dart';

/// A block of an XDTS sheet's body: its left, its columns and how wide
/// each is, and its width.
typedef _XdtsBlock = ({
  double left,
  int columns,
  double columnWidth,
  double width,
});

/// THE XDTS VIEWER'S FORM — its rules, its blocks' names, its frame and
/// second numbers, its half-second marks and its info header — drawn on the
/// page as the viewer draws it ([_XdtsPage]: its pixels, its words).
class _XdtsFormPass {
  _XdtsFormPass(this._page);

  final _XdtsPage _page;

  XdtsSheetForm get _form => _page.form;

  /// The viewer's pens: thin, thick — the body's outline is a thick one.
  static final Paint _thin = _pen(2);
  static final Paint _thick = _pen(5);

  static Paint _pen(double width) => Paint()
    ..color = _XdtsPage.line
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

  static int _px(double mm) => _XdtsPage.px(mm);

  /// A form word, [size] large, [across] its box from its top.
  static _XdtsWordsSet _mark(double size, TextAlign across) =>
      (size: size, color: _XdtsPage.line, across: across, middle: false);

  /// A form number, [size] large, right on its box's middle.
  static _XdtsWordsSet _number(double size) => (
    size: size,
    color: _XdtsPage.line,
    across: TextAlign.right,
    middle: true,
  );

  void _rule(Canvas canvas, Offset from, Offset to, Paint pen) =>
      canvas.drawLine(from, to, pen);

  /// Page [pageIndex]'s form: the info header, then each body.
  void paintPage(Canvas canvas, int pageIndex) =>
      _page.on(canvas, pageIndex, () {
        _paintInfoHeader(canvas);
        for (var body = 0; body < _form.template.bodyAmount; body += 1) {
          _paintBody(canvas, body, pageIndex);
        }
      });

  // ── the info header ────────────────────────────────────────────────

  /// Each box's walls, the rule under its label and the label spread over
  /// it — the first box's left wall and the last's right one, the top and
  /// the bottom in the outline's pen — and in the length's box and the
  /// sheet count's, the marks their values are written by.
  void _paintInfoHeader(Canvas canvas) {
    final top = _form.infoTop.toDouble();
    final middle = _form.infoTitleBottom.toDouble();
    final bottom = _form.infoBottom.toDouble();
    for (final (index, place) in _form.info.indexed) {
      final left = place.left.toDouble();
      final right = left + place.width;
      _rule(
        canvas,
        Offset(left, top),
        Offset(left, bottom),
        index == 0 ? _thick : _thin,
      );
      _rule(canvas, Offset(left, middle), Offset(right, middle), _thin);
      _rule(canvas, Offset(left, top), Offset(right, top), _thick);
      _rule(canvas, Offset(left, bottom), Offset(right, bottom), _thick);
      _page.spread(
        canvas,
        place.box.label,
        Rect.fromLTRB(left, top, right, middle),
        size: middle - top - _px(1),
      );
      final value = _page.valueBox(place);
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
    _rule(canvas, Offset(right, top), Offset(right, bottom), _thick);
  }

  /// The length's marks: 秒 over the seconds' half, コマ over the frames'
  /// and ＋ under it.
  void _paintTimeMarks(Canvas canvas, XdtsPixelRect box) {
    final size = _page.markSize(box, _plusWord, 12);
    final half = (box.width ~/ 2).toDouble();
    final rows = (box.height ~/ 2).toDouble();
    final left = box.left.toDouble();
    final top = box.top.toDouble();
    _page.words(
      canvas,
      _secondsWord,
      Rect.fromLTWH(left, top, half, rows),
      _mark(size, TextAlign.right),
    );
    _page.words(
      canvas,
      _framesWord,
      Rect.fromLTWH(left + half, top, half, rows - _px(0.5)),
      _mark(size, TextAlign.right),
    );
    _page.words(
      canvas,
      _plusWord,
      Rect.fromLTWH(left + half, top + rows, half, rows),
      _mark(size, TextAlign.left),
    );
  }

  /// The sheet count's marks: the stroke between its two numbers, and 枚 ·
  /// 枚目 by the one over and the one under — which is which the template
  /// says ([XdtsViewerSheet.totalOverCurrent]).
  void _paintSheetMarks(Canvas canvas, XdtsPixelRect box) {
    final right = box.left + box.width - 1;
    final bottom = box.top + box.height - 1;
    final centre = (box.left + right) ~/ 2;
    _rule(
      canvas,
      Offset(((right + centre) ~/ 2).toDouble(), box.top.toDouble()),
      Offset(((box.left + centre) ~/ 2).toDouble(), bottom.toDouble()),
      _thin,
    );
    final size = _page.markSize(box, _sheetsWord, 6);
    final half = (box.width ~/ 2).toDouble();
    final rows = (box.height ~/ 2).toDouble();
    final left = box.left.toDouble();
    final top = box.top.toDouble();
    final totalOver = _form.template.totalOverCurrent;
    _page.words(
      canvas,
      totalOver ? _sheetsWord : _sheetWord,
      Rect.fromLTWH(left, top, half, rows),
      _mark(size, TextAlign.right),
    );
    _page.words(
      canvas,
      totalOver ? _sheetWord : _sheetsWord,
      Rect.fromLTWH(left + half, top + rows, half - _px(0.5), rows),
      _mark(size, TextAlign.right),
    );
  }

  // ── a body ─────────────────────────────────────────────────────────

  double get _bodyTop => _form.bodyTop.toDouble();
  double get _bodyBottom => (_form.bodyTop + _form.bodyHeight).toDouble();
  double get _headMiddle => _bodyTop + _form.headerHeight ~/ 2;
  double get _headBottom => _bodyTop + _form.headerHeight;

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

  /// A wall down the whole body at [x].
  void _bodyWall(Canvas canvas, double x) =>
      _rule(canvas, Offset(x, _bodyTop), Offset(x, _bodyBottom), _thin);

  /// A rule across [block] at [y].
  void _across(Canvas canvas, _XdtsBlock block, double y, Paint pen) =>
      _rule(
        canvas,
        Offset(block.left, y),
        Offset(block.left + block.width, y),
        pen,
      );

  /// The first [count] of [block]'s walls, a column apart from its left,
  /// down [span].
  void _walls(
    Canvas canvas,
    _XdtsBlock block,
    int count,
    ({double top, double bottom}) span,
  ) {
    for (var wall = 1; wall <= count; wall += 1) {
      final x = block.left + wall * block.columnWidth;
      _rule(canvas, Offset(x, span.top), Offset(x, span.bottom), _thin);
    }
  }

  /// [block]'s head: the rule halving it, the thick rule closing it, and
  /// the walls between its columns in its lower half.
  void _paintHeadGrid(Canvas canvas, _XdtsBlock block) {
    _across(canvas, block, _headMiddle, _thin);
    _across(canvas, block, _headBottom, _thick);
    _walls(
      canvas,
      block,
      block.columns - 1,
      (top: _headMiddle, bottom: _headBottom),
    );
  }

  /// [block]'s rows: each row's rule, thick on every sixth, and a second's
  /// double rule — then [walls] walls a column apart down them.
  void _paintRowGrid(Canvas canvas, _XdtsBlock block, {required int walls}) {
    final rowsTop = _form.rowsTop.toDouble();
    for (var second = 0; second < XdtsSheetForm.bodySeconds; second += 1) {
      final secondTop = rowsTop + second * _form.secondHeight;
      for (var row = 1; row <= XdtsSheetForm.rowsPerSecond; row += 1) {
        final y = secondTop + row * _form.rowHeight;
        _across(canvas, block, y, row % 6 == 0 ? _thick : _thin);
      }
      _across(canvas, block, secondTop + _form.secondHeight, _thick);
    }
    final rowsBottom =
        rowsTop + XdtsSheetForm.bodySeconds * _form.secondHeight;
    _walls(canvas, block, walls, (top: rowsTop, bottom: rowsBottom));
  }

  /// Where [block] writes its name small: its head's upper half.
  Rect _upperHead(_XdtsBlock block) => Rect.fromLTRB(
    block.left,
    _bodyTop,
    block.left + block.width,
    _headMiddle,
  );

  double get _smallName => (_form.headerHeight ~/ 2 - _px(1)).toDouble();
  double get _largeName => (_form.headerHeight - _px(4)).toDouble();

  void _paintActionBlock(Canvas canvas, double left, int body, int page) {
    final block = (
      left: left,
      columns: _form.keyColumns,
      columnWidth: _form.keyColWidth.toDouble(),
      width: _form.keyBlockWidth.toDouble(),
    );
    _paintHeadGrid(canvas, block);
    if (_form.template.drawKeysHeaderLabel) {
      _page.spread(canvas, _actionWord, _upperHead(block), size: _smallName);
    }
    _paintRowGrid(canvas, block, walls: block.columns);
    _paintFrameNumbers(canvas, left, body, page);
    _bodyWall(canvas, left + block.width);
  }

  /// Every second row's frame number, the cut's count — in the column after
  /// the ACTION block's, or where a sheet keeps none, outside the body.
  void _paintFrameNumbers(Canvas canvas, double left, int body, int page) {
    final rowHeight = _form.rowHeight.toDouble();
    final inside = _form.lastKeyColWidth > 0;
    final numbersLeft = inside
        ? left + _form.keyColumns * _form.keyColWidth
        : left - 2 * _form.keyColWidth;
    final numbersWidth = inside
        ? _form.lastKeyColWidth - _px(0.5)
        : 2 * _form.keyColWidth - _px(0.5);
    final framesBefore =
        body * XdtsSheetForm.bodyRows + _form.template.frameLength * page;
    for (var second = 0; second < XdtsSheetForm.bodySeconds; second += 1) {
      final secondTop = _form.rowsTop + second * _form.secondHeight;
      for (var row = 2; row <= XdtsSheetForm.rowsPerSecond; row += 2) {
        _page.words(
          canvas,
          '${framesBefore + second * XdtsSheetForm.rowsPerSecond + row}',
          Rect.fromLTWH(
            numbersLeft,
            secondTop + (row - 1) * rowHeight,
            numbersWidth.toDouble(),
            rowHeight,
          ),
          _number(rowHeight - _px(2)),
        );
      }
    }
  }

  /// The dialogue column: its name as large as it fits, no rows, a
  /// half-second mark on its right wall in each second and the second's
  /// number by its end.
  void _paintDialogueColumn(Canvas canvas, double left, int body, int page) {
    final width = _form.dialogColWidth.toDouble();
    _page.words(
      canvas,
      _dialogueWord,
      Rect.fromLTRB(left, _bodyTop, left + width, _headBottom),
      (
        size: math.max(
          _page.fitSize(_dialogueWord, start: _largeName, room: width - _px(2)),
          _px(1).toDouble(),
        ),
        color: _XdtsPage.line,
        across: TextAlign.center,
        middle: true,
      ),
    );
    if (_form.template.drawDialogHeaderLine) {
      _rule(
        canvas,
        Offset(left, _headBottom),
        Offset(left + width, _headBottom),
        _thin,
      );
    }
    final rowHeight = _form.rowHeight.toDouble();
    final mark = Paint()..color = _XdtsPage.line;
    final secondsBefore =
        body * XdtsSheetForm.bodySeconds +
        page * _form.template.frameLength ~/ XdtsSheetForm.rowsPerSecond;
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
      _page.words(
        canvas,
        '${secondsBefore + second}',
        Rect.fromLTWH(
          left,
          secondTop + rowHeight * (last ? 23 : 23.5),
          width - _px(1),
          rowHeight,
        ),
        _number(rowHeight - _px(1.5)),
      );
    }
  }

  void _paintCellsBlock(Canvas canvas, double left) {
    final block = (
      left: left,
      columns: _form.cellsColumns,
      columnWidth: _form.cellsColWidth.toDouble(),
      width: _form.cellsBlockWidth.toDouble(),
    );
    _bodyWall(canvas, left);
    _paintHeadGrid(canvas, block);
    if (_form.template.drawCellsHeaderLabel) {
      _page.spread(canvas, _cellsWord, _upperHead(block), size: _smallName);
    }
    _paintRowGrid(canvas, block, walls: block.columns - 1);
    _bodyWall(canvas, left + block.width);
  }

  /// The camera block — its walls between the camera columns the sheet
  /// prints, the template's or the more a cut's instruction rows split it
  /// into ([TimesheetDocumentLayout.columnWidthFor]).
  void _paintCameraBlock(Canvas canvas, double left) {
    final template = _form.template;
    final layout = _page._painter.layout;
    final block = (
      left: left,
      columns: layout._columnCountOf(TimesheetColumnKind.camera),
      columnWidth:
          layout.columnWidthFor(TimesheetColumnKind.camera) / _page.sheet.unit,
      width: _form.cameraBlockWidth.toDouble(),
    );
    if (template.drawCameraHeaderGrid) {
      _paintHeadGrid(canvas, block);
      if (template.drawCameraHeaderLabel) {
        _page.spread(canvas, _cameraWord, _upperHead(block), size: _smallName);
      }
    } else {
      _across(canvas, block, _headBottom, _thick);
      if (template.drawCameraHeaderLabel) {
        _page.spread(
          canvas,
          _cameraWord,
          Rect.fromLTRB(left, _bodyTop, left + block.width, _headBottom),
          size: _largeName,
        );
      }
    }
    _paintRowGrid(canvas, block, walls: block.columns - 1);
  }
}
