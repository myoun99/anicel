part of 'cel_text_layout.dart';

/// A text's letters SET IN COLUMNS (縦書き) — top to bottom, the columns
/// from the right to the left.
///
/// 🗣️유저 2026-10-06 (R9-rest, of vertical writing): 「권장대로. 다만 어차피
/// 타임시트나 x시트에서 가로쓰기/세로표기같은거 한거 많으니 **그거
/// 통합하면서** 진행해도될듯」. So WHAT each letter does in a column — turn,
/// lean into its corner, pair up as digits, lie down as a Latin word — is
/// the app's one table (`vertical_writing.dart`, [verticalTextCells]), and
/// HOW a cell is drawn is the one renderer the sheets draw through
/// ([paintVerticalTextCell], [verticalGlyphFit]). Nothing of either is
/// written again here: this places the cells and answers where they are.
///
/// 🧭THE SAME FRAME AS LINES, READ THE OTHER WAY. The origin is the anchor
/// and the block hangs from it — its TOP RIGHT corner for a box, whose
/// columns run [CelTextContent.wrapWidth] long; and for a text that grows,
/// the point its columns are set about: their top, their middle or their
/// bottom as [CelTextContent.align] says (left · centre · right, read down
/// the column), at the first column's right.
///
/// ⚠️ONE PAINTER A CELL, A PASS. A cell is drawn turned, shifted or scaled
/// on its own, so the engine's one paragraph cannot hold them. A text on a
/// cel is short; what that costs on a long one is not measured.
class _ColumnsSetting implements _TextSetting {
  factory _ColumnsSetting(
    CelTextContent content,
    TextLetterStyle nextLetterStyle,
  ) {
    final cells = _columnCellsOf(content);
    final letters = CanvasLetterPasses<List<TextPainter>>.of(
      [for (final span in content.spans) span.style],
      (paintOf) => [
        for (final cell in cells) _cellPainter(cell, paintOf(cell.style)),
      ],
      letGo: (painters) {
        for (final painter in painters) {
          painter.dispose();
        }
      },
    );
    for (final (index, cell) in cells.indexed) {
      cell.measure(letters.fill[index]);
    }
    final columns = _columnsOf(content, cells, nextLetterStyle);
    return _ColumnsSetting._(
      cells,
      columns,
      letters,
      _placed(content, columns),
    );
  }

  _ColumnsSetting._(this._cells, this._columns, this._letters, this.block);

  /// Every cell of the text, in reading order.
  final List<_ColumnCell> _cells;

  /// The columns, first — rightmost — to last.
  final List<_Column> _columns;

  /// The cells' painters, pass by pass: one a cell, in [_cells]' order.
  final CanvasLetterPasses<List<TextPainter>> _letters;

  /// The columns' block: as long as the longest column — or as the box, for
  /// a text that wraps — and as wide as its columns.
  @override
  final ui.Rect block;

  @override
  void paintBoxBehind(ui.Canvas canvas, ui.Rect box, int argb) =>
      _letters.paintBoxBehind(canvas, box, argb);

  @override
  void paint(ui.Canvas canvas, {required ui.Rect within}) => _letters.paint(
    canvas,
    within: within,
    draw: (painters) {
      for (final (index, cell) in _cells.indexed) {
        paintVerticalTextCell(
          canvas,
          cell.cell,
          painter: painters[index],
          center: cell.centre,
          fontSize: cell.style.fontSize,
          // A cel is paper: its letters are set for its own pixels, never
          // drawn from a bake made for the screen's.
          setWord: paintScaledText,
        );
      }
    },
  );

  /// A hairline ACROSS its column — or, between the two digits of a pair
  /// set side by side, down their cell.
  @override
  ui.Rect caretRect(TextPosition position) {
    final offset = position.offset;
    for (final column in _columns) {
      if (offset < column.start || offset > column.end) {
        continue;
      }
      // ⚠️Where a column ended for want of room, its last place IS the
      // next one's first: the caret stands at the head of the next.
      if (offset == column.end && column.wrapped) {
        continue;
      }
      for (final cell in column.cells) {
        if (offset >= cell.start && offset < cell.end) {
          return cell.caretAt(offset, _fillOf(cell));
        }
      }
      return ui.Rect.fromLTWH(column.left, column.endsAt, column.width, 0);
    }
    final last = _columns.last;
    return ui.Rect.fromLTWH(last.left, last.endsAt, last.width, 0);
  }

