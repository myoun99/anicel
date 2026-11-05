part of '../timesheet_document_painter.dart';

/// Whether an XDTS sheet writes [column] in the viewer's notation: a row of
/// the ACTION or the CELL block — a track the viewer reads.
bool _xdtsViewerWrites(TimesheetColumn column) =>
    column.layerId != null &&
    (column.kind == TimesheetColumnKind.action ||
        column.kind == TimesheetColumnKind.cel);

/// A column as the viewer writes it: the values it reads
/// ([xdtsViewerFramesOf]) and its notation of them.
typedef _XdtsViewerColumn = ({
  List<Object?> frames,
  XdtsViewerNotation notation,
});

/// The last notation read of a list of cells, and what it was read for.
final Expando<
  ({int duration, int pageFrames, bool keyBlock, _XdtsViewerColumn read})
>
_xdtsViewerReads = Expando('the XDTS viewer notation of a column');

/// [cells] of a column of [kind] as the viewer writes them, [duration]
/// frames long on pages of [pageFrames] — read again only when one of
/// them changes: a drag re-derives the one column it moves.
_XdtsViewerColumn _xdtsViewerColumn(
  List<TimesheetCell> cells, {
  required TimesheetColumnKind kind,
  required int duration,
  required int pageFrames,
}) {
  final keyBlock = kind == TimesheetColumnKind.action;
  final kept = _xdtsViewerReads[cells];
  if (kept != null &&
      kept.duration == duration &&
      kept.pageFrames == pageFrames &&
      kept.keyBlock == keyBlock) {
    return kept.read;
  }
  final frames = xdtsViewerFramesOf(cells, duration: duration);
  final read = (
    frames: frames,
    notation: xdtsViewerNotation(
      frames,
      keyBlock: keyBlock,
      pageFrames: pageFrames,
    ),
  );
  _xdtsViewerReads[cells] = (
    duration: duration,
    pageFrames: pageFrames,
    keyBlock: keyBlock,
    read: read,
  );
  return read;
}

/// One half of a page as a column's notation is written down it: its rows,
/// the frame the first prints, and how many it holds.
///
/// ⛔ONE answer for the paint and the drag print ([timesheetDragPrint]), as
/// [_columnRows] is for every other column.
class _XdtsHalf {
  const _XdtsHalf(
    this.rows, {
    required this.startFrame,
    required this.rowCount,
  });

  final TimesheetRows rows;
  final int startFrame;
  final int rowCount;

  /// The rows a paint over [shown] writes: those it reaches, short of the
  /// [duration]th frame — none on a half past it.
  (int, int) written(Rect? shown, int duration) {
    final (first, last) = rows.reached(shown, rowCount);
    final to = math.min(last, (duration - startFrame).clamp(0, rowCount));
    return (math.min(first, to), to);
  }

  /// Whether [frame] is one of this half's.
  bool holds(int frame) =>
      frame >= startFrame && frame < startFrame + rowCount;

  /// What a paint over [shown] writes of [read]: the values and the inks of
  /// the rows it writes, and the words that stand on this half.
  Object printOf(_XdtsViewerColumn read, Rect? shown, int duration) {
    final (from, to) = written(shown, duration);
    List<T> rowsOf<T>(List<T> frames) => from < to
        ? frames.sublist(startFrame + from, startFrame + to)
        : <T>[];
    return (
      startFrame + from,
      ByList(rowsOf(read.frames)),
      ByList(rowsOf(read.notation.inks)),
      ByList([
        for (final word in read.notation.words)
          if (holds(word.frame)) word,
      ]),
    );
  }
}

/// THE XDTS VIEWER'S NOTATION, ON AN XDTS SHEET (I-162-Q1, 유저 2026-11-05:
/// 「XDTS 서식에서만 뷰어 표기」 — 「일단 최대한 서식대로 보여주는게 목표.
/// 보이는그대로 출력이 목표니까」): the ACTION and CELL blocks' rows as the
/// viewer writes them ([xdtsViewerNotation]) — a value where it is written,
/// the line it lasts down, the null cell's × and its wave, a repeat's blue
/// value and dashes, 止メ and リピート — and each column's end mark under
/// its last frame.
///
/// ⛔The viewer's code is not ours to copy (BSD-3): what is kept is where
/// it draws, how large and in what pen (`drawXsheetContents` and the
/// primitives it calls, xdts_viewer v1.3.0); the drawing is our own.
///
/// ⚠️Mine: a value too wide for its cell shrinks by the sheet's one law
/// ([_XdtsPage.fitSize]) where the viewer squeezes it across, and a mark is
/// our own ○ ● (I-162-Q6) where the viewer draws its tick. The words are
/// the viewer's Japanese, as the form's are ([_XdtsPage]).
class _XdtsNotationPass {
  _XdtsNotationPass(this._page);

  final _XdtsPage _page;

  TimesheetDocumentPainter get _painter => _page._painter;

  XdtsSheetForm get _form => _page.form;

  /// The viewer's 止メ and リピート — its long sound a bar, set downwards.
  static const String _holdWord = '止メ';
  static const String _repeatWord = 'リピ|ト';

  /// Where a repeat starts its next round, and the dashes it lasts down in.
  static const Color _blue = Color(0xFF0000FF);

  double _at(num pixels) => pixels * _page.sheet.unit;

  /// The viewer's pen for the cells: half a millimetre, cut square.
  late final Paint _pen = Paint()
    ..color = TimesheetDocumentPainter._ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = _at(_XdtsPage.px(0.5))
    ..strokeCap = StrokeCap.butt;

  /// The size a value and a word are set at: a row less a millimetre.
  late final int _letterPixels = _form.rowHeight - _XdtsPage.px(1);

