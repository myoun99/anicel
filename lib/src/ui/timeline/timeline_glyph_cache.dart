import 'package:flutter/painting.dart';

import '../text/laid_out_glyph.dart';
import '../text/word_condensation.dart';
import 'timeline_cell_style.dart' show timelineTextOnColor;

/// [text] in [style] set onto [room], the length it has along its line: its
/// letter gaps give way first ([wordTightening], F-234-Q1: 「글자 사이부터
/// 줄이기」), and the painter laid that way — whose size is what a word is
/// LAID by ([timelineBlockWordLayout], [wordFit]). What is still too long
/// narrows from there, as every word does.
({TextPainter glyph, double tightening}) timelineWordSetOnto(
  String text,
  TextStyle style,
  double room,
) {
  final natural = laidOutGlyph(text, style);
  final tightening = wordTightening(
    extent: natural.width,
    gaps: wordLetterGaps(text),
    room: room,
  );
  return (
    glyph: tightening == 0
        ? natural
        : laidOutGlyph(text, style, tightening: tightening),
    tightening: tightening,
  );
}

/// Paints [text] in the GROUND LAW's ink (2026-08-17, the difference
/// blend's successor): one solid fill, black or white by [ground]'s
/// luminance ([timelineTextOnColor]) — crisp on any hue, where the
/// difference blend turned navy on the purple blocks and the outline
/// before it wrapped every number in a halo.
///
/// [ground] is the color the glyph actually lands on, composited: the
/// block's paper, the band's fill, the lane — whatever the CALLER knows
/// it painted there. The law supersedes `style.color` (which stays what
/// it always was at these sites: layout identity), and the resolved
/// solid joins the shared cache key through the style's color slot.
void paintTimelineGlyphOnGround(
  Canvas canvas,
  Offset offset,
  String text,
  TextStyle style, {
  required Color ground,
  double? maxWidth,
  WordFit fit = wordFitsAsItIs,
  double tightening = 0,
}) {
  paintFittedText(
    canvas,
    laidOutGlyph(
      text,
      style.copyWith(color: timelineTextOnColor(ground)),
      maxWidth: maxWidth,
      tightening: tightening,
    ),
    offset,
    fit,
  );
}

/// A laid-out glyph, where it lands and how it is narrowed: a strip's
/// writing as VALUES, so what one piece would overlap can be asked before
/// anything is painted (I-16: the playhead's pair covers what it touches).
typedef TimelineGlyphPlacement = ({
  TextPainter painter,
  Offset offset,
  WordFit fit,
});

extension TimelineGlyphPlacementPaint on TimelineGlyphPlacement {
  /// The box the glyph covers — as drawn, narrowed when it is.
  Rect get rect =>
      offset & Size(painter.width * fit.x, painter.height * fit.y);

  void paint(Canvas canvas) => paintFittedText(canvas, painter, offset, fit);
}

/// The seconds index on a boundary cell's LEADING CORNER (UI-R10 #27):
/// two pixels in from the corner, bold, on the surface-variant ink.
///
/// ⛔THE CORNER IS THE SHARED ANSWER. Both frame rails place it here, and
/// the vertical one's comment says it "converges on the SHARED ruler's
/// answers" — but each wrote the offset out, so the convergence was a
/// promise rather than a fact.
///
/// ⚠️THE SIZE IS THE RAIL'S OWN, not shared: the vertical rail narrowed to
/// 28px (R10 R6) and prints a point smaller than the horizontal ruler. The
/// FACE is the strip's too (`TimelineRulerScale.face`) — set from scratch,
/// the second named none and wrote in the OS's font.
TimelineGlyphPlacement? secondsCornerGlyph(
  Rect rect,
  ({String text, double fontSize, Color color, TextStyle face}) seconds,
) {
  if (seconds.text.isEmpty) {
    return null;
  }
  return (
    painter: laidOutGlyph(
      seconds.text,
      timelineSecondsType(
        seconds.face,
        seconds.fontSize,
      ).copyWith(color: seconds.color),
    ),
    offset: Offset(rect.left + 2, rect.top + 1),
    fit: wordFitsAsItIs,
  );
}

/// The type a seconds index is set in — bold, in a strip's [face] at the
/// strip's own [fontSize] — for the corner that writes it
/// ([secondsCornerGlyph]) and the cadence that measures it.
TextStyle timelineSecondsType(TextStyle face, double fontSize) =>
    face.copyWith(fontSize: fontSize, fontWeight: FontWeight.w700);
