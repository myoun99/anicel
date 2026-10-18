part of 'cel_text_layout.dart';

/// A text's letters SET IN LINES — left to right, the lines down the page:
/// the engine's own paragraphs, a painter a paragraph, a pass
/// ([_Paragraphs]).
///
/// ↩️This was the whole of `CelTextLayout` until a text could also be set in
/// columns (2026-10-07). It moved as it was.
class _LinesSetting implements _TextSetting {
  factory _LinesSetting(
    CelTextContent content,
    CanvasLetterPasses<_Paragraphs> letters,
  ) => _LinesSetting._(content, letters, _blockOf(content, letters.fill));

  _LinesSetting._(this._content, this._letters, ui.Rect set)
    : block = _drawnRect(set, _content.letterWidth),
      _lettersAt = set.topLeft - _roomBeforeBlock(_content, _letters.fill);

  final CelTextContent _content;

  /// The letters, set for drawing — stroke under fill, smooth or hard.
  final CanvasLetterPasses<_Paragraphs> _letters;

  /// The lines' block as they are drawn: as wide as the longest line — or
  /// as the box, for a text that wraps — and as tall as its lines.
  @override
  final ui.Rect block;

  /// Where the box the letters are SET in has its corner — in the text's
  /// frame before they are drawn as wide as [CelTextContent.letterWidth]
  /// says ([_drawnRect]). It is the block's corner but for a text that
  /// grows, whose box reaches past its longest line ([_frameOf]) and begins
  /// what is past it — or half of that — before the block does.
  final ui.Offset _lettersAt;

  /// How wide the letters are drawn, as a share of how they are set.
  double get _width => _content.letterWidth;

  /// The letters as the engine sets them: what the caret, a selection and a
  /// press are measured on.
  _Paragraphs get _fill => _letters.fill;

  /// The lines the letters wear, where they are drawn.
  late final CanvasLetterLines _lines = _fill.linesOf(
    _runsOf(_content),
    at: _lettersAt,
  );

  @override
  void paintBoxBehind(ui.Canvas canvas, ui.Rect box, int argb) =>
      _letters.paintBoxBehind(canvas, box, argb);

  @override
  void paint(ui.Canvas canvas, {required ui.Rect within}) => _letters.paint(
    canvas,
    within: within,
    draw: (paragraphs) => paragraphs.paint(canvas, _lettersAt),
    lines: _lines,
    letterWidth: _width,
  );

  /// A hairline as tall as its line.
  @override
  ui.Rect caretRect(TextPosition position) =>
      _drawnRect(_fill.caretAt(position).shift(_lettersAt), _width);

  /// One box per line the letters run over, each as tall as its line.
  @override
  List<ui.Rect> selectionRects(int start, int end) => [
    for (final box in _fill.boxesOf(start, end))
      _drawnRect(box.shift(_lettersAt), _width),
  ];

  /// Under the letters, as a field underlines what is being composed.
  @override
  List<CelTextMark> marksBeside(int start, int end) => [
    for (final rect in selectionRects(start, end))
      (from: rect.bottomLeft, to: rect.bottomRight),
  ];

  @override
  TextPosition positionAt(ui.Offset local) =>
      _fill.positionAt(ui.Offset(local.dx / _width, local.dy) - _lettersAt);

  /// From its line's top to its bottom — the whole line's, which a caret
  /// beside a small letter in it is not.
  @override
  ({double from, double to}) lineAcross(TextPosition position) {
    final (:top, :bottom) = _fill.lineAround(position);
    return (from: _lettersAt.dy + top, to: _lettersAt.dy + bottom);
  }

  @override
  List<int> get wrapPlaces => _fill.wrapPlaces;

  @override
  void dispose() => _letters.dispose();
}

/// [content]'s letters set in lines, each run painted as the passes say.
_LinesSetting _linesOf(
  CelTextContent content,
  TextLetterStyle nextLetterStyle,
) => _LinesSetting(
  content,
  CanvasLetterPasses.of(
    [for (final span in content.spans) span.style],
    (pass) => _Paragraphs.set(
      content,
      nextLetterStyle,
      (letters, lineHeight) => canvasLetterTextStyle(
        letters,
        lineHeight: lineHeight,
        foreground: pass.paintOf(letters),
      ),
    ),
    letGo: (paragraphs) => paragraphs.dispose(),
  ),
);