  /// [read] written on [half], in the column [box] spans across.
  void paintColumn(
    Canvas canvas,
    _XdtsViewerColumn read,
    _XdtsHalf half,
    ({double left, double width}) box,
  ) {
    Rect cellOf(int frame) {
      final row = frame - half.startFrame;
      return Rect.fromLTRB(
        box.left,
        half.rows.topOf(row),
        box.left + box.width,
        half.rows.bottomOf(row),
      );
    }

    final duration = _painter.liveDrawnFrameCount;
    final (from, to) = half.written(_painter._cull, duration);
    for (var row = from; row < to; row += 1) {
      final frame = half.startFrame + row;
      _paintRow(canvas, read, frame, cellOf(frame));
    }
    // Over the rows, on white, as the viewer sets them after the column.
    for (final word in read.notation.words) {
      if (half.holds(word.frame)) {
        _paintWord(
          canvas,
          word.repeat ? _repeatWord : _holdWord,
          cellOf(word.frame),
        );
      }
    }
    if (half.holds(duration - 1)) {
      _paintEndMark(canvas, cellOf(duration - 1));
    }
  }

  void _paintRow(
    Canvas canvas,
    _XdtsViewerColumn read,
    int frame,
    Rect cell,
  ) {
    switch (read.notation.inks[frame]) {
      case XdtsViewerInk.none:
        break;
      case XdtsViewerInk.value:
        _paintValue(canvas, read.frames[frame], cell, blue: false);
      case XdtsViewerInk.repeatValue:
        _paintValue(canvas, read.frames[frame], cell, blue: true);
      case XdtsViewerInk.line:
        canvas.drawLine(cell.topCenter, cell.bottomCenter, _pen);
      case XdtsViewerInk.wave:
        canvas.drawPath(_waveIn(cell), _pen);
      case XdtsViewerInk.repeat:
        _paintDashes(canvas, cell);
    }
  }

  /// A frame's [value]: its mark, its number on the row's middle — or the
  /// null cell's ×, corner to corner. In [blue], the pen the viewer takes
  /// for it is a pixel wide.
  void _paintValue(
    Canvas canvas,
    Object? value,
    Rect cell, {
    required bool blue,
  }) {
    switch (value) {
      case final InbetweenMark mark:
        _painter._cells._paintMark(canvas, cell.center, mark);
      case final String number:
        final size = _page.fitSize(
          number,
          start: _letterPixels.toDouble(),
          room: cell.width / _page.sheet.unit - 1,
        );
        _page.words(canvas, number, cell, (
          size: _at(size),
          color: blue ? _blue : TimesheetDocumentPainter._ink,
          across: TextAlign.center,
          middle: true,
        ));
      case _:
        final pen = blue
            ? (Paint()
                ..color = _blue
                ..strokeWidth = _at(1))
            : _pen;
        canvas
          ..drawLine(cell.topLeft, cell.bottomRight, pen)
          ..drawLine(cell.topRight, cell.bottomLeft, pen);
    }
  }

  /// The wave a null cell lasts down: from the row's top to its bottom on
  /// its middle, bowed a quarter of the row left then right.
  Path _waveIn(Rect cell) {
    final bow = _at(_form.rowHeight ~/ 4);
    final x = cell.center.dx;
    return Path()
      ..moveTo(x, cell.top)
      ..cubicTo(
        x - bow,
        cell.top + bow,
        x + bow,
        cell.bottom - bow,
        x,
        cell.bottom,
      );
  }

  /// A repeat's line down [cell], in blue dashes four pens long with two
  /// between — from the row's top, each row anew.
  void _paintDashes(Canvas canvas, Rect cell) {
    final pen = Paint()
      ..color = _blue
      ..strokeWidth = _pen.strokeWidth
      ..strokeCap = StrokeCap.butt;
    final dash = 4 * pen.strokeWidth;
    final gap = 2 * pen.strokeWidth;
    final x = cell.center.dx;
    for (var top = cell.top; top < cell.bottom; top += dash + gap) {
      canvas.drawLine(
        Offset(x, top),
        Offset(x, math.min(top + dash, cell.bottom)),
        pen,
      );
    }
  }

  /// [word] set downwards a letter a line from the top of [cell], on its
  /// middle, over a white ground as wide and as tall as the letters.
  void _paintWord(Canvas canvas, String word, Rect cell) {
    final letters = TextPainter(
      text: TextSpan(
        text: word.characters.join('\n'),
        style: TimesheetDocumentPainter.wordsStyle(
          _painter.face,
          fontSize: _at(_letterPixels),
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    final ground = Rect.fromLTWH(
      cell.center.dx - letters.width / 2,
      cell.top,
      letters.width,
      letters.height,
    );
    canvas.drawRect(ground, Paint()..color = TimesheetDocumentPainter._paper);
    letters
      ..paint(canvas, ground.topLeft)
      ..dispose();
  }

  /// The end mark under [last], the column's last frame: a line across the
  /// row below's top in the cells' pen, and three light hatches down it —
  /// from its top's middle to its left's, corner to corner, and from its
  /// right's middle to its bottom's.
  void _paintEndMark(Canvas canvas, Rect last) {
    final below = last.shift(Offset(0, last.height));
    final hatch = Paint()
      ..color = TimesheetDocumentPainter._ink.withAlpha(128)
      ..strokeWidth = _at(_XdtsPage.px(0.2))
      ..strokeCap = StrokeCap.butt;
    canvas
      ..drawLine(below.topLeft, below.topRight, _pen)
      ..drawLine(below.topCenter, below.centerLeft, hatch)
      ..drawLine(below.topRight, below.bottomLeft, hatch)
      ..drawLine(below.centerRight, below.bottomCenter, hatch);
  }
}
