import 'package:flutter/material.dart';

import '../text/dialogue_fit_layout.dart';
import '../text/dialogue_fit_paint.dart';
import '../text/word_condensation.dart';
import 'axis_turn.dart';
import '../repaint_props.dart';

/// SE dialogue distributed evenly over the available extent — one glyph per
/// [dialogueGlyphCenters] position along [axis], centered on the cross
/// axis. Mirrors the paper sheet's SE column, where dialogue stretches to
/// fill its covered frames.
///
/// A glyph longer than its cell narrows into it along [axis] — F-93, the
/// rule every block word keeps since 2026-09-24 ([wordCondensation]) — and
/// across it narrows only where the row is shorter than the glyph.
///
/// Down a COLUMN the glyphs take their vertical-writing forms, through the
/// shared table. They used not to: the class doc said "every glyph painted
/// upright (never rotated)", so a long-vowel bar in `ドアー` stayed lying
/// across the column while the same character rotated everywhere else on
/// the sheet. The spacing rule is the dialogue's own; the FORM rule is the
/// app's one table.
class DialogueFitText extends StatelessWidget {
  const DialogueFitText({
    super.key,
    required this.text,
    required this.axis,
    required this.color,
    this.fontSize = 12,
  });

  final String text;
  final Axis axis;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    // The app's FACE and nothing else of the ambient style: a painter set
    // from a bare `TextStyle` names no face and draws in the OS's (「앱은 한
    // 글꼴」, 08-28), but the ambient line height would grow every glyph's
    // box past the cell it is spread into.
    final ambient = DefaultTextStyle.of(context).style;
    return ExcludeSemantics(
      child: CustomPaint(
        painter: _DialogueFitPainter(
          text: text,
          axis: axis,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            fontFamily: ambient.fontFamily,
            fontFamilyFallback: ambient.fontFamilyFallback,
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _DialogueFitPainter extends CustomPainter with RepaintOnProps {
  _DialogueFitPainter({
    required this.text,
    required this.axis,
    required this.style,
  });

  final String text;
  final Axis axis;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    if (axis == Axis.vertical) {
      paintDialogueFitColumn(
        canvas,
        text,
        topCenter: Offset(size.width / 2, 0),
        extent: size.height,
        style: style,
        maxCrossExtent: size.width,
      );
      return;
    }
    final glyphs = text.characters.toList(growable: false);
    final mainExtent = extentAlong(axis, size);
    final centers = dialogueGlyphCenters(
      glyphCount: glyphs.length,
      mainExtent: mainExtent,
    );
    final cellExtent = dialogueGlyphCellExtent(
      glyphCount: glyphs.length,
      mainExtent: mainExtent,
    );
    for (var i = 0; i < glyphs.length; i += 1) {
      final painter = TextPainter(
        text: TextSpan(text: glyphs[i], style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final fit = wordFit(painter.size, Size(cellExtent, size.height));
      paintFittedText(
        canvas,
        painter,
        Offset(
          centers[i] - painter.width * fit.x / 2,
          (size.height - painter.height * fit.y) / 2,
        ),
        fit,
      );
    }
  }

  @override
  Object get props => (text, axis, style);
}
