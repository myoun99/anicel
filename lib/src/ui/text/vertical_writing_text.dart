import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'laid_out_glyph.dart';
import 'vertical_writing.dart';
import 'word_bake.dart' show RepaintOnWordBakes;
import 'word_condensation.dart';
import '../repaint_props.dart';
import '../timeline/memo_token.dart' show ByList;
import '../widgets/ground_ink_writing.dart' show GroundInkRun;

// Hosts pick a Latin form when they mount the widget, so the choice has to
// travel with the renderer they already import — the table itself stays a
// pure library nobody else needs to reach.
export 'vertical_writing.dart' show VerticalLatinForm;

/// The ONE renderer for Japanese vertical writing — [paintVerticalText] for
/// canvases and [VerticalWritingText] for the widget tree, both reading the
/// table in `vertical_writing.dart`.
///
/// The widget is a painter underneath rather than a `Column` of `Text`,
/// because a column of Texts cannot rotate a bracket, cannot lean a small
/// kana, and cannot put two digits in one cell — and going through the same
/// code as the timesheet is the only way the two stay agreed.

/// Paints [text] as a vertical column of glyph cells.
///
/// The column starts at [top] and runs [mainExtent] down, centered on
/// [centerX]. [style]'s `fontSize` is the MAXIMUM: a column with more cells
/// than the span holds packs tighter and shrinks (see [verticalTextFit]).
/// [mainAlignment] places the packed block inside the span — 0 starts at
/// [top] (the timesheet's notation words begin on their span's first row),
/// 0.5 centers it (the section band).
///
/// Returns the extent actually painted.
///
/// [style]'s `fontSize` is taken as already scaled: text scaling is the
/// WIDGET's business (it owns the MediaQuery, and the scaled size has to
/// reach the fit math or the glyphs grow while their cells do not). A
/// canvas host with fixed paper geometry — the timesheet — has no scaler
/// and wants none.
/// What a column does when it is longer than the space it was given.
enum VerticalTextOverflow {
  /// Cells pack tighter and the glyphs shrink with them. The PRINT
  /// timesheet's rule (squeezing a notation word into its span is a paper
  /// convention — `リ/ピ/ー/ト`) — and, since A6 (2026-08-17), the layer
  /// colour label's: the user's spec says a long colour name shrinks
  /// (「길면 글자 축소 허용」). Everything else on screen ellipsises.
  pack,

  /// Cells keep their size and the tail is replaced by an ellipsis. Every
  /// screen surface, since the rail-window round: nothing shrinks to fit
  /// anywhere anymore.
  ellipsis,
}

double paintVerticalText(
  Canvas canvas,
  String text, {
  required TextStyle style,
  required double centerX,
  required double top,
  required double mainExtent,
  required double naturalCellExtent,

  /// How the host sets a glyph: a screen's from its bake, paper's scaled
  /// ([WordSetter]).
  required WordSetter setWord,

  /// The whole column narrowed about the canvas origin, on the screen's
  /// axes — what `canvas.scale` around this call would draw, handed down
  /// so each glyph is SET at its narrowing rather than scaled after it
  /// (F-224: scaled, a narrowed glyph speckles). The extent this returns
  /// is the column's own, before it.
  WordFit narrowing = wordFitsAsItIs,
  double minFontSize = 4,
  double cellPadding = 3,
  double? maxCellWidth,
  double mainAlignment = 0,
  int tateChuYokoDigits = verticalTateChuYokoDigits,
  VerticalLatinForm latinForm = VerticalLatinForm.sideways,
  VerticalTextOverflow overflow = VerticalTextOverflow.pack,
}) {
  var cells = verticalTextCells(
    text,
    tateChuYokoDigits: tateChuYokoDigits,
    latinForm: latinForm,
  );
  if (cells.isEmpty) {
    return 0;
  }
  if (overflow == VerticalTextOverflow.ellipsis && naturalCellExtent > 0) {
    cells = verticalTextCellsWithin(
      cells,
      capacityCells: verticalTextCapacityCells(
        mainExtent: mainExtent,
        naturalCellExtent: naturalCellExtent,
      ),
    );
    if (cells.isEmpty) {
      return 0;
    }
  }
  final fit = verticalTextFit(
    cellCount: verticalTextSpanCount(cells),
    mainExtent: mainExtent,
    naturalCellExtent: naturalCellExtent,
    maxFontSize: style.fontSize ?? 12,
    minFontSize: minFontSize,
    cellPadding: cellPadding,
  );
  final fontSize = fit.fontSize;
  if (fontSize <= 0) {
    return 0;
  }
  // Letter spacing is a HORIZONTAL notion; in a vertical column it would
  // only pad each glyph's box sideways and pull it off centre, so it is
  // dropped here and the leading comes from the cell extent instead.
  final glyphStyle = style.copyWith(
    fontSize: fontSize,
    letterSpacing: 0,
    height: 1.0,
  );
  final start = top + (mainExtent - fit.totalExtent) * mainAlignment;
  final widthLimit = maxCellWidth ?? double.infinity;

  var slot = 0;
  for (var index = 0; index < cells.length; index += 1) {
    final cell = cells[index];
    // A sideways run owns several slots, so its centre is the centre of the
    // whole span, not of one cell.
    final cellSpan = cell.spanCells * fit.cellExtent;
    final cellCenterY = start + slot * fit.cellExtent + cellSpan / 2;
    slot += cell.spanCells;

    paintVerticalTextCell(
      canvas,
      cell,
      painter: laidOutGlyph(cell.text, glyphStyle),
      center: Offset(centerX, cellCenterY),
      fontSize: fontSize,
      maxCrossExtent: widthLimit,
      spanExtent: cellSpan,
      setWord: setWord,
      narrowing: narrowing,
    );
  }
  return fit.totalExtent;
}

