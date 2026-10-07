import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';

import '../../models/cel_text.dart';
import '../../models/text_cel_style.dart';
import 'canvas_letter_faces.dart';
import 'canvas_letter_passes.dart';
import 'canvas_letter_style.dart';
import 'vertical_writing.dart';
import 'vertical_writing_text.dart'
    show paintVerticalTextCell, verticalGlyphAdvance, verticalGlyphFit;
import 'word_condensation.dart' show paintScaledText;

part 'cel_text_cell_painters.dart';
part 'cel_text_columns.dart';
part 'cel_text_lines.dart';

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
///
/// 🧭TWO SETTINGS. A text is written in lines or in columns
/// ([CelTextContent.vertical]); which letters stand where is the setting's
/// ([_TextSetting]) and everything about the box they stand in is this
/// class's, the same for both.
class CelTextLayout {
  CelTextLayout._({
    required this.content,
    required this.pad,
    required double reach,
    required _TextSetting setting,
  }) : _reach = reach,
       _setting = setting;

  final CelTextContent content;

  /// The letters, set — in lines or in columns.
  final _TextSetting _setting;

  /// The letters' block in the text's own frame — its lines', as wide as
  /// the longest line (or as the box, for a text that wraps) and as tall
  /// as they are; or its columns', as long as the longest (or as the box)
  /// and as wide as they are.
  ui.Rect get block => _setting.block;

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
      _setting.paintBoxBehind(canvas, box, background);
    }
    _setting.paint(canvas, within: block.inflate(_reach));
    canvas.restore();
  }

  /// Where the caret stands at [position], in the text's own frame: a
  /// HAIRLINE — a rect of no width, as tall as its line, or for a text in
  /// columns one of no height, as wide as its column. Whoever draws it
  /// draws from its one corner to the other.
  ui.Rect caretRect(TextPosition position) => _setting.caretRect(position);

  /// The boxes of the letters from [start] up to [end], in the text's own
  /// frame — one per line they run over, each as tall as its line; or, in
  /// columns, one per letter's place down its column.
  List<ui.Rect> selectionRects(int start, int end) =>
      _setting.selectionRects(start, end);

  /// The marks that say WHICH letters, from [start] up to [end], are still
  /// being composed, in the text's own frame: under them on a line, to
  /// their right in a column.
  List<CelTextMark> marksBeside(int start, int end) =>
      _setting.marksBeside(start, end);

  /// The place between letters nearest [point], a point of the canvas.
  TextPosition positionAt(ui.Offset point) =>
      _setting.positionAt(toLocal(point));

  /// Where a line of the text — or a column — ends for want of ROOM: the
  /// first letter of the one after, counted from the text's start. The
  /// places a box broke its text at, never the ones a break was typed at.
  /// None for a text that grows.
  List<int> get wrapPlaces => _setting.wrapPlaces;

  void dispose() => _setting.dispose();
}

/// A mark drawn beside letters, in the text's own frame — a hairline from
/// one point to another ([CelTextLayout.marksBeside]).
typedef CelTextMark = ({ui.Offset from, ui.Offset to});

/// A TEXT'S LETTERS, SET — which of them stands where, in the text's own
/// frame, and how they are drawn: in lines ([_LinesSetting]) or in columns
/// ([_ColumnsSetting]). What [CelTextLayout] answers of its letters, it
/// asks here.
abstract interface class _TextSetting {
  ui.Rect get block;
  void paintBoxBehind(ui.Canvas canvas, ui.Rect box, int argb);
  void paint(ui.Canvas canvas, {required ui.Rect within});
  ui.Rect caretRect(TextPosition position);
  List<ui.Rect> selectionRects(int start, int end);
  List<CelTextMark> marksBeside(int start, int end);

  /// The place between letters nearest [local], a point of the text's own
  /// frame.
  TextPosition positionAt(ui.Offset local);
  List<int> get wrapPlaces;
  void dispose();
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

  /// The middle of the box — what a hand on a corner sizes it about, and
  /// where its cross stands until a hand carries it ([crossAt]).
  ui.Offset get centre => _frame.toCanvas(_rect.center);

  /// Where the box's CROSS stands, carried [offCentre] from its middle: the
  /// point a hand outside the box turns the text about.
  ///
  /// 🚨[offCentre] IS ALONG THE TEXT'S OWN LINES, in canvas pixels — a
  /// displacement, and zero is the middle, so a cross nobody carried needs
  /// no case of its own (the anchor point's law, `TransformValues.anchorX`:
  /// 「기본값 상자안의 자리에서 **얼마나 이동됬나**」). Kept that way it rides
  /// every edit the box takes: a move and a scale leave it as far from the
  /// middle as it was, and a turn about it carries the middle round it — the
  /// cross does not orbit itself.
  ui.Offset crossAt(ui.Offset offCentre) =>
      _frame.toCanvas(_rect.center + offCentre);

  /// [travel], a hand's travel on the canvas, along the text's own lines —
  /// what carrying the cross that far adds to how far it stands off the
  /// middle ([crossAt]).
  ui.Offset alongItsLines(ui.Offset travel) =>
      _turned(travel, -_frame.radians);

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
/// ⚠️It is the box the letters have ON THIS MACHINE, in the faces it has
/// NOW: a box kept from before a face arrived, or left, was measured in
/// other letters, and is set again ([CanvasLetterFaces.generation]).
CelTextBox celTextBoxOf(CelTextContent content) {
  final faces = CanvasLetterFaces.current.generation;
  final kept = _boxes[content];
  if (kept != null && kept.faces == faces) {
    return kept.box;
  }
  final box = _boxSetFor(content);
  _boxes[content] = (faces: faces, box: box);
  return box;
}

final Expando<({int faces, CelTextBox box})> _boxes = Expando('cel text box');

/// Whether a face [content]'s letters are written in is still ON ITS WAY to
/// the engine ([CanvasLetterFaces]) — and it is sent for, if nobody had.
/// Until it is here those letters would be set in another face, so nothing
/// measures them and no plate is made of them.
bool celTextAwaitsAFace(CelTextContent content) {
  final faces = CanvasLetterFaces.current;
  return content.spans.any((span) => faces.isOnItsWay(span.style.fontFamily));
}

/// Completes when every face [content] is set in has reached the engine —
/// null when none is on its way, so that whoever asks goes on at once.
/// [nextLetterStyle] is read for a content with no letters, which is
/// measured by it ([layoutCelText]).
Future<void>? celTextFacesArriving(
  CelTextContent content, {
  TextLetterStyle nextLetterStyle = const TextLetterStyle(),
}) => CanvasLetterFaces.current.whenHere([
  for (final span in content.spans) span.style.fontFamily,
  if (content.isEmpty) nextLetterStyle.fontFamily,
]);

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
    pad: pad,
    reach: pad + _widestOutlineOf(letters) / 2 + largest * _glyphReach,
    setting: content.vertical
        ? _ColumnsSetting(content, nextLetterStyle)
        : _linesOf(content, nextLetterStyle),
  );
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
