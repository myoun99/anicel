import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../models/text_cel_style.dart';
import 'canvas_letter_style.dart';

/// Sets a canvas text's letters ONCE MORE, for one pass — each run painted
/// by what the pass says of its letters — and hands back what it set: one
/// painter for a text set in lines, the painters of its cells for one set
/// in columns.
typedef CanvasLetterSetter<T> = T Function(CanvasLetterPass pass);

/// ONE PASS over a text's letters, as a setter is handed it
/// ([CanvasLetterPasses]).
class CanvasLetterPass {
  CanvasLetterPass._(this.key, this._paintOf);

  /// WHICH pass this is, as a value: with a run's letters it says ALL of
  /// what [paintOf] answers for them. So whoever keeps what it set by the
  /// letters, their style and this can use it again for another text — a
  /// text in columns keeps its cells' painters so
  /// (`cel_text_cell_painters.dart`).
  ///
  /// ⚠️A pass that painted by anything else — a colour of the whole text's,
  /// a size of the canvas — would have to say so HERE, or what is kept for
  /// one text would be drawn for another.
  final Object key;

  final ui.Paint? Function(TextLetterStyle letters) _paintOf;

  /// What paints a run of [letters] in this pass — null being their own
  /// colour.
  ///
  /// A run that is not this pass's still names a paint, one that draws
  /// nothing ([draws]): a text set as ONE paragraph has to set that run to
  /// keep the others where they stand.
  ui.Paint? paintOf(TextLetterStyle letters) => _paintOf(letters);

  /// Whether a run of [letters] is this pass's to draw at all. A host that
  /// sets every run on its own sets nothing for one that is not.
  bool draws(TextLetterStyle letters) =>
      !identical(_paintOf(letters), _drawsNothing);
}

/// The kinds of pass there are — a hard one told from the others of its
/// kind by the colour it covers in ([CanvasLetterPass.key]).
enum _PassKind { fill, stroke, hardStroke, hardFill }

/// THE PASSES A CANVAS TEXT'S LETTERS ARE DRAWN IN — outline under fill
/// (#15: one rule on every surface), over the whole text, so a letter's
/// outline never covers its neighbour — for the SE name tag
/// (`layoutTextCel`) and a text on a cel (`layoutCelText`) alike (R5 ⓣ:
/// 「ONE canvas-text implementation」), and for a text set in lines or in
/// columns alike: [T] is whatever one setting of the letters is.
///
/// 🗣️유저 2026-10-06 (R9-rest, of letters with no smoothing — the switch
/// the shape fill and the selection carry): 「권장대로. 2차에서 스위치로
/// 넣음」. A letter whose style says [TextLetterStyle.antialias] false is
/// drawn HARD: every pixel it covers by half or more is its colour, whole,
/// and every other pixel is none of it.
///
/// 🚨WHY A LAYER, AND NOT A SWITCH ON THE LETTERS. The engine sets no glyph
/// without smoothing its edge — the edging is the engine's own, and a
/// paint's `isAntiAlias` is not read for text. So the hard letters are set
/// in a layer of their own and the layer comes down through a filter that
/// keeps a pixel whole or drops it ([_drawHard]).
///
/// ★ONE LAYER A COLOUR. Two hard letters of different colours that meet in
/// a pixel each claim it, or do not, by their own cover of it: no pixel
/// comes out a blend of the two, which is the whole of what 「no smoothing」
/// is asked for.
///
/// ⚠️WITH NO HARD LETTER NOTHING OF THIS RUNS: the passes are the two
/// settings they always were, drawn as they always were, and a text baked
/// before the switch existed bakes to the bytes it did.
class CanvasLetterPasses<T extends Object> {
  CanvasLetterPasses._({
    required this.fill,
    required T? stroke,
    required List<_HardPass<T>> hardStrokes,
    required List<_HardPass<T>> hardFills,
    required bool hardThroughout,
    required void Function(T set) letGo,
  }) : _stroke = stroke,
       _hardStrokes = hardStrokes,
       _hardFills = hardFills,
       _hardThroughout = hardThroughout,
       _letGo = letGo;

