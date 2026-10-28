import 'package:flutter/material.dart';

import '../../models/se_dialogue_spacing.dart';
import '../text/app_face.dart';
import '../text/dialogue_fit_layout.dart';
import '../text/dialogue_fit_paint.dart';
import '../text/laid_out_glyph.dart';
import '../text/word_bake.dart' show RepaintOnWordBakes;
import '../text/word_condensation.dart';
import 'axis_turn.dart';
import 'timeline_cell_style.dart';
import '../repaint_props.dart';

/// SE dialogue along its block — each glyph on the frame its block's
/// [spacing] stands it on ([dialogueGlyphSlots], F-496 ③), centred on the
/// cross axis. The paper sheet's SE column lays it so too.
///
/// A glyph is a block word ([timelineBlockWordLayout]): centred on its frame
/// while it fits it, growing on into the frames its koma give it past that,
/// and narrowing along [axis] only past those — F-93, the rule every block
/// word keeps since 2026-09-24 ([wordCondensation]) — and across only where
/// the row is shorter than the glyph.
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
    required this.frames,
    required this.spacing,
    this.fontSize = 12,
    this.shownFromPart = 0,
  });

  final String text;
  final Axis axis;
  final Color color;

  /// How many frames the box runs along [axis] — what [spacing] counts in.
  final int frames;
  final SeDialogueSpacing spacing;
  final double fontSize;

  /// Where along the text's length a window on it opens, as a part of the
  /// whole: the text is laid out over all of it, and only the glyphs whose
  /// frame the window holds are painted, each whole and where that layout
  /// lays it — the sheet's column paints its part so too
  /// ([paintDialogueFitColumn]). A part rather than pixels: a zoom repaints
  /// it and does not build it again.
  final double shownFromPart;

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
          frames: frames,
          spacing: spacing,
          style: dialogueFitStyle(context, color: color, fontSize: fontSize),
          shownFromPart: shownFromPart,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// The dialogue's print — what [DialogueFitText] paints it in, and what a
/// host measuring it before laying it out has to measure it in.
TextStyle dialogueFitStyle(
  BuildContext context, {
  required Color color,
  double fontSize = 12,
}) => appFaceOf(DefaultTextStyle.of(context).style).copyWith(
  color: color,
  fontSize: fontSize,
  fontWeight: FontWeight.w600,
);

class _DialogueFitPainter extends CustomPainter
    with RepaintOnProps, RepaintOnWordBakes {
  _DialogueFitPainter({
    required this.text,
    required this.axis,
    required this.frames,
    required this.spacing,
    required this.style,
    required this.shownFromPart,
  });

  final String text;
  final Axis axis;
  final int frames;
  final SeDialogueSpacing spacing;
  final TextStyle style;
  final double shownFromPart;

  @override
  void paintWords(Canvas canvas, Size size) {
    if (axis == Axis.vertical) {
      paintDialogueFitColumn(
        canvas,
        text,
        topCenter: Offset(size.width / 2, 0),
        extent: size.height,
        frames: frames,
        spacing: spacing,
        style: style,
        setWord: paintFittedText,
        maxCrossExtent: size.width,
        shownFrom: size.height * shownFromPart,
      );
      return;
    }
    final glyphs = text.characters.toList(growable: false);
    final mainExtent = extentAlong(axis, size);
    final slots = dialogueGlyphSlots(
      glyphCount: glyphs.length,
      frames: frames,
      mainExtent: mainExtent,
      spacing: spacing,
    );
    final shown = dialogueGlyphsShownIn(
      slots,
      from: mainExtent * shownFromPart,
    );
    for (var i = shown.first; i < shown.end; i += 1) {
      final glyph = laidOutGlyph(glyphs[i], style);
      final slot = slots[i];
      final (:origin, :fit) = timelineBlockWordLayout(glyph.size, (
        axis: axis,
        room: Rect.fromLTWH(slot.cellStart, 0, slot.roomExtent, size.height),
        cellStart: slot.cellStart,
        cellExtent: slot.cellExtent,
        growth: TimelineBlockWordGrowth.towardBlockEnd,
        acrossAlignment: 0,
      ));
      paintFittedText(canvas, glyph, origin, fit);
    }
  }

  @override
  Object get props => (text, axis, frames, spacing, style, shownFromPart);
}