/// Paints ONE already-laid-out cell centred on [center], applying the form
/// table's rotation, lean and condensation.
///
/// Split out of [paintVerticalText] for hosts that place their own cells:
/// the SE dialogue spreads its glyphs evenly over the frames a block covers
/// (`dialogueGlyphCenters`) rather than stacking them at a fixed leading,
/// so it cannot go through the column renderer — but it must still ROTATE
/// what the table rotates. Both the screen overlay and the printed sheet
/// were placing dialogue glyphs upright, which left `ー` a horizontal bar
/// in the one place a vertical column makes it most obvious.
///
/// [alongColumnScale] lets such a host narrow a glyph DOWN the column
/// alone: it is handed the glyph's advance there, once the form and the
/// width fit are applied, and answers the factor. SE dialogue passes it so
/// a glyph keeps to its frame cell (F-93).
///
/// [narrowing] and [setWord] are the column's ([paintVerticalText]): the
/// cell sits where the narrowed column puts it and is set at its share.
void paintVerticalTextCell(
  Canvas canvas,
  VerticalTextCell cell, {
  required TextPainter painter,
  required Offset center,
  required double fontSize,
  required WordSetter setWord,
  WordFit narrowing = wordFitsAsItIs,
  double maxCrossExtent = double.infinity,
  double spanExtent = 0,
  double Function(double extentAlongColumn)? alongColumnScale,
}) {
  // ↩️F-93 (유저 2026-09-12): DOWN the column a glyph may still be narrowed
  // on that one axis, through [alongColumnScale] — SE dialogue asks for it
  // when its glyphs outnumber the room: 「이렇게 겹쳐질땐 글자 한글자의 좌우
  // 길이? 를 줄여서 한 칸에 한 글자라는 느낌이 나도록」. The width rule
  // ([verticalGlyphFit]) stands.
  final (:turned, :scale) = verticalGlyphFit(
    cell,
    painter: painter,
    fontSize: fontSize,
    room: (across: maxCrossExtent, span: spanExtent),
  );
  final along =
      alongColumnScale?.call(
        verticalGlyphAdvance(
          turned: turned,
          painter: painter,
          fontSize: fontSize,
          scale: scale,
        ),
      ) ??
      1.0;
  // The glyph's own narrowing, the column's [narrowing] in it — which a
  // glyph lying down the column takes across its own axes.
  final fit = turned
      ? (x: narrowing.y * scale * along, y: narrowing.x * scale)
      : (x: narrowing.x * scale, y: narrowing.y * scale * along);
  canvas.save();
  switch (cell.form) {
    case VerticalGlyphForm.rotated:
    case VerticalGlyphForm.sideways:
      // Turned 90° clockwise about the cell's centre ([verticalGlyphFit]).
      canvas.translate(narrowing.x * center.dx, narrowing.y * center.dy);
      canvas.rotate(math.pi / 2);
    case VerticalGlyphForm.tateChuYoko:
      canvas.translate(narrowing.x * center.dx, narrowing.y * center.dy);
    case VerticalGlyphForm.shifted:
    case VerticalGlyphForm.upright:
      final shift = cell.shiftEm * fontSize;
      canvas.translate(
        narrowing.x * (center.dx + shift),
        narrowing.y * (center.dy - shift),
      );
  }
  setWord(
    canvas,
    painter,
    Offset(-painter.width * fit.x / 2, -painter.height * fit.y / 2),
    fit,
  );
  canvas.restore();
}