/// A text's letters set in lines FOR ONE PASS, A PARAGRAPH AT A TIME: one
/// painter a paragraph, its lines aligned as that paragraph says
/// ([CelTextParagraph.align]), and the paragraphs stacked down the page —
/// in the frame of the box they are set in, its top left corner at the
/// origin.
///
/// ⚠️A PAINTER A PARAGRAPH, because the engine aligns every line of what it
/// sets by ONE alignment, and a text's paragraphs are aligned each its own
/// way (text-letters-lean-and-underline ④).
///
/// ★A paragraph begins where a line the last break of the one before would
/// open stands. So every line is as tall as ITS letters at ITS paragraph's
/// pitch, between two paragraphs as within one, and the gap between two
/// set at unlike pitches is between the two (🗣️유저 2026-10-18,
/// text-letters-lean-and-underline-Q4: 「줄마다 제 칸 — 틈은 두 값의 사이」).
class _Paragraphs {
  _Paragraphs._(
    this._content,
    this._painters, {
    required this.width,
    required this.frame,
  }) : _starts = _startsOf(_painters),
       _tops = _topsOf(_painters);

  /// [content]'s paragraphs set — each run in the style [styleOf] makes of
  /// its letters at its paragraph's pitch: wrapped at the box's width, or
  /// for a text that grows in the box it would be made ([_frameOf]).
  factory _Paragraphs.set(
    CelTextContent content,
    TextLetterStyle nextLetterStyle,
    TextStyle Function(TextLetterStyle letters, double lineHeight) styleOf,
  ) {
    final paragraphs = content.paragraphs;
    final spans = _paragraphSpansOf(
      content,
      _paragraphLettersOf(content, nextLetterStyle),
      styleOf,
    );
    final painters = [
      for (final (index, span) in spans.indexed)
        TextPainter(
          text: span,
          textAlign: canvasTextAlign(paragraphs[index].align),
          textDirection: TextDirection.ltr,
        ),
    ];
    final wrapWidth = celTextSetWidth(content);
    if (wrapWidth != null) {
      for (final painter in painters) {
        painter.layout(minWidth: wrapWidth, maxWidth: wrapWidth);
      }
      return _Paragraphs._(
        content,
        painters,
        width: wrapWidth,
        frame: wrapWidth,
      );
    }
    for (final painter in painters) {
      painter.layout();
    }
    final longest = painters.fold(
      0.0,
      (width, painter) => math.max(width, painter.width),
    );
    final frame = _frameOf(content, longest);
    for (final (index, painter) in painters.indexed) {
      // A paragraph set to the left is set once: its lines stand at the
      // box's left whatever width it is set in, and the engine moves none
      // of them to align it ([_frameOf]).
      if (paragraphs[index].align == TextCelAlign.left) {
        continue;
      }
      // ⚠️Set AGAIN, from nothing. Asked only for another width, a painter
      // whose lines would break the same keeps the lines it has and slides
      // them as one — and the longest would keep the place the room is here
      // to take it out of (measured 2026-10-06: the first cut of this did
      // exactly that).
      painter
        ..markNeedsLayout()
        ..layout(minWidth: frame, maxWidth: frame);
    }
    return _Paragraphs._(content, painters, width: longest, frame: frame);
  }

  final CelTextContent _content;

  /// A painter a paragraph, in reading order.
  final List<TextPainter> _painters;

  /// Where each paragraph's letters begin in the text — and, last, where
  /// the text ends.
  final List<int> _starts;

  /// Where each paragraph's first line has its top, down the page.
  final List<double> _tops;

  /// How wide the lines' block is: the box's, or for a text that grows its
  /// longest line's.
  final double width;

  /// How wide the box is that the lines are set — and aligned — in: the
  /// box's own, or for a text that grows the one it would be made
  /// ([_frameOf]).
  final double frame;

  /// How tall the lines are, from the first's top to the last's bottom.
  double get height => _tops.last + _painters.last.height;

  /// Draws the letters with the box's corner at [at].
  void paint(ui.Canvas canvas, ui.Offset at) {
    for (final (index, painter) in _painters.indexed) {
      painter.paint(canvas, at + ui.Offset(0, _tops[index]));
    }
  }

  /// The caret at [position]: a hairline as tall as its line.
  ui.Rect caretAt(TextPosition position) {
    final index = _content.paragraphAt(position.offset);
    final painter = _painters[index];
    final inIt = _inParagraph(index, position);
    final at = painter.getOffsetForCaret(inIt, ui.Rect.zero);
    return ui.Rect.fromLTWH(
      at.dx,
      _tops[index] + at.dy,
      0,
      painter.getFullHeightForCaret(inIt, ui.Rect.zero),
    );
  }

