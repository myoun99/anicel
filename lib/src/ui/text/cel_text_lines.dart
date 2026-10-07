part of 'cel_text_layout.dart';

/// A text's letters SET IN LINES — left to right, the lines down the page:
/// the engine's own paragraph, one painter a pass.
///
/// ↩️This was the whole of `CelTextLayout` until a text could also be set in
/// columns (2026-10-07). It moved as it was.
class _LinesSetting implements _TextSetting {
  factory _LinesSetting(
    CelTextContent content,
    CanvasLetterPasses<TextPainter> letters,
  ) => _LinesSetting._(content, letters, _blockOf(content, letters.fill));

  _LinesSetting._(this._content, this._letters, this.block)
    : _lettersAt = block.topLeft - _roomBeforeBlock(_content);

  final CelTextContent _content;

  /// The letters, set for drawing — stroke under fill, smooth or hard.
  final CanvasLetterPasses<TextPainter> _letters;

  /// The lines' block: as wide as the longest line — or as the box, for a
  /// text that wraps — and as tall as its lines.
  @override
  final ui.Rect block;

  /// Where the engine's own box of the letters stands in the text's frame.
  /// It is the block's corner but for a text set with room to spare
  /// ([_roomToAlign]), whose letters' box begins that room — or half of it
  /// — before the block does.
  final ui.Offset _lettersAt;

  /// The letters as the engine sets them: what the caret, a selection and a
  /// press are measured on.
  TextPainter get _fill => _letters.fill;

  @override
  void paintBoxBehind(ui.Canvas canvas, ui.Rect box, int argb) =>
      _letters.paintBoxBehind(canvas, box, argb);

  @override
  void paint(ui.Canvas canvas, {required ui.Rect within}) =>
      _letters.paintAt(canvas, _lettersAt, within: within);

  /// A hairline as tall as its line.
  @override
  ui.Rect caretRect(TextPosition position) {
    final at = _lettersAt + _fill.getOffsetForCaret(position, ui.Rect.zero);
    return ui.Rect.fromLTWH(
      at.dx,
      at.dy,
      0,
      _fill.getFullHeightForCaret(position, ui.Rect.zero),
    );
  }

  /// One box per line the letters run over, each as tall as its line.
  @override
  List<ui.Rect> selectionRects(int start, int end) => [
    for (final box in _fill.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
      boxHeightStyle: ui.BoxHeightStyle.max,
    ))
      box.toRect().shift(_lettersAt),
  ];

  /// Under the letters, as a field underlines what is being composed.
  @override
  List<CelTextMark> marksBeside(int start, int end) => [
    for (final rect in selectionRects(start, end))
      (from: rect.bottomLeft, to: rect.bottomRight),
  ];

  @override
  TextPosition positionAt(ui.Offset local) =>
      _fill.getPositionForOffset(local - _lettersAt);

  /// 🔬Measured 2026-10-06: a line that wraps at a space takes the space
  /// with it, hanging past its end, and the next line begins after it.
  @override
  List<int> get wrapPlaces {
    final text = _content.text;
    final places = <int>[];
    var start = 0;
    for (final line in _fill.computeLineMetrics()) {
      if (line.hardBreak) {
        // Ended by a break that was typed, or by the text's end.
        final typed = text.indexOf('\n', start);
        start = typed < 0 ? text.length : typed + 1;
        continue;
      }
      start = _fill.getLineBoundary(TextPosition(offset: start)).end;
      places.add(start);
    }
    return places;
  }

  @override
  void dispose() => _letters.dispose();
}

/// [content]'s letters set in lines, each run painted as the passes say.
_LinesSetting _linesOf(
  CelTextContent content,
  TextLetterStyle nextLetterStyle,
) {
  final lineHeight = content.lineHeight;
  return _LinesSetting(
    content,
    canvasLetterPainterPasses(
      [for (final span in content.spans) span.style],
      (paintOf) => _painterOf(
        content,
        nextLetterStyle,
        (letters) => canvasLetterTextStyle(
          letters,
          lineHeight: lineHeight,
          foreground: paintOf(letters),
        ),
      ),
    ),
  );
}

