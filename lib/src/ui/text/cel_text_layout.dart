import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../models/cel_text.dart';
import '../../models/text_cel_style.dart';
import 'canvas_letter_style.dart';

/// A text of a cel, SET: its letters as the engine lays them out, where that
/// puts them on the canvas, and how to draw them (R9-rest, the text tool).
///
/// Built SYNCHRONOUSLY — measuring is the half of setting type the engine
/// answers at once; only the PIXELS take a frame (`bakeCelTextPlate`). So
/// the box a text is edited by, its caret and the letters a press lands on
/// are all read off the same layout its plate was baked from, and none of
/// them can lead or trail the letters on screen.
///
/// 🧭TWO FRAMES. The text's OWN frame has its origin at the anchor and its
/// x along the lines, before the turn — [block], [box], [caretRect] and
/// [selectionRects] are in it, so whoever draws them sets the frame up once
/// ([applyFrame]). CANVAS space is where the cel's pixels are — [inkBounds],
/// [boxCorners] and the points a press hands in ([positionAt],
/// [boxContains]).
class CelTextLayout {
  CelTextLayout._({
    required this.content,
    required this.block,
    required this.pad,
    required double reach,
    required TextPainter fill,
    required TextPainter? stroke,
  }) : _reach = reach,
       _fill = fill,
       _stroke = stroke,
       _lettersAt = block.topLeft - _roomBeforeBlock(content);

  final CelTextContent content;

  /// The lines' block in the text's own frame: as wide as the longest line
  /// — or as the box, for a text that wraps — and as tall as its lines.
  final ui.Rect block;

  /// Where the engine's own box of the letters stands in the text's frame.
  /// It is the block's corner but for a text set with room to spare
  /// ([_roomToAlign]), whose letters' box begins that room — or half of it
  /// — before the block does.
  final ui.Offset _lettersAt;

  /// How far the box filled behind the letters reaches past [block] on
  /// every side; zero for a text with none.
  final double pad;

  /// What a person sees as this text's box, in its own frame — the block,
  /// and the box behind it where it has one. The frame it is selected by is
  /// drawn here, and a press inside it is a press on the text.
  ui.Rect get box => block.inflate(pad);

  /// A canvas rect, in whole pixels, that holds everything [paint] draws.
  ///
  /// ⚠️NOT THE TIGHT BOX OF THE INK — the engine says where a line's box
  /// is, never how far a glyph reaches out of it, and a swash or a stack of
  /// accents does. It is the box grown by a whole letter's size
  /// ([_glyphReach]); the tiles a bake finds empty are dropped there, so
  /// the room costs a larger raster and nothing that is kept.
  late final ui.Rect inkBounds = _wholePixelsAround(
    _cornersOf(block.inflate(_reach), toCanvas),
  );

  /// How far past [block] anything of the text is drawn, in its own frame.
  final double _reach;

  final TextPainter _fill;
  final TextPainter? _stroke;

  late final _TextFrame _frame = _TextFrame.of(content);

  /// Sets [canvas] — which is in canvas space — up for drawing in the
  /// text's own frame. The caller saves and restores around it.
  void applyFrame(ui.Canvas canvas) {
    canvas.translate(content.anchor.x, content.anchor.y);
    if (content.rotationDegrees != 0) {
      canvas.rotate(_frame.radians);
    }
  }

  /// [local], a point of the text's own frame, on the canvas.
  ui.Offset toCanvas(ui.Offset local) => _frame.toCanvas(local);

  /// [point], a point of the canvas, in the text's own frame.
  ui.Offset toLocal(ui.Offset point) => _frame.toLocal(point);

  /// [box] as it stands on the canvas — what is kept of this text once its
  /// letters are let go ([celTextBoxOf]).
  late final CelTextBox onCanvas = CelTextBox._(_frame, box);

  /// [box]'s corners on the canvas: top left, top right, bottom right,
  /// bottom left — as the text reads, so they turn with it.
  List<ui.Offset> get boxCorners => onCanvas.corners;

  /// Whether [point], on the canvas, is inside the text's box.
  bool boxContains(ui.Offset point) => onCanvas.contains(point);

  /// Draws the text at its place on the canvas — the caller sets up any
  /// viewport or camera first.
  void paint(ui.Canvas canvas) {
    canvas.save();
    applyFrame(canvas);
    final background = content.backgroundColor;
    if (background != null) {
      canvas.drawRect(box, ui.Paint()..color = ui.Color(background));
    }
    // Stroke under fill, over the whole text — the timeline glyph outline
    // recipe (#15: one rule on every surface). A letter's outline never
    // covers its neighbour.
    _stroke?.paint(canvas, _lettersAt);
    _fill.paint(canvas, _lettersAt);
    canvas.restore();
  }

