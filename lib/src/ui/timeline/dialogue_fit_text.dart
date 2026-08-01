import 'package:flutter/material.dart';

import '../text/dialogue_fit_layout.dart';
import '../text/vertical_writing_text.dart';

/// SE dialogue distributed evenly over the available extent — one glyph per
/// [dialogueGlyphCenters] position along [axis], centered on the cross
/// axis. Mirrors the paper sheet's SE column, where dialogue stretches to
/// fill its covered frames.
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
    return ExcludeSemantics(
      child: CustomPaint(
        painter: _DialogueFitPainter(
          text: text,
          axis: axis,
          color: color,
          fontSize: fontSize,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _DialogueFitPainter extends CustomPainter {
  _DialogueFitPainter({
    required this.text,
    required this.axis,
    required this.color,
    required this.fontSize,
  });

  final String text;
  final Axis axis;
  final Color color;
  final double fontSize;

  @override
  void paint(Canvas canvas, Size size) {
    final glyphs = text.characters.toList(growable: false);
    final mainExtent = axis == Axis.horizontal ? size.width : size.height;
    final centers = dialogueGlyphCenters(
      glyphCount: glyphs.length,
      mainExtent: mainExtent,
    );
    for (var i = 0; i < glyphs.length; i += 1) {
      final painter = TextPainter(
        text: TextSpan(
          text: glyphs[i],
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (axis == Axis.horizontal) {
        painter.paint(
          canvas,
          Offset(
            centers[i] - painter.width / 2,
            (size.height - painter.height) / 2,
          ),
        );
        continue;
      }
      paintVerticalTextCell(
        canvas,
        verticalGlyphCell(glyphs[i]),
        painter: painter,
        center: Offset(size.width / 2, centers[i]),
        fontSize: fontSize,
        maxCrossExtent: size.width,
      );
    }
  }

  @override
  bool shouldRepaint(_DialogueFitPainter oldDelegate) {
    return text != oldDelegate.text ||
        axis != oldDelegate.axis ||
        color != oldDelegate.color ||
        fontSize != oldDelegate.fontSize;
  }
}