/// How a glyph of [cell] stands in a column `room.across` wide: whether it
/// lies DOWN the column, and the uniform scale that fits it across — what
/// [paintVerticalTextCell] draws, and what a host that measures a column
/// before drawing it asks ([verticalGlyphAdvance]). `room.span` is the
/// length a sideways word reserved down the column (0: none).
({bool turned, double scale}) verticalGlyphFit(
  VerticalTextCell cell, {
  required TextPainter painter,
  required double fontSize,
  ({double across, double span}) room = (
    across: double.infinity,
    span: 0,
  ),
}) {
  final maxCrossExtent = room.across;
  final spanExtent = room.span;
  // Every form scales UNIFORMLY when it is wider than the column allows —
  // never anamorphically. A 縦中横 pair squeezed on one axis alone reads
  // as a font bug, and the SE columns really do get this narrow: a
  // four-column SE group is 10px per column, so the limit is reachable,
  // not theoretical.
  double fitScale(double extentAcrossColumn) {
    return extentAcrossColumn > maxCrossExtent && extentAcrossColumn > 0
        ? maxCrossExtent / extentAcrossColumn
        : 1.0;
  }

  return switch (cell.form) {
    // Turned 90° clockwise about the cell's centre: the long-vowel bar and
    // the brackets become strokes along the column. Lying down, it is the
    // glyph's HEIGHT that has to clear the column.
    VerticalGlyphForm.rotated => (turned: true, scale: fitScale(painter.height)),
    // The word lies down and reads along the column. It is scaled into the
    // slots it reserved (the reservation is an estimate, so this is usually
    // a small trim) and into the column's own width, which the turned
    // glyphs' HEIGHT has to clear.
    VerticalGlyphForm.sideways => (
      turned: true,
      scale: math.min(
        spanExtent > 0 && painter.width > spanExtent && painter.width > 0
            ? spanExtent / painter.width
            : 1.0,
        fitScale(painter.height),
      ),
    ),
    // 縦中横: the digits stay horizontal and condense into the width one
    // upright glyph would have taken.
    VerticalGlyphForm.tateChuYoko => (
      turned: false,
      scale: painter.width > math.min(fontSize, maxCrossExtent) &&
              painter.width > 0
          ? math.min(fontSize, maxCrossExtent) / painter.width
          : 1.0,
    ),
    VerticalGlyphForm.shifted || VerticalGlyphForm.upright => (
      turned: false,
      scale: fitScale(painter.width),
    ),
  };
}

/// How far a glyph advances DOWN a column: a standing glyph an em, a turned
/// one its width — after the [scale] that fits it across the column.
double verticalGlyphAdvance({
  required bool turned,
  required TextPainter painter,
  required double fontSize,
  required double scale,
}) => (turned ? painter.width : fontSize) * scale;

/// The single-glyph cell [glyph] becomes in a vertical column — the form
/// table applied without any run grouping, for the dialogue placers.
VerticalTextCell verticalGlyphCell(String glyph) => VerticalTextCell(
  text: glyph,
  form: verticalGlyphForm(glyph),
  shiftEm: verticalGlyphShiftEm(glyph),
);

/// Vertical writing in the widget tree: one glyph cell per line, top to
/// bottom, rotating and leaning and pairing digits exactly as the timesheet
/// painter does. Exposes ONE semantics node carrying the whole [text].
///
/// Replaces the old `UprightVerticalText`, whose name was the bug: it
/// stacked every character upright, so `ー` stayed a horizontal bar in the
/// section band while the timesheet had rotated it since UI-R13 #3.
///
/// ★ONE BOX ([RenderVerticalWriting]): the column paints, sizes and says
/// itself, as a built block word does (`RenderTimelineBuiltWord`).
/// ↩️It was a `Semantics` over an `ExcludeSemantics` over a `CustomPaint`,
/// built by a widget of its own — four elements for every upright word on
/// a rail row, paid on every panel reopen (card
/// frame-panels-build-in-one-frame, 2026-10-25).
class VerticalWritingText extends LeafRenderObjectWidget {
  const VerticalWritingText({
    super.key,
    required this.text,
    this.style,
    this.lineHeight = verticalWritingLineHeight,
    this.minFontSize = 1,
    this.tateChuYokoDigits = verticalTateChuYokoDigits,
    this.latinForm = VerticalLatinForm.sideways,
    this.mainAlignment = 0.5,
    this.overflow = VerticalTextOverflow.ellipsis,
    this.endInset = 0,
    this.inks,
  });

