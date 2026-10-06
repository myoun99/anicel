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
       _stroke = stroke;

  final CelTextContent content;

  /// The lines' block in the text's own frame: as wide as the longest line
  /// — or as the box, for a text that wraps — and as tall as its lines.
  final ui.Rect block;

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

  double get _radians => content.rotationDegrees * math.pi / 180;

  /// Sets [canvas] — which is in canvas space — up for drawing in the
  /// text's own frame. The caller saves and restores around it.
  void applyFrame(ui.Canvas canvas) {
    canvas.translate(content.anchor.x, content.anchor.y);
    if (content.rotationDegrees != 0) {
      canvas.rotate(_radians);
    }
  }

  /// [local], a point of the text's own frame, on the canvas.
  ui.Offset toCanvas(ui.Offset local) => _turned(
    local,
    _radians,
  ).translate(content.anchor.x, content.anchor.y);

  /// [point], a point of the canvas, in the text's own frame.
  ui.Offset toLocal(ui.Offset point) => _turned(
    point.translate(-content.anchor.x, -content.anchor.y),
    -_radians,
  );

  /// [box]'s corners on the canvas: top left, top right, bottom right,
  /// bottom left — as the text reads, so they turn with it.
  List<ui.Offset> get boxCorners => _cornersOf(box, toCanvas);

  /// Whether [point], on the canvas, is inside the text's box.
  bool boxContains(ui.Offset point) => box.contains(toLocal(point));

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
    _stroke?.paint(canvas, block.topLeft);
    _fill.paint(canvas, block.topLeft);
    canvas.restore();
  }

  /// Where the caret stands at [position], in the text's own frame: a
  /// hairline as tall as its line.
  ui.Rect caretRect(TextPosition position) {
    final at = block.topLeft + _fill.getOffsetForCaret(position, ui.Rect.zero);
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
      box.toRect().shift(block.topLeft),
  ];

  /// The place between letters nearest [point], a point of the canvas.
  TextPosition positionAt(ui.Offset point) =>
      _fill.getPositionForOffset(toLocal(point) - block.topLeft);

  void dispose() {
    _fill.dispose();
    _stroke?.dispose();
  }
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
  final wrapWidth = content.wrapWidth;
  // What no run sets is set by the paragraph the runs are nested in: how
  // tall a text with NO letters is — the caret before the first one. (A
  // line a break opens at the end of the text is not one of those: measured
  // 2026-10-06, the engine makes it as tall as the line the break ended.)
  final paragraphLetters = content.isEmpty
      ? nextLetterStyle
      : content.spans.last.style;

  TextPainter build(TextStyle Function(TextLetterStyle letters) styleOf) {
    final painter = TextPainter(
      text: TextSpan(
        style: canvasLetterTextStyle(
          paragraphLetters,
          lineHeight: lineHeight,
        ),
        children: [
          for (final span in content.spans)
            TextSpan(text: span.text, style: styleOf(span.style)),
        ],
      ),
      textAlign: canvasTextAlign(content.align),
      textDirection: TextDirection.ltr,
    );
    if (wrapWidth == null) {
      painter.layout();
    } else {
      painter.layout(minWidth: wrapWidth, maxWidth: wrapWidth);
    }
    return painter;
  }

  final fill = build(
    (letters) => canvasLetterTextStyle(letters, lineHeight: lineHeight),
  );
  final outlined = content.spans.any(
    (span) => canvasLetterOutlinePaint(span.style) != null,
  );
  final stroke = outlined
      ? build(
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

  // A growing text stands ABOUT its anchor; a box hangs from it.
  final left = wrapWidth != null
      ? 0.0
      : switch (content.align) {
          TextCelAlign.left => 0.0,
          TextCelAlign.center => -fill.width / 2,
          TextCelAlign.right => -fill.width,
        };
  final block = ui.Rect.fromLTWH(left, 0, fill.width, fill.height);

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
  final widestOutline = letters.fold(
    0.0,
    (width, style) => canvasLetterOutlinePaint(style) == null
        ? width
        : math.max(width, style.outlineWidth),
  );
  return CelTextLayout._(
    content: content,
    block: block,
    pad: pad,
    reach: pad + widestOutline / 2 + largest * _glyphReach,
    fill: fill,
    stroke: stroke,
  );
}

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