  /// One box per cell the letters run over — the whole of its place down
  /// the column, or of a word lying down, the part the letters take.
  @override
  List<ui.Rect> selectionRects(int start, int end) => [
    for (final cell in _cells)
      if (cell.start < end && cell.end > start)
        cell.spanOf(
          math.max(start, cell.start),
          math.min(end, cell.end),
          _fillOf(cell),
        ),
  ];

  /// To the RIGHT of the letters, as a column's side line is drawn (傍線).
  @override
  List<CelTextMark> marksBeside(int start, int end) => [
    for (final rect in selectionRects(start, end))
      (from: rect.topRight, to: rect.bottomRight),
  ];

  @override
  TextPosition positionAt(ui.Offset local) {
    final column = _columnAt(local.dx);
    for (final cell in column.cells) {
      if (local.dy < cell.room.bottom) {
        return TextPosition(offset: cell.placeAt(local, _fillOf(cell)));
      }
    }
    return TextPosition(
      offset: column.end,
      // The end of a column that ran out of room is the head of the next:
      // said upstream, it is this column's.
      affinity: column.wrapped ? TextAffinity.upstream : TextAffinity.downstream,
    );
  }

  /// The column [x] is in — the nearest, for a point beside them all.
  _Column _columnAt(double x) {
    for (final column in _columns) {
      if (x >= column.left) {
        return column;
      }
    }
    return _columns.last;
  }

  TextPainter _fillOf(_ColumnCell cell) => _letters.fill[cell.index];

  @override
  List<int> get wrapPlaces => [
    for (final column in _columns)
      if (column.wrapped) column.end,
  ];

  @override
  void dispose() => _letters.dispose();
}

/// One cell of a text set in columns: what the table makes of its letters
/// ([cell]), which letters they are, the style they wear — and, once
/// measured and placed, where it stands.
class _ColumnCell {
  _ColumnCell({
    required this.index,
    required this.cell,
    required this.start,
    required this.style,
  });

  /// Its place among the text's cells — and so among each pass's painters.
  final int index;

  final VerticalTextCell cell;

  /// Where its letters begin in the text.
  final int start;

  final TextLetterStyle style;

  /// Where its letters end in the text.
  int get end => start + cell.text.length;

  /// Whether it is white space — which hangs past a column's end and is no
  /// reason to break one.
  bool get isSpace => cell.text.trim().isEmpty;

  /// Whether its glyph lies down the column, and the scale that fits it
  /// across ([verticalGlyphFit]).
  late final ({bool turned, double scale}) _fit;

  /// How far its glyph reaches down the column ([verticalGlyphAdvance]).
  late final double _glyphAdvance;

  /// How far it moves the next cell down the column: its glyph, and the
  /// tracking after it. (A word lying down is tracked letter by letter by
  /// its own painter.)
  double get advance => math.max(0, _glyphAdvance + _trackingAfter);

  double get _trackingAfter =>
      cell.form == VerticalGlyphForm.sideways ? 0 : style.letterSpacing;

  void measure(TextPainter fill) {
    _fit = verticalGlyphFit(cell, painter: fill, fontSize: style.fontSize);
    _glyphAdvance = verticalGlyphAdvance(
      turned: _fit.turned,
      painter: fill,
      fontSize: style.fontSize,
      scale: _fit.scale,
    );
  }

  /// Its place in the text's own frame: as wide as its column, as long as
  /// its [advance].
  late final ui.Rect room;

  /// Where its glyph is centred ([paintVerticalTextCell]).
  ui.Offset get centre =>
      ui.Offset(room.center.dx, room.top + _glyphAdvance / 2);

  /// How far down the cell the place [offset] stands, for a cell whose
  /// letters run ALONG the column — a word lying down, or one glyph.
  double _downTo(int offset, TextPainter fill) {
    if (offset >= end) {
      return _glyphAdvance;
    }
    if (offset <= start || !_fit.turned) {
      return 0;
    }
    return fill
            .getOffsetForCaret(TextPosition(offset: offset - start), ui.Rect.zero)
            .dx *
        _fit.scale;
  }