  final String text;
  final TextStyle? style;

  /// The natural cell extent as a multiple of the font size — the leading
  /// between glyphs when the column is not cramped.
  final double lineHeight;

  /// Only consulted with [VerticalTextOverflow.pack]; the default ELLIPSIS
  /// mode keeps the size it was given.
  final double minFontSize;

  final int tateChuYokoDigits;

  /// Whether Latin words lie down or stand up; see [VerticalLatinForm].
  final VerticalLatinForm latinForm;

  /// Where the packed column sits inside the host's extent — 0 starts at
  /// the top, 0.5 centers it, 1 ends at the bottom.
  ///
  /// The default centers, which is what every caller got when this was a
  /// hardcoded 0.5. The x-sheet's rail labels pass 0: the horizontal rail
  /// starts its names at the row's leading edge, and "the same alignment,
  /// transposed" is the whole rule the two surfaces are supposed to share.
  final double mainAlignment;

  /// What a column too long for its host does. Ellipsis by default (the
  /// rail-window round's rule everywhere on screen); the print timesheet
  /// packs, and it goes through [paintVerticalText] directly.
  final VerticalTextOverflow overflow;

  /// What the column keeps clear at each end of the box — a stood bar's
  /// track inset; the box itself, and so [inks], still runs the whole
  /// length.
  final double endInset;

  /// The ground under the column, top to bottom ([GroundInkRun], as
  /// fractions of the box's height), each stretch of the column taking its
  /// run's ink — the text-on-ground law ([GroundInkWriting]) standing up.
  /// Null: one ink, the style's.
  ///
  /// ⚠️Not the gradient a lying writing wears: a column sets each glyph at
  /// its own cell, so a shader would start again in every cell. The column
  /// is set once per run instead, clipped to its stretch.
  final List<GroundInkRun>? inks;

  /// The style the column is set in where [context] shows it.
  ///
  /// Accessibility scaling has to reach the FIT, not just the glyphs: the
  /// old widget was a FittedBox and got this for free, and scaling only the
  /// TextPainters would grow the letters inside cells that stayed the same
  /// height. The style carries the scaled size from here on.
  TextStyle _styleIn(BuildContext context) {
    final merged = DefaultTextStyle.of(context).style.merge(style);
    return merged.copyWith(
      fontSize: MediaQuery.textScalerOf(context).scale(merged.fontSize ?? 12),
    );
  }

  /// The box the column asks for where [context] shows it — its natural
  /// leading and its [endInset]s: what a host that sizes itself around the
  /// column measures before it builds one.
  Size naturalSizeIn(BuildContext context) {
    final natural = verticalWritingNaturalBox(
      verticalTextCells(
        text,
        tateChuYokoDigits: tateChuYokoDigits,
        latinForm: latinForm,
      ),
      fontSize: _styleIn(context).fontSize!,
      lineHeight: lineHeight,
    ).size;
    return Size(natural.width, natural.height + endInset * 2);
  }

  /// What paints the column where [context] shows it, at whatever size it is
  /// painted in — what a box that lays its columns itself (a label plate)
  /// paints each with. It repaints its listeners when a word it drew from a
  /// stand-in has its bake land ([RepaintOnWordBakes]).
  CustomPainter painterIn(BuildContext context) =>
      _VerticalWritingPainter(
        text: text,
        style: _styleIn(context),
        lineHeight: lineHeight,
        minFontSize: minFontSize,
        tateChuYokoDigits: tateChuYokoDigits,
        latinForm: latinForm,
        mainAlignment: mainAlignment,
        overflow: overflow,
        endInset: endInset,
        inks: inks,
      );

  // An INTRINSIC size, not `SizedBox.expand`: a loose host (the section
  // band's Center) gets the column's natural extent, a tight one gets
  // clamped down and the fit packs to it, and an UNBOUNDED one no longer
  // throws — `SectionBandZone` passes a null extent and is saved today only
  // by the Positioned around it.
  @override
  RenderVerticalWriting createRenderObject(BuildContext context) =>
      RenderVerticalWriting(
        text: text,
        textDirection: Directionality.maybeOf(context),
        painter: painterIn(context),
        preferredSize: naturalSizeIn(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderVerticalWriting renderObject,
  ) {
    renderObject
      ..text = text
      ..textDirection = Directionality.maybeOf(context)
      ..painter = painterIn(context)
      ..preferredSize = naturalSizeIn(context);
  }
}

/// A column that paints itself, takes its natural size and says its [text]
/// to a screen reader — the one box a [VerticalWritingText] stands for.
///
/// ★It says the text on the node above it, as the `Semantics` it replaces
/// did: no node of its own, its painter carrying none.
class RenderVerticalWriting extends RenderCustomPaint {
  RenderVerticalWriting({
    required String text,
    required TextDirection? textDirection,
    required super.painter,
    required super.preferredSize,
  }) : _text = text,
       _textDirection = textDirection;