  /// The passes of a text whose runs are set in [letters], [set] being how
  /// it sets them and [letGo] how one setting is let go of.
  ///
  /// [measured] is the text already set in its letters' own colours, where
  /// the caller had to set it to know its size (the SE tag, every frame):
  /// with no hard letter that IS the fill pass, and nothing is set twice.
  /// It is this object's to let go of from here on.
  factory CanvasLetterPasses.of(
    Iterable<TextLetterStyle> letters,
    CanvasLetterSetter<T> set, {
    required void Function(T set) letGo,
    T? measured,
  }) {
    final styles = letters.toList();
    final hard = [
      for (final style in styles)
        if (!style.antialias) style,
    ];
    final T fill;
    if (hard.isEmpty && measured != null) {
      fill = measured;
    } else {
      if (measured != null) {
        letGo(measured);
      }
      // A hard letter is not this pass's: it names a paint that draws
      // nothing, as a run with no outline does in the outline's pass.
      fill = set(
        CanvasLetterPass._(
          (_PassKind.fill, null),
          (letters) => letters.antialias ? null : _drawsNothing,
        ),
      );
    }
    final outlined = styles.any(
      (style) => style.antialias && canvasLetterOutlinePaint(style) != null,
    );
    return CanvasLetterPasses._(
      fill: fill,
      stroke: outlined
          ? set(
              CanvasLetterPass._(
                (_PassKind.stroke, null),
                (letters) => letters.antialias
                    // ⚠️A run with no outline still names a paint, one
                    // that draws nothing: painted by its colour it would
                    // be drawn a second time under its own fill, and every
                    // soft edge of it would come out heavier.
                    ? canvasLetterOutlinePaint(letters) ?? _drawsNothing
                    : _drawsNothing,
              ),
            )
          : null,
      hardStrokes: [
        for (final argb in {
          for (final style in hard)
            if (canvasLetterOutlinePaint(style) != null) style.outlineColor!,
        })
          (
            argb: argb,
            cover: set(
              CanvasLetterPass._(
                (_PassKind.hardStroke, argb),
                (letters) =>
                    _hardOutlineCover(letters, argb) ?? _drawsNothing,
              ),
            ),
          ),
      ],
      hardFills: [
        for (final argb in {for (final style in hard) style.color})
          _hardFillOf(argb, set),
      ],
      hardThroughout: hard.length == styles.length,
      letGo: letGo,
    );
  }

  /// The hard letters whose colour is [argb], set as cover.
  static _HardPass<T> _hardFillOf<T extends Object>(
    int argb,
    CanvasLetterSetter<T> set,
  ) {
    final cover = _coverIn(argb);
    return (
      argb: argb,
      cover: set(
        CanvasLetterPass._(
          (_PassKind.hardFill, argb),
          (letters) => !letters.antialias && letters.color == argb
              ? cover
              : _drawsNothing,
        ),
      ),
    );
  }

  /// The letters as the engine sets them — what a caret, a selection and a
  /// press are measured on — and the pass that fills the smooth ones.
  final T fill;

  /// The smooth letters' outlines; null when none of them wears one.
  final T? _stroke;

  final List<_HardPass<T>> _hardStrokes;
  final List<_HardPass<T>> _hardFills;

  /// Whether NO letter of the text is smooth.
  final bool _hardThroughout;

  final void Function(T set) _letGo;

  /// Draws the box behind the letters — [box], in [argb] — HARD where every
  /// letter of the text is: a text none of whose letters is smoothed has no
  /// smoothed edge at all, its box's included (it has one wherever the text
  /// is turned, or the box ends between two pixels).
  void paintBoxBehind(ui.Canvas canvas, ui.Rect box, int argb) {
    if (!_hardThroughout) {
      canvas.drawRect(box, ui.Paint()..color = ui.Color(argb));
      return;
    }
    _drawHard(
      canvas,
      argb,
      within: box,
      cover: () => canvas.drawRect(box, _coverIn(argb)),
    );
  }

  /// Draws the letters, [draw] being how one setting of them is drawn.
  /// [within] holds everything they can draw, in the canvas's own space:
  /// the hard letters are cut just past it ([_drawHard]).
  void paint(
    ui.Canvas canvas, {
    required ui.Rect within,
    required void Function(T set) draw,
  }) {
    void hard(_HardPass<T> pass) => _drawHard(
      canvas,
      pass.argb,
      within: within,
      cover: () => draw(pass.cover),
    );
    final stroke = _stroke;
    if (stroke != null) {
      draw(stroke);
    }
    _hardStrokes.forEach(hard);
    draw(fill);
    _hardFills.forEach(hard);
  }

  void dispose() {
    final stroke = _stroke;
    _letGo(fill);
    if (stroke != null) {
      _letGo(stroke);
    }
    for (final pass in [..._hardStrokes, ..._hardFills]) {
      _letGo(pass.cover);
    }
  }
}

/// The passes of a text whose every setting is ONE painter — a text set in
/// lines (`layoutCelText`), the SE name tag (`layoutTextCel`).
CanvasLetterPasses<TextPainter> canvasLetterPainterPasses(
  Iterable<TextLetterStyle> letters,
  CanvasLetterSetter<TextPainter> set, {
  TextPainter? measured,
}) => CanvasLetterPasses.of(
  letters,
  set,
  letGo: (painter) => painter.dispose(),
  measured: measured,
);

/// Drawing the passes of a text whose every setting is one painter.
extension CanvasLetterPainterPasses on CanvasLetterPasses<TextPainter> {
  /// Draws the letters with their box's corner at [at] ([paint]).
  void paintAt(ui.Canvas canvas, ui.Offset at, {required ui.Rect within}) =>
      paint(
        canvas,
        within: within,
        draw: (painter) => painter.paint(canvas, at),
      );
}

