import 'package:flutter/painting.dart';

import '../text/word_condensation.dart';
import 'timeline_cell_style.dart' show timelineTextOnColor;

/// UI-R16: ONE laid-out TextPainter cache for every timeline-family
/// painter (row cell glyphs, ruler labels, x-sheet rail numbers).
/// Text layout is the priciest part of a painter repaint in debug, and
/// the same strings recur endlessly across repaints, rows and panels —
/// cache per (text, style) with LRU eviction.
///
/// ⛔The key is the WHOLE style. It used to be (color, weight, size) —
/// and the painters that set their type from scratch never named a face,
/// so the koma, the rulers and the flip window drew in the OS's font while
/// the names beside them drew in the app's (「앱은 한 글꼴」, 08-28). Once
/// the painters all carry the app's face, the same number in two faces —
/// or two heights, or two spacings — must be two entries, not whichever
/// was laid out first.
final Map<Object, TextPainter> _cache = <Object, TextPainter>{};

/// Roomy enough for the widest live set (a storyboard-zoom ruler shows
/// hundreds of headers × two styles) while bounding memory.
const int _cacheCap = 2048;

/// [maxWidth] turns the glyph into a one-line ELLIPSIZED run — free text
/// (a cut's name) has to stop at its box the way a `Text` with
/// `TextOverflow.ellipsis` did. It joins the cache key: the same string
/// laid out at two widths is two different pictures.
///
/// The style's COLOR is in the key too, which is what lets the
/// ground-law sites ([paintTimelineGlyphOnGround]) share this one cache:
/// the resolved black and white variants of a string are simply two
/// entries, and neither can serve the other's raster.
///
/// [tightening] is what each LETTER GAP gives way ([wordTightening]): the
/// letters before the last are set that much tighter and the last keeps its
/// spacing, so the painter's box is the word's ink. ⛔Not a tighter
/// `letterSpacing` on the whole style: letter spacing follows every letter,
/// the last one too, and a word set that way measured a gap short of its
/// ink — laid by its box, its ink ran off-centre and out of its room.
TextPainter timelineGlyphPainter(
  String text,
  TextStyle style, {
  double? maxWidth,
  double tightening = 0,
}) {
  final key = (text, style, maxWidth, tightening);
  final cached = _cache.remove(key);
  if (cached != null) {
    _cache[key] = cached; // LRU touch.
    return cached;
  }
  final painter = TextPainter(
    text: tightening == 0
        ? TextSpan(text: text, style: style)
        : _tightSpan(text, style, tightening),
    textDirection: TextDirection.ltr,
    maxLines: maxWidth == null ? null : 1,
    ellipsis: maxWidth == null ? null : '…',
  )..layout(maxWidth: maxWidth ?? double.infinity);
  if (_cache.length >= _cacheCap) {
    _cache.remove(_cache.keys.first);
  }
  _cache[key] = painter;
  return painter;
}

TextSpan _tightSpan(String text, TextStyle style, double tightening) {
  final letters = text.runes.toList();
  return TextSpan(
    style: style,
    children: [
      TextSpan(
        text: String.fromCharCodes(letters, 0, letters.length - 1),
        style: TextStyle(
          letterSpacing: (style.letterSpacing ?? 0) - tightening,
        ),
      ),
      TextSpan(text: String.fromCharCode(letters.last)),
    ],
  );
}

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
  final natural = timelineGlyphPainter(text, style);
  final tightening = wordTightening(
    extent: natural.width,
    gaps: wordLetterGaps(text),
    room: room,
  );
  return (
    glyph: tightening == 0
        ? natural
        : timelineGlyphPainter(text, style, tightening: tightening),
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
    timelineGlyphPainter(
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
    painter: timelineGlyphPainter(
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