  /// How far across the cell the place [offset] stands, for the digits of
  /// a pair set side by side.
  double _acrossTo(int offset, TextPainter fill) {
    final width = fill.width * _fit.scale;
    final from = room.center.dx - width / 2;
    return from +
        fill
                .getOffsetForCaret(
                  TextPosition(offset: offset - start),
                  ui.Rect.zero,
                )
                .dx *
            _fit.scale;
  }

  bool get _sideBySide => cell.form == VerticalGlyphForm.tateChuYoko;

  /// The caret at [offset] — a place inside this cell, or at its head.
  ui.Rect caretAt(int offset, TextPainter fill) {
    if (_sideBySide && offset > start) {
      return ui.Rect.fromLTWH(
        _acrossTo(offset, fill),
        room.top,
        0,
        _glyphAdvance,
      );
    }
    return ui.Rect.fromLTWH(
      room.left,
      room.top + _downTo(offset, fill),
      room.width,
      0,
    );
  }

  /// The part of its place the letters from [from] up to [to] take.
  ui.Rect spanOf(int from, int to, TextPainter fill) {
    if (from <= start && to >= end) {
      return room;
    }
    if (_sideBySide) {
      return ui.Rect.fromLTRB(
        from <= start ? room.left : _acrossTo(from, fill),
        room.top,
        to >= end ? room.right : _acrossTo(to, fill),
        room.bottom,
      );
    }
    return ui.Rect.fromLTRB(
      room.left,
      room.top + _downTo(from, fill),
      room.right,
      to >= end ? room.bottom : room.top + _downTo(to, fill),
    );
  }

  /// The place between letters nearest [local], a point in this cell.
  int placeAt(ui.Offset local, TextPainter fill) {
    if (end - start == 1) {
      return local.dy < room.top + advance / 2 ? start : end;
    }
    final inPainter = _sideBySide
        ? ui.Offset(
            (local.dx - (room.center.dx - fill.width * _fit.scale / 2)) /
                _fit.scale,
            fill.height / 2,
          )
        : ui.Offset((local.dy - room.top) / _fit.scale, fill.height / 2);
    return start + fill.getPositionForOffset(inPainter).offset;
  }
}

/// One column: its cells, the letters it runs from and to, and — once
/// placed — where it stands.
class _Column {
  _Column({
    required this.cells,
    required this.start,
    required this.end,
    required this.wrapped,
    required this.width,
  });

  final List<_ColumnCell> cells;

  /// The first place of the column, and the last: the place before the
  /// break that ended it, or the text's end.
  final int start;
  final int end;

  /// Whether it ended for want of ROOM, and not at a break that was typed
  /// or the text's end.
  final bool wrapped;

  /// How wide it is: the pitch of its largest letter.
  final double width;

  /// How far its cells run down it.
  double get length => cells.fold(0, (sum, cell) => sum + cell.advance);

  /// Its left edge, and where its last cell ends, in the text's own frame.
  late final double left;
  late final double endsAt;
}

/// [content]'s letters as the cells of its columns, in reading order: each
/// run through the app's table on its own ([verticalTextCells]), so a cell
/// wears one style — and the breaks typed into it left out, which are no
/// cell's letters.
List<_ColumnCell> _columnCellsOf(CelTextContent content) {
  final cells = <_ColumnCell>[];
  var at = 0;
  for (final span in content.spans) {
    for (final (index, piece) in span.text.split('\n').indexed) {
      if (index > 0) {
        at += 1;
      }
      var within = 0;
      for (final cell in verticalTextCells(
        piece,
      ).expand(verticalCellWordByWord)) {
        cells.add(
          _ColumnCell(
            index: cells.length,
            cell: cell,
            start: at + within,
            style: span.style,
          ),
        );
        within += cell.text.length;
      }
      at += piece.length;
    }
  }
  return cells;
}

/// One cell's letters set for one pass: at the size of their style, in a
/// line box one letter tall — what [paintVerticalTextCell] centres.
TextPainter _cellPainter(_ColumnCell cell, ui.Paint? foreground) => TextPainter(
  text: TextSpan(
    text: cell.cell.text,
    style: canvasLetterTextStyle(
      cell.style,
      lineHeight: 1,
      foreground: foreground,
    ).copyWith(letterSpacing: cell.cell.form == VerticalGlyphForm.sideways
        ? cell.style.letterSpacing
        : 0),
  ),
  textDirection: TextDirection.ltr,
  maxLines: 1,
)..layout();