/// The hard letters of one colour, set as cover ([_coverIn]).
typedef _HardPass<T> = ({int argb, T cover});

/// Draws what [cover] draws HARD, in the colour [argb]: every pixel it
/// covers by half or more is that colour, whole, and every other is
/// nothing. [within] holds everything [cover] draws.
///
/// [cover] draws into a layer that comes down through a filter: the three
/// colours are set outright — no rounding on the way to the cel can leave
/// one a step off — and under the alpha is a cliff, at half.
///
/// ⚠️THE COLOUR'S OWN ALPHA IS A LAYER ROUND THAT ONE, not the hard layer's
/// paint: a paint's alpha is taken before its filter (measured 2026-10-07 —
/// a half see-through colour came down whole), so under the cliff it would
/// be read as cover.
///
/// ⚠️THE ROOM IS A CUT, MADE HERE. One engine cuts a layer at the bounds it
/// is given and another takes them as a hint (measured 2026-10-07: the test
/// engine drew a hard outline past them, whole) — so a room too small would
/// show on the first and pass every test on the second. Cut here, it shows
/// wherever this runs.
///
/// 🚨AND THE CUT IS MADE CLEAR OF [within] ([_cutClear]), NEVER ON IT. A cut
/// is not hard on the engine that ships, whatever `doAntiAlias` says: its
/// own edge is smoothed. Measured on the device, 2026-10-07 — a turned box
/// cut at its own edge came down with 241 of that edge's pixels half and
/// three quarters there (alpha 7f, bf), under letters asked to have no such
/// pixel. The test engine cut the same box clean, so no test of pixels
/// here can see it: the room is pinned as a rect, and read on the device.
void _drawHard(
  ui.Canvas canvas,
  int argb, {
  required ui.Rect within,
  required void Function() cover,
}) {
  final alpha = (argb >> 24) & 0xFF;
  final seeThrough = alpha != 0xFF;
  final room = within.inflate(_cutClear);
  canvas
    ..save()
    ..clipRect(room, doAntiAlias: false);
  if (seeThrough) {
    canvas.saveLayer(
      room,
      ui.Paint()..color = ui.Color.fromARGB(alpha, 0, 0, 0),
    );
  }
  canvas.saveLayer(
    room,
    ui.Paint()
      ..colorFilter = ui.ColorFilter.matrix(<double>[
        0, 0, 0, 0, ((argb >> 16) & 0xFF).toDouble(),
        0, 0, 0, 0, ((argb >> 8) & 0xFF).toDouble(),
        0, 0, 0, 0, (argb & 0xFF).toDouble(),
        0, 0, 0, _cliff, -_cliff * 127.5,
      ]),
  );
  cover();
  canvas.restore();
  if (seeThrough) {
    canvas.restore();
  }
  canvas.restore();
}

/// How far past what is drawn a hard pass is cut ([_drawHard]), in the
/// canvas's own units: farther than a pixel is across from corner to
/// corner, where a unit is a pixel. A pixel the ink so much as touches is
/// then whole inside the cut, so whatever an engine makes of the cut's
/// edge within a pixel, it makes it of pixels nothing is drawn on.
///
/// ⚠️A unit IS a pixel where a text is baked onto its cel
/// ([bakeCelTextPlate], drawn 1:1) — the one place a letter is set hard
/// today. Drawn under a view zoomed out, two units are less than that and
/// the cut closes on the ink again: whoever sets a tag hard measures the
/// room in the surface's pixels first.
const double _cutClear = 2;

/// How steep the alpha's cliff is ([_drawHard]): of two covers a 255th
/// apart on either side of half, one comes down nothing and the other
/// whole from 510 up; the rest is room, for a layer that keeps its cover in
/// more than eight bits — where a sliver of cover, one part in this of a
/// step, still comes down between the two.
const double _cliff = 65536;

/// The paint that covers as letters of the colour [argb] cover: that
/// colour, opaque.
///
/// 🔬ITS OWN COLOUR, NOT ANY (measured 2026-10-07): the engine's cover of a
/// glyph depends on the colour it is set in. Set in white, two letters came
/// down hard over 215 pixels where the same letters, red and smooth, cover
/// 190 — every edge a fifth of a pixel further out.
ui.Paint _coverIn(int argb) => ui.Paint()..color = ui.Color(argb | 0xFF000000);

/// The outline of [letters] as plain cover, where they are hard and wear
/// one in the colour [argb]; null where they do not.
ui.Paint? _hardOutlineCover(TextLetterStyle letters, int argb) {
  final outline = canvasLetterOutlinePaint(letters);
  if (letters.antialias || outline == null || letters.outlineColor != argb) {
    return null;
  }
  return _coverIn(argb)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = outline.strokeWidth
    ..strokeJoin = outline.strokeJoin;
}

/// The paint of a run that is not a pass's to draw.
final ui.Paint _drawsNothing = ui.Paint()..color = const ui.Color(0x00000000);
