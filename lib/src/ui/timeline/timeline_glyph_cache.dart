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
