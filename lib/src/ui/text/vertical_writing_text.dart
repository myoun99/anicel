import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'vertical_writing.dart';

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
    final painter = TextPainter(
      text: TextSpan(text: cell.text, style: glyphStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    paintVerticalTextCell(
      canvas,
      cell,
      painter: painter,
      center: Offset(centerX, cellCenterY),
      fontSize: fontSize,
      maxCrossExtent: widthLimit,
      spanExtent: cellSpan,
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
void paintVerticalTextCell(
  Canvas canvas,
  VerticalTextCell cell, {
  required TextPainter painter,
  required Offset center,
  required double fontSize,
  double maxCrossExtent = double.infinity,
  double spanExtent = 0,
}) {
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

  canvas.save();
  switch (cell.form) {
    case VerticalGlyphForm.rotated:
      // Turned 90° clockwise about the cell's centre: the long-vowel bar
      // and the brackets become strokes along the column. Lying down, it
      // is the glyph's HEIGHT that has to clear the column.
      canvas.translate(center.dx, center.dy);
      canvas.rotate(math.pi / 2);
      final scale = fitScale(painter.height);
      if (scale != 1.0) {
        canvas.scale(scale, scale);
      }
    case VerticalGlyphForm.sideways:
      // The word lies down and reads along the column. It is scaled into
      // the slots it reserved (the reservation is an estimate, so this is
      // usually a small trim) and into the column's own width, which the
      // turned glyphs' HEIGHT has to clear.
      canvas.translate(center.dx, center.dy);
      canvas.rotate(math.pi / 2);
      final alongScale =
          spanExtent > 0 && painter.width > spanExtent && painter.width > 0
          ? spanExtent / painter.width
          : 1.0;
      final scale = math.min(alongScale, fitScale(painter.height));
      if (scale != 1.0) {
        canvas.scale(scale, scale);
      }
    case VerticalGlyphForm.tateChuYoko:
      // 縦中横: the digits stay horizontal and condense into the width one
      // upright glyph would have taken.
      canvas.translate(center.dx, center.dy);
      final target = math.min(fontSize, maxCrossExtent);
      final scale = painter.width > target && painter.width > 0
          ? target / painter.width
          : 1.0;
      if (scale != 1.0) {
        canvas.scale(scale, scale);
      }
    case VerticalGlyphForm.shifted:
    case VerticalGlyphForm.upright:
      final shift = cell.shiftEm * fontSize;
      canvas.translate(center.dx + shift, center.dy - shift);
      final scale = fitScale(painter.width);
      if (scale != 1.0) {
        canvas.scale(scale, scale);
      }
  }
  painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
  canvas.restore();
}

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
class VerticalWritingText extends StatelessWidget {
  const VerticalWritingText({
    super.key,
    required this.text,
    this.style,
    this.lineHeight = 1.15,
    this.minFontSize = 1,
    this.tateChuYokoDigits = verticalTateChuYokoDigits,
    this.latinForm = VerticalLatinForm.sideways,
    this.mainAlignment = 0.5,
    this.overflow = VerticalTextOverflow.ellipsis,
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

  @override
  Widget build(BuildContext context) {
    final merged = DefaultTextStyle.of(context).style.merge(style);
    // Accessibility scaling has to reach the FIT, not just the glyphs: the
    // old widget was a FittedBox and got this for free, and scaling only
    // the TextPainters would grow the letters inside cells that stayed the
    // same height. The style carries the scaled size from here on.
    final fontSize = MediaQuery.textScalerOf(
      context,
    ).scale(merged.fontSize ?? 12);
    final resolved = merged.copyWith(fontSize: fontSize);
    // SLOTS, not cells: a sideways word owns several of them.
    final cellCount = verticalTextSpanCount(
      verticalTextCells(
        text,
        tateChuYokoDigits: tateChuYokoDigits,
        latinForm: latinForm,
      ),
    );

    return Semantics(
      label: text,
      child: ExcludeSemantics(
        // An INTRINSIC size, not `SizedBox.expand`: a loose host (the
        // section band's Center) gets the column's natural extent, a tight
        // one gets clamped down and the fit packs to it, and an UNBOUNDED
        // one no longer throws — `SectionBandZone` passes a null extent and
        // is saved today only by the Positioned around it.
        child: CustomPaint(
          // One em across, plus headroom ONLY when something in the text
          // actually moves to a corner. Reserving the spare em always made
          // every SE name pay for a punctuation form they never contain:
          // the 16px name box's FittedBox went width-limited at 16/18 and
          // shrank every label ~11%.
          size: Size(
            fontSize *
                (1 + 2 * _maxShiftEm(text, tateChuYokoDigits, latinForm)),
            cellCount * fontSize * lineHeight,
          ),
          painter: _VerticalWritingPainter(
            text: text,
            style: resolved,
            lineHeight: lineHeight,
            minFontSize: minFontSize,
            tateChuYokoDigits: tateChuYokoDigits,
            latinForm: latinForm,
            mainAlignment: mainAlignment,
            overflow: overflow,
          ),
        ),
      ),
    );
  }
}

/// The largest corner shift anything in [text] takes, as an em fraction —
/// zero for text with no shifted glyph, which is most of it.
double _maxShiftEm(
  String text,
  int tateChuYokoDigits,
  VerticalLatinForm latinForm,
) {
  var most = 0.0;
  for (final cell in verticalTextCells(
    text,
    tateChuYokoDigits: tateChuYokoDigits,
    latinForm: latinForm,
  )) {
    if (cell.shiftEm > most) {
      most = cell.shiftEm;
    }
  }
  return most;
}

class _VerticalWritingPainter extends CustomPainter {
  const _VerticalWritingPainter({
    required this.text,
    required this.style,
    required this.lineHeight,
    required this.minFontSize,
    required this.tateChuYokoDigits,
    required this.latinForm,
    required this.mainAlignment,
    required this.overflow,
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

  @override
  void paint(Canvas canvas, Size size) {
    final fontSize = style.fontSize ?? 12;
    paintVerticalText(
      canvas,
      text,
      style: style,
      centerX: size.width / 2,
      top: 0,
      mainExtent: size.height,
      naturalCellExtent: fontSize * lineHeight,
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
  bool shouldRepaint(_VerticalWritingPainter oldDelegate) {
    return text != oldDelegate.text ||
        style != oldDelegate.style ||
        lineHeight != oldDelegate.lineHeight ||
        minFontSize != oldDelegate.minFontSize ||
        tateChuYokoDigits != oldDelegate.tateChuYokoDigits ||
        latinForm != oldDelegate.latinForm ||
        mainAlignment != oldDelegate.mainAlignment ||
        overflow != oldDelegate.overflow;
  }
}