  /// Where the caret stands at [position], in the text's own frame: a
  /// hairline as tall as its line.
  ui.Rect caretRect(TextPosition position) {
    final at = _lettersAt + _fill.getOffsetForCaret(position, ui.Rect.zero);
    return ui.Rect.fromLTWH(
      at.dx,
      at.dy,
      0,
      _fill.getFullHeightForCaret(position, ui.Rect.zero),
    );
  }

  /// The boxes of the letters from [start] up to [end], in the text's own
  /// frame — one per line they run over, each as tall as its line.
  List<ui.Rect> selectionRects(int start, int end) => [
    for (final box in _fill.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
      boxHeightStyle: ui.BoxHeightStyle.max,
    ))
      box.toRect().shift(_lettersAt),
  ];

  /// The place between letters nearest [point], a point of the canvas.
  TextPosition positionAt(ui.Offset point) =>
      _fill.getPositionForOffset(toLocal(point) - _lettersAt);

  /// Where a line of the text ends for want of ROOM — the first letter of
  /// the line after, counted from the text's start: the places a box broke
  /// its text at, never the ones a break was typed at. None for a text that
  /// grows.
  ///
  /// 🔬Measured 2026-10-06: a line that wraps at a space takes the space
  /// with it, hanging past its end, and the next line begins after it.
  List<int> get wrapPlaces {
    final text = content.text;
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

  void dispose() {
    _fill.dispose();
    _stroke?.dispose();
  }
}

/// The frame a text is set in: its origin at the text's anchor, its x along
/// the lines — turned as the text is.
class _TextFrame {
  _TextFrame.of(CelTextContent content)
    : anchor = ui.Offset(content.anchor.x, content.anchor.y),
      radians = content.rotationDegrees * math.pi / 180;

  final ui.Offset anchor;
  final double radians;

  /// [local], a point of the frame, on the canvas.
  ui.Offset toCanvas(ui.Offset local) => _turned(local, radians) + anchor;

  /// [point], a point of the canvas, in the frame.
  ui.Offset toLocal(ui.Offset point) => _turned(point - anchor, -radians);
}

/// WHERE A TEXT'S BOX STANDS ON THE CANVAS: the frame a person sees the
/// text by and takes it by, turned as the text is — and nothing of its
/// letters.
///
/// 유저 2026-10-02 (R9-rest): 「텍스트는 텍스트 툴을 선택했을때만 **텍스트별로
/// 박스가 떠서** 편집가능」 — every text of the cel wears its box while the
/// tool is in hand, the ones nobody is holding too, and a press asks each
/// of them whether it is inside. Those are drawn and asked through this
/// ([celTextBoxOf]): the one in hand through its layout's
/// ([CelTextLayout.onCanvas]), which is the same value.
class CelTextBox {
  const CelTextBox._(this._frame, this._rect);

  final _TextFrame _frame;

  /// The box in the text's own frame.
  final ui.Rect _rect;

  /// Top left, top right, bottom right, bottom left — as the text reads, so
  /// they turn with it.
  List<ui.Offset> get corners => _cornersOf(_rect, _frame.toCanvas);

  /// The middle of the box — what a hand on it turns and sizes it about.
  ui.Offset get centre => _frame.toCanvas(_rect.center);

  /// Whether [point], on the canvas, is inside the box.
  bool contains(ui.Offset point) => _rect.contains(_frame.toLocal(point));
}

/// [content]'s box on the canvas — set once for a content, and kept with
/// it.
///
/// A content never changes, so neither does its box; and the boxes of the
/// texts nobody is holding are drawn every frame the text tool is in hand
/// and asked on every press. Setting their letters each time would be
/// setting type to draw four lines.
///
/// ⚠️It is the box the letters have ON THIS MACHINE, in the fonts it has
/// when first asked.
CelTextBox celTextBoxOf(CelTextContent content) =>
    _boxes[content] ??= _boxSetFor(content);

final Expando<CelTextBox> _boxes = Expando<CelTextBox>('cel text box');

CelTextBox _boxSetFor(CelTextContent content) {
  final layout = layoutCelText(content);
  final box = layout.onCanvas;
  layout.dispose();
  return box;
}