/// [content]'s letters as the engine sets them, each run in the style
/// [styleOf] makes of its letters: wrapped at the box's width, or as long
/// as its lines are.
TextPainter _painterOf(
  CelTextContent content,
  TextLetterStyle nextLetterStyle,
  TextStyle Function(TextLetterStyle letters) styleOf,
) {
  final wrapWidth = content.wrapWidth;
  final painter = TextPainter(
    text: _spanOf(
      content,
      _paragraphLettersOf(content, nextLetterStyle),
      styleOf,
    ),
    textAlign: canvasTextAlign(content.align),
    textDirection: TextDirection.ltr,
  );
  if (wrapWidth != null) {
    painter.layout(minWidth: wrapWidth, maxWidth: wrapWidth);
    return painter;
  }
  painter.layout();
  final room = _roomToAlign(content);
  if (room > 0) {
    final width = painter.width + room;
    // ⚠️Set AGAIN, from nothing. Asked only for another width, a painter
    // whose lines would break the same keeps the lines it has and slides
    // them as one — and the longest would keep the place the room is here
    // to take it out of (measured 2026-10-06: the first cut of this did
    // exactly that).
    painter
      ..markNeedsLayout()
      ..layout(minWidth: width, maxWidth: width);
  }
  return painter;
}

/// THE ROOM A TEXT THAT GROWS IS SET IN, PAST ITS LONGEST LINE — one pixel,
/// when its lines are centred or set to the right; none otherwise.
///
/// 🔬Measured 2026-10-06. The engine aligns a line only when the width it is
/// set in is WIDER than the line. One that fills its width exactly is left
/// where a left-aligned line stands — half its tracking in from the edge —
/// while a line with room is set flush by its letters' own boxes. A text
/// that grows is by its nature as wide as its longest line, so that one
/// line stood half its tracking to the right of where the alignment put
/// every other: in a right-aligned text tracked by ten, five pixels past
/// the rest.
///
/// So such a text is set a pixel wider than its longest line: every line
/// then has room, and the engine aligns them all by one rule. The block is
/// still as wide as the longest line ([_blockOf]) — the room is the
/// engine's to align in, and no part of the text.
///
/// It is also what lets a text be swapped between growing and a box
/// without a letter moving (`cel_text_box_width.dart`): in a box every line
/// that does not fill it has room too.
double _roomToAlign(CelTextContent content) =>
    content.wrapWidth == null && content.align != TextCelAlign.left ? 1 : 0;

/// How far before the block the engine's box of [content]'s letters begins,
/// in the text's own frame: the share of the [_roomToAlign] the alignment
/// leaves on the block's left — half of it centred, all of it set to the
/// right.
ui.Offset _roomBeforeBlock(CelTextContent content) => ui.Offset(
  _roomToAlign(content) *
      switch (content.align) {
        TextCelAlign.left => 0,
        TextCelAlign.center => 0.5,
        TextCelAlign.right => 1,
      },
  0,
);

/// The lines' block in the text's own frame, [fill] being its letters set:
/// a growing text stands ABOUT its anchor, a box hangs from it.
ui.Rect _blockOf(CelTextContent content, TextPainter fill) {
  if (content.wrapWidth != null) {
    return ui.Rect.fromLTWH(0, 0, fill.width, fill.height);
  }
  // As wide as its longest line: what it was set in, less the room.
  final width = fill.width - _roomToAlign(content);
  final left = switch (content.align) {
    TextCelAlign.left => 0.0,
    TextCelAlign.center => -width / 2,
    TextCelAlign.right => -width,
  };
  return ui.Rect.fromLTWH(left, 0, width, fill.height);
}