/// [cells] — measured — broken into columns: at every break typed into
/// [content], and for a box wherever the next cells would run past its
/// length.
///
/// ★WHERE A COLUMN MAY BREAK IS THE TABLE'S ([verticalMayBreakBetween]): a
/// closing bracket or a full stop does not head a column and an opening
/// bracket does not end one — what the engine keeps to on a line. Cells
/// that may not part go to the next column together; white space hangs
/// past a column's end rather than head the next.
List<_Column> _columnsOf(
  CelTextContent content,
  List<_ColumnCell> cells,
  TextLetterStyle nextLetterStyle,
) {
  final text = content.text;
  final limit = content.wrapWidth;
  final pitch = content.lineHeight;
  final columns = <_Column>[];
  var next = 0;

  /// The style a column with no cell is as wide as: the letters at [place]
  /// — the break that opened it, or what will be typed there.
  TextLetterStyle lettersAt(int place) {
    var at = 0;
    for (final span in content.spans) {
      at += span.text.length;
      if (place < at || (place == at && place > 0)) {
        return span.style;
      }
    }
    return content.isEmpty ? nextLetterStyle : content.spans.last.style;
  }

  void close(List<_ColumnCell> column, int start, int end, bool wrapped) {
    final largest = column.isEmpty
        ? lettersAt(start).fontSize
        : column.fold<double>(
            0,
            (size, cell) => math.max(size, cell.style.fontSize),
          );
    columns.add(
      _Column(
        cells: column,
        start: start,
        end: end,
        wrapped: wrapped,
        width: largest * pitch,
      ),
    );
  }

  var paragraphStart = 0;
  for (final paragraph in text.split('\n')) {
    final paragraphEnd = paragraphStart + paragraph.length;
    var column = <_ColumnCell>[];
    var columnStart = paragraphStart;
    var length = 0.0;
    while (next < cells.length && cells[next].start < paragraphEnd) {
      // The cells from here that may not part.
      var unitEnd = next + 1;
      while (unitEnd < cells.length &&
          cells[unitEnd].start < paragraphEnd &&
          !verticalMayBreakBetween(
            cells[unitEnd - 1].cell.text,
            cells[unitEnd].cell.text,
          )) {
        unitEnd += 1;
      }
      final unit = cells.sublist(next, unitEnd);
      // White space at its end hangs, and is not what has to fit.
      var fits = 0.0;
      var run = 0.0;
      for (final cell in unit) {
        run += cell.advance;
        if (!cell.isSpace) {
          fits = run;
        }
      }
      if (limit != null && column.isNotEmpty && length + fits > limit) {
        close(column, columnStart, unit.first.start, true);
        column = [];
        columnStart = unit.first.start;
        length = 0;
      }
      column.addAll(unit);
      length += run;
      next = unitEnd;
    }
    close(column, columnStart, paragraphEnd, false);
    paragraphStart = paragraphEnd + 1;
  }
  return columns;
}

/// Places [columns] — and their cells — in the text's own frame, and
/// answers their block.
ui.Rect _placed(CelTextContent content, List<_Column> columns) {
  final width = columns.fold<double>(0, (sum, column) => sum + column.width);
  final longest = columns.fold<double>(
    0,
    (length, column) => math.max(length, column.length),
  );
  final limit = content.wrapWidth;
  final height = limit ?? longest;
  // A box hangs from its anchor; a text that grows stands about it.
  final top = limit != null
      ? 0.0
      : switch (content.align) {
          TextCelAlign.left => 0.0,
          TextCelAlign.center => -height / 2,
          TextCelAlign.right => -height,
        };
  var right = 0.0;
  for (final column in columns) {
    column.left = right - column.width;
    final room = height - column.length;
    var down =
        top +
        switch (content.align) {
          TextCelAlign.left => 0.0,
          TextCelAlign.center => room / 2,
          TextCelAlign.right => room,
        };
    for (final cell in column.cells) {
      cell.room = ui.Rect.fromLTWH(
        column.left,
        down,
        column.width,
        cell.advance,
      );
      down += cell.advance;
    }
    column.endsAt = down;
    right = column.left;
  }
  return ui.Rect.fromLTWH(-width, top, width, height);
}