/// Sets [content].
///
/// A text with a [CelTextContent.wrapWidth] is set in a box that wide and
/// wraps at it (유저 2026-10-06: 「폭이 정해진 상자(자동 줄바꿈)」); one
/// without grows with its letters and breaks only at the breaks typed into
/// it, its lines standing about the anchor as [CelTextContent.align] says.
///
/// [nextLetterStyle] is what the first letter typed into a text with NO
/// letters will wear — such a text has no run to say how tall its caret is.
/// Unread for any other.
///
/// Cheap enough to call per edit; dispose the result when done.
CelTextLayout layoutCelText(
  CelTextContent content, {
  TextLetterStyle nextLetterStyle = const TextLetterStyle(),
}) {
  final lineHeight = content.lineHeight;
  final fill = _painterOf(
    content,
    nextLetterStyle,
    (letters) => canvasLetterTextStyle(letters, lineHeight: lineHeight),
  );
  final outlined = content.spans.any(
    (span) => canvasLetterOutlinePaint(span.style) != null,
  );
  final stroke = outlined
      ? _painterOf(
          content,
          nextLetterStyle,
          (letters) => canvasLetterTextStyle(
            letters,
            lineHeight: lineHeight,
            // ⚠️A run with no outline still names a paint, one that draws
            // nothing: painted by its colour it would be drawn a second
            // time under its own fill, and every soft edge of it would
            // come out heavier.
            foreground: canvasLetterOutlinePaint(letters) ?? _drawsNothing,
          ),
        )
      : null;
  final letters = [
    if (content.isEmpty) nextLetterStyle,
    for (final span in content.spans) span.style,
  ];
  final largest = letters.fold(
    0.0,
    (size, style) => math.max(size, style.fontSize),
  );
  // The SE tag's box (`layoutTextCel`): a quarter of the letter's size of
  // breathing room. Here the largest letter's, so the box clears them all.
  final pad = content.backgroundColor == null ? 0.0 : largest * 0.25;
  return CelTextLayout._(
    content: content,
    block: _blockOf(content, fill),
    pad: pad,
    reach: pad + _widestOutlineOf(letters) / 2 + largest * _glyphReach,
    fill: fill,
    stroke: stroke,
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

/// The widest outline any of [letters] is stroked with — a width with no
/// colour is no outline.
double _widestOutlineOf(List<TextLetterStyle> letters) => letters.fold(
  0.0,
  (width, style) => canvasLetterOutlinePaint(style) == null
      ? width
      : math.max(width, style.outlineWidth),
);

/// [content]'s letters as the engine is handed them: one span a run, each
/// saying its whole style, nested in the style of [paragraphLetters].
TextSpan _spanOf(
  CelTextContent content,
  TextLetterStyle paragraphLetters,
  TextStyle Function(TextLetterStyle letters) styleOf,
) => TextSpan(
  style: canvasLetterTextStyle(
    paragraphLetters,
    lineHeight: content.lineHeight,
  ),
  children: [
    for (final span in content.spans)
      TextSpan(text: span.text, style: styleOf(span.style)),
  ],
);

/// The letters of [content] as a FIELD is handed them — the very spans the
/// layout's own fill pass is set from ([layoutCelText]), so a field that
/// types into a text breaks its lines, and moves its caret up and down
/// them, where the text on the canvas does.
TextSpan celTextFieldSpan(
  CelTextContent content, {
  required TextLetterStyle nextLetterStyle,
}) => _spanOf(
  content,
  _paragraphLettersOf(content, nextLetterStyle),
  (letters) => canvasLetterTextStyle(letters, lineHeight: content.lineHeight),
);

/// The letters the PARAGRAPH is set in — the style [content]'s runs are
/// nested in. What no run sets is set by it: how tall a text with NO
/// letters is, the caret before the first one. (A line a break opens at the
/// end of the text is not one of those: measured 2026-10-06, the engine
/// makes it as tall as the line the break ended.)
TextLetterStyle _paragraphLettersOf(
  CelTextContent content,
  TextLetterStyle nextLetterStyle,
) => content.isEmpty ? nextLetterStyle : content.spans.last.style;

/// How far past its line's box a glyph is given room to reach, in letter
/// sizes ([CelTextLayout.inkBounds]). A whole one: an italic leans out by a
/// fraction of that and a script's swash by most of it; what would need
/// more is cut at the edge of the room.
const double _glyphReach = 1.0;

/// The paint of a run that has no outline, in the pass that strokes them.
final ui.Paint _drawsNothing = ui.Paint()..color = const ui.Color(0x00000000);

/// [rect]'s corners through [place]: top left, top right, bottom right,
/// bottom left.
List<ui.Offset> _cornersOf(
  ui.Rect rect,
  ui.Offset Function(ui.Offset) place,
) => [
  place(rect.topLeft),
  place(rect.topRight),
  place(rect.bottomRight),
  place(rect.bottomLeft),
];

/// The smallest rect on whole pixels that holds every one of [points].
ui.Rect _wholePixelsAround(List<ui.Offset> points) {
  var left = points.first.dx;
  var top = points.first.dy;
  var right = left;
  var bottom = top;
  for (final point in points.skip(1)) {
    left = math.min(left, point.dx);
    top = math.min(top, point.dy);
    right = math.max(right, point.dx);
    bottom = math.max(bottom, point.dy);
  }
  return ui.Rect.fromLTRB(
    left.floorToDouble(),
    top.floorToDouble(),
    right.ceilToDouble(),
    bottom.ceilToDouble(),
  );
}

/// [point] turned by [radians] about the origin — clockwise on a canvas,
/// whose y runs down.
ui.Offset _turned(ui.Offset point, double radians) {
  if (radians == 0) {
    return point;
  }
  final cos = math.cos(radians);
  final sin = math.sin(radians);
  return ui.Offset(
    point.dx * cos - point.dy * sin,
    point.dx * sin + point.dy * cos,
  );
}
