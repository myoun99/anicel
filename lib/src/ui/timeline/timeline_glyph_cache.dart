import 'package:flutter/painting.dart';

import 'timeline_cell_style.dart' show timelineTextOnColor;

/// UI-R16: ONE laid-out TextPainter cache for every timeline-family
/// painter (row cell glyphs, ruler labels, x-sheet rail numbers).
/// Text layout is the priciest part of a painter repaint in debug, and
/// the same strings recur endlessly across repaints, rows and panels —
/// cache per (text, color, weight, size) with LRU eviction.
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
TextPainter timelineGlyphPainter(
  String text,
  TextStyle style, {
  double? maxWidth,
}) {
  final key = (text, style.color, style.fontWeight, style.fontSize, maxWidth);
  final cached = _cache.remove(key);
  if (cached != null) {
    _cache[key] = cached; // LRU touch.
    return cached;
  }
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
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
}) {
  timelineGlyphPainter(
    text,
    style.copyWith(color: timelineTextOnColor(ground)),
    maxWidth: maxWidth,
  ).paint(canvas, offset);
}