  /// The top and the bottom of the line [position] stands on, down the
  /// page: the line the engine stacks there, as tall as its tallest letter
  /// at its paragraph's pitch.
  ({double top, double bottom}) lineAround(TextPosition position) {
    final index = _content.paragraphAt(position.offset);
    final painter = _painters[index];
    final caret = painter.getOffsetForCaret(
      _inParagraph(index, position),
      ui.Rect.zero,
    );
    // A paragraph with no letters is its one line.
    var top = 0.0;
    var bottom = painter.height;
    for (final line in painter.computeLineMetrics()) {
      bottom = top + line.height;
      if (caret.dy < bottom) {
        break;
      }
      top = bottom;
    }
    return (top: _tops[index] + top, bottom: _tops[index] + bottom);
  }

  /// [position], a place in the text, as a place in the letters of its
  /// paragraph — the one at [index].
  TextPosition _inParagraph(int index, TextPosition position) => TextPosition(
    offset: position.offset - _starts[index],
    affinity: position.affinity,
  );

  /// The boxes of the letters from [start] up to [end]: one per line they
  /// run over, each as tall as its line.
  List<ui.Rect> boxesOf(int start, int end) => [
    for (final (index, painter) in _painters.indexed)
      if (_starts[index] < end && _starts[index + 1] > start)
        for (final box in painter.getBoxesForSelection(
          TextSelection(
            baseOffset: math.max(start, _starts[index]) - _starts[index],
            extentOffset: math.min(end, _starts[index + 1]) - _starts[index],
          ),
          boxHeightStyle: ui.BoxHeightStyle.max,
        ))
          box.toRect().shift(ui.Offset(0, _tops[index])),
  ];

  /// The place between letters nearest [point]: in the paragraph whose
  /// lines it is down the page beside.
  TextPosition positionAt(ui.Offset point) {
    var index = 0;
    while (index + 1 < _painters.length && point.dy >= _tops[index + 1]) {
      index += 1;
    }
    final inIt = _painters[index].getPositionForOffset(
      point - ui.Offset(0, _tops[index]),
    );
    return TextPosition(
      offset: _starts[index] + inIt.offset,
      affinity: inIt.affinity,
    );
  }

  /// Where a line ends for want of room: the first letter of the next.
  List<int> get wrapPlaces => [
    for (final (index, painter) in _painters.indexed)
      for (final place in _wrapPlacesOf(painter)) _starts[index] + place,
  ];

  /// The lines [runs] of the text's letters wear ([CanvasLetterLines]), the
  /// box being drawn with its corner at [at]: each run's in each paragraph
  /// it is in.
  CanvasLetterLines linesOf(
    List<CanvasLetterRun> runs, {
    required ui.Offset at,
  }) {
    final lines = CanvasLetterLinesBuilder();
    for (final (index, painter) in _painters.indexed) {
      final start = _starts[index];
      final end = _starts[index + 1];
      lines.addLinesOf(
        painter,
        [
          for (final run in runs)
            if (run.start < end && run.end > start)
              (
                start: math.max(run.start, start) - start,
                end: math.min(run.end, end) - start,
                letters: run.letters,
              ),
        ],
        at: at + ui.Offset(0, _tops[index]),
      );
    }
    return lines.build();
  }

  void dispose() {
    for (final painter in _painters) {
      painter.dispose();
    }
  }
}

/// Where each of [painters]' paragraphs begins in the text — and, last,
/// where the text ends: each holds its letters and the break that ends it.
List<int> _startsOf(List<TextPainter> painters) {
  final starts = [0];
  for (final painter in painters) {
    starts.add(starts.last + painter.plainText.length);
  }
  return starts;
}

/// Where each of [painters]' paragraphs has its top, down the page: the
/// first at none, and each after where a line opened by the break that
/// ends the one before would stand — that painter's height, less the
/// line's.
///
/// 🔬Measured 2026-10-18: the engine sets every line in WHOLE pixels (a
/// line of letters 20.3 at a pitch of 1.13 is 23 tall), so a line's top is
/// not its baseline less its ascent — that is off by what was rounded —
/// while its height is the very number the engine stacks its lines by. Set
/// a painter a paragraph so, every baseline stood where one painter of the
/// whole text put it, at a pitch a paragraph as at one.
List<double> _topsOf(List<TextPainter> painters) {
  final tops = [0.0];
  for (final painter in painters.take(painters.length - 1)) {
    final opened = painter.computeLineMetrics().last;
    tops.add(tops.last + painter.height - opened.height);
  }
  return tops;
}