  String _text;
  String get text => _text;
  set text(String value) {
    if (value == _text) {
      return;
    }
    _text = value;
    markNeedsSemanticsUpdate();
  }

  TextDirection? _textDirection;
  TextDirection? get textDirection => _textDirection;
  set textDirection(TextDirection? value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    markNeedsSemanticsUpdate();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _text
      ..textDirection = _textDirection;
  }
}

/// A column's slot, in ems, where its host names none: the glyph and the
/// leading after it.
const double verticalWritingLineHeight = 1.15;

/// The box a column of [cells] ([verticalTextCells]) takes at its natural
/// leading, and how many SLOTS it runs down — slots, not cells: a sideways
/// word owns several.
///
/// One em across, plus headroom ONLY when something in the text actually
/// moves to a corner. Reserving the spare em always made every SE name pay
/// for a punctuation form they never contain: the 16px name box's
/// FittedBox went width-limited at 16/18 and shrank every label ~11%.
({Size size, int slots}) verticalWritingNaturalBox(
  List<VerticalTextCell> cells, {
  required double fontSize,
  required double lineHeight,
}) {
  final cellCount = verticalTextSpanCount(cells);
  return (
    size: Size(
      fontSize * (1 + 2 * _maxShiftEm(cells)),
      cellCount * fontSize * lineHeight,
    ),
    slots: cellCount,
  );
}

/// The largest corner shift any of [cells] takes, as an em fraction — zero
/// for text with no shifted glyph, which is most of it.
double _maxShiftEm(List<VerticalTextCell> cells) {
  var most = 0.0;
  for (final cell in cells) {
    if (cell.shiftEm > most) {
      most = cell.shiftEm;
    }
  }
  return most;
}

class _VerticalWritingPainter extends CustomPainter
    with RepaintOnProps, RepaintOnWordBakes {
  const _VerticalWritingPainter({
    required this.text,
    required this.style,
    required this.lineHeight,
    required this.minFontSize,
    required this.tateChuYokoDigits,
    required this.latinForm,
    required this.mainAlignment,
    required this.overflow,
    required this.endInset,
    required this.inks,
  });

  final String text;

  /// Already carries the text-scaled font size (see the widget's build).
  final TextStyle style;
  final double lineHeight;
  final double minFontSize;
  final int tateChuYokoDigits;
  final VerticalLatinForm latinForm;
  final double mainAlignment;
  final VerticalTextOverflow overflow;
  final double endInset;
  final List<GroundInkRun>? inks;

  @override
  void paintWords(Canvas canvas, Size size) {
    final inks = this.inks;
    if (inks == null) {
      _paintColumn(canvas, size, style);
      return;
    }
    var start = 0.0;
    for (final run in inks) {
      canvas
        ..save()
        ..clipRect(
          Rect.fromLTRB(
            0,
            start * size.height,
            size.width,
            run.end * size.height,
          ),
        );
      _paintColumn(canvas, size, style.copyWith(color: run.ink));
      canvas.restore();
      start = run.end;
    }
  }

  void _paintColumn(Canvas canvas, Size size, TextStyle style) {
    final fontSize = style.fontSize ?? 12;
    paintVerticalText(
      canvas,
      text,
      style: style,
      centerX: size.width / 2,
      top: endInset,
      mainExtent: math.max(0, size.height - endInset * 2),
      naturalCellExtent: fontSize * lineHeight,
      setWord: paintFittedText,
      // The leading is proportional here, unlike the timesheet's fixed-row
      // sheet: at the natural extent this returns the full font size, and
      // as cells pack it gives the leading back first.
      cellPadding: fontSize * (lineHeight - 1),
      maxCellWidth: size.width,
      mainAlignment: mainAlignment,
      minFontSize: minFontSize,
      tateChuYokoDigits: tateChuYokoDigits,
      latinForm: latinForm,
      overflow: overflow,
    );
  }

  @override
  Object get props => (
    text,
    style,
    lineHeight,
    minFontSize,
    tateChuYokoDigits,
    latinForm,
    mainAlignment,
    overflow,
    endInset,
    inks == null ? null : ByList(inks!),
  );
}
