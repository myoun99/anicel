import 'package:flutter/painting.dart';

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
/// [outlineColor]/[outlineWidth] build the STROKE pass of an outlined
/// glyph (a foreground stroke Paint — `style.color` goes null then, which
/// is why the outline params join the cache key: an outlined and a plain
/// run of the same string must never serve each other's raster).
TextPainter timelineGlyphPainter(
  String text,
  TextStyle style, {
  double? maxWidth,
  Color? outlineColor,
  double outlineWidth = 0,
}) {
  final key = (
    text,
    style.color,
    style.fontWeight,
    style.fontSize,
    maxWidth,
    outlineColor,
    outlineWidth,
  );
  final cached = _cache.remove(key);
  if (cached != null) {
    _cache[key] = cached; // LRU touch.
    return cached;
  }
  final effectiveStyle = outlineColor == null
      ? style
      : style.copyWith(
          color: null,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = outlineWidth
            // Round joins: miter spikes on glyph corners read as dirt at
            // label sizes.
            ..strokeJoin = StrokeJoin.round
            ..color = outlineColor,
        );
  final painter = TextPainter(
    text: TextSpan(text: text, style: effectiveStyle),
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

/// Paints [text] with a bright OUTLINE under the fill (#15: frame names
/// and comma counts read over pictures; on the near-white paper the same
/// outline sinks in unseen, which is what keeps the rule one rule). Two
/// cached glyph passes at one offset — stroke first, fill on top. The
/// stroke pass shares the fill's layout inputs, so the two line up.
void paintTimelineOutlinedGlyph(
  Canvas canvas,
  Offset offset,
  String text,
  TextStyle style, {
  required Color outlineColor,
  double outlineWidth = 2,
  double? maxWidth,
}) {
  timelineGlyphPainter(
    text,
    style,
    maxWidth: maxWidth,
    outlineColor: outlineColor,
    outlineWidth: outlineWidth,
  ).paint(canvas, offset);
  timelineGlyphPainter(text, style, maxWidth: maxWidth).paint(canvas, offset);
}