/// Where [painter]'s lines end for want of room, in its own letters: the
/// first letter of the line after.
///
/// 🔬Measured 2026-10-06: a line that wraps at a space takes the space
/// with it, hanging past its end, and the next line begins after it.
List<int> _wrapPlacesOf(TextPainter painter) {
  final text = painter.plainText;
  final places = <int>[];
  var start = 0;
  for (final line in painter.computeLineMetrics()) {
    if (line.hardBreak) {
      // Ended by a break that was typed, or by the text's end.
      final typed = text.indexOf('\n', start);
      start = typed < 0 ? text.length : typed + 1;
      continue;
    }
    start = painter.getLineBoundary(TextPosition(offset: start)).end;
    places.add(start);
  }
  return places;
}

/// [content]'s runs, where each stands in its text.
List<CanvasLetterRun> _runsOf(CelTextContent content) {
  final runs = <CanvasLetterRun>[];
  var at = 0;
  for (final span in content.spans) {
    runs.add((start: at, end: at + span.text.length, letters: span.style));
    at += span.text.length;
  }
  return runs;
}

/// THE WIDTH A TEXT THAT GROWS IS SET IN, as it is set — its longest line
/// [longest] long so: the box it would be made ([celTextBoxLengthPast]),
/// which reaches PAST that line. Its lines are aligned in it each as its
/// paragraph says, and the box stands about the anchor as the first
/// paragraph is aligned ([CelTextContent.standsBy]).
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
/// So such a text is set in a box past its longest line: every line then
/// has room, and the engine aligns them all by one rule. The block is
/// still as wide as the longest line ([_blockOf]) — the room is the
/// engine's to align in, and no part of the text.
///
/// ★It is the very box the text is made when it is made one
/// (`cel_text_box_width.dart`), so that swap moves no letter however its
/// paragraphs are aligned: each line stands in the box where it stood.
double _frameOf(CelTextContent content, double longest) =>
    celTextBoxLengthPast(longest * content.letterWidth) / content.letterWidth;

/// How far before the block the box the letters are set in begins, in the
/// text's own frame: the share of what of the box is past the longest line
/// ([_frameOf]) that the text's standing leaves on the block's left — none
/// as it stands by its lines' left end, half of it by their middle, all of
/// it by their right end. None for a box, which is its block.
ui.Offset _roomBeforeBlock(CelTextContent content, _Paragraphs fill) =>
    ui.Offset(
      (fill.frame - fill.width) *
          switch (content.standsBy) {
            TextCelAlign.left => 0,
            TextCelAlign.center => 0.5,
            TextCelAlign.right => 1,
          },
      0,
    );

/// [rect], of letters as the engine SETS them, as they are DRAWN in the
/// text's own frame: [letterWidth] times as wide about its x = 0
/// ([CelTextContent.letterWidth]) — the anchor a text that grows is set
/// about, the left edge of a box.
ui.Rect _drawnRect(ui.Rect rect, double letterWidth) => ui.Rect.fromLTRB(
  rect.left * letterWidth,
  rect.top,
  rect.right * letterWidth,
  rect.bottom,
);

/// The lines' block as the engine sets them, [fill] being its letters set:
/// a growing text stands ABOUT its anchor, as its first paragraph is
/// aligned ([CelTextContent.standsBy]); a box hangs from it.
///
/// ⚠️A paragraph of a growing text aligned UNLIKE the first stands in the
/// box the text is set in ([_frameOf]), which reaches past the block by
/// under a pixel — so its lines can stand that much past the block's edge,
/// as they will in the box the text is made.
ui.Rect _blockOf(CelTextContent content, _Paragraphs fill) {
  final width = fill.width;
  if (content.wrapWidth != null) {
    return ui.Rect.fromLTWH(0, 0, width, fill.height);
  }
  final left = switch (content.standsBy) {
    TextCelAlign.left => 0.0,
    TextCelAlign.center => -width / 2,
    TextCelAlign.right => -width,
  };
  return ui.Rect.fromLTWH(left, 0, width, fill.height);
}
