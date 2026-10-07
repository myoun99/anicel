import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../models/text_cel_style.dart';
import 'canvas_letter_style.dart';

/// Sets a canvas text's letters ONCE MORE — each run painted by what
/// [paintOf] says of its letters, null being their own colour.
typedef CanvasLetterSetter =
    TextPainter Function(ui.Paint? Function(TextLetterStyle letters) paintOf);

/// THE PASSES A CANVAS TEXT'S LETTERS ARE DRAWN IN — outline under fill
/// (#15: one rule on every surface), over the whole text, so a letter's
/// outline never covers its neighbour — for the SE name tag
/// (`layoutTextCel`) and a text on a cel (`layoutCelText`) alike (R5 ⓣ:
/// 「ONE canvas-text implementation」).
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
/// painters they always were, drawn as they always were, and a text baked
/// before the switch existed bakes to the bytes it did.
class CanvasLetterPasses {
  CanvasLetterPasses._({
    required this.fill,
    required TextPainter? stroke,
    required List<_HardPass> hardStrokes,
    required List<_HardPass> hardFills,
    required bool hardThroughout,
  }) : _stroke = stroke,
       _hardStrokes = hardStrokes,
       _hardFills = hardFills,
       _hardThroughout = hardThroughout;

  /// The passes of a text whose runs are set in [letters], [set] being how
  /// it sets them.
  ///
  /// [measured] is the text already set in its letters' own colours, where
  /// the caller had to set it to know its size (the SE tag, every frame):
  /// with no hard letter that IS the fill pass, and nothing is set twice.
  /// It is this object's to dispose of from here on.
  factory CanvasLetterPasses.of(
    Iterable<TextLetterStyle> letters,
    CanvasLetterSetter set, {
    TextPainter? measured,
  }) {
    final styles = letters.toList();
    final hard = [
      for (final style in styles)
        if (!style.antialias) style,
    ];
    final TextPainter fill;
    if (hard.isEmpty && measured != null) {
      fill = measured;
    } else {
      measured?.dispose();
      // A hard letter is not this pass's: it names a paint that draws
      // nothing, as a run with no outline does in the outline's pass.
      fill = set((letters) => letters.antialias ? null : _drawsNothing);
    }
    final outlined = styles.any(
      (style) => style.antialias && canvasLetterOutlinePaint(style) != null,
    );
    return CanvasLetterPasses._(
      fill: fill,
      stroke: outlined
          ? set(
              (letters) => letters.antialias
                  // ⚠️A run with no outline still names a paint, one that
                  // draws nothing: painted by its colour it would be drawn
                  // a second time under its own fill, and every soft edge
                  // of it would come out heavier.
                  ? canvasLetterOutlinePaint(letters) ?? _drawsNothing
                  : _drawsNothing,
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
              (letters) => _hardOutlineCover(letters, argb) ?? _drawsNothing,
            ),
          ),
      ],
      hardFills: [
        for (final argb in {for (final style in hard) style.color})
          _hardFillOf(argb, set),
      ],
      hardThroughout: styles.isNotEmpty && hard.length == styles.length,
    );
  }

  /// The hard letters whose colour is [argb], set as cover.
  static _HardPass _hardFillOf(int argb, CanvasLetterSetter set) {
    final cover = _coverIn(argb);
    return (
      argb: argb,
      cover: set(
        (letters) =>
            !letters.antialias && letters.color == argb ? cover : _drawsNothing,
      ),
    );
  }

  /// The letters as the engine sets them — what a caret, a selection and a
  /// press are measured on — and the pass that fills the smooth ones.
  final TextPainter fill;

  /// The smooth letters' outlines; null when none of them wears one.
  final TextPainter? _stroke;

  final List<_HardPass> _hardStrokes;
  final List<_HardPass> _hardFills;

  /// Whether the text has letters and EVERY one of them is hard.
  final bool _hardThroughout;

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
      within: box.inflate(1),
      cover: () => canvas.drawRect(box, _coverIn(argb)),
    );
  }

  /// Draws the letters with their box's corner at [at]. [within] holds
  /// everything they can draw, in the canvas's own space: the hard letters'
  /// layers are no larger.
  void paint(ui.Canvas canvas, ui.Offset at, {required ui.Rect within}) {
    void hard(_HardPass pass) => _drawHard(
      canvas,
      pass.argb,
      within: within,
      cover: () => pass.cover.paint(canvas, at),
    );
    _stroke?.paint(canvas, at);
    _hardStrokes.forEach(hard);
    fill.paint(canvas, at);
    _hardFills.forEach(hard);
  }

  void dispose() {
    fill.dispose();
    _stroke?.dispose();
    for (final pass in [..._hardStrokes, ..._hardFills]) {
      pass.cover.dispose();
    }
  }
}

/// The hard letters of one colour, set as cover ([_coverIn]).
typedef _HardPass = ({int argb, TextPainter cover});

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
void _drawHard(
  ui.Canvas canvas,
  int argb, {
  required ui.Rect within,
  required void Function() cover,
}) {
  final alpha = (argb >> 24) & 0xFF;
  final seeThrough = alpha != 0xFF;
  if (seeThrough) {
    canvas.saveLayer(
      within,
      ui.Paint()..color = ui.Color.fromARGB(alpha, 0, 0, 0),
    );
  }
  canvas.saveLayer(
    within,
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
}

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
