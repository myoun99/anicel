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
/// [inverting] builds the SELF-INVERTING variant of the run (a white
/// foreground Paint in [BlendMode.difference] — `style.color` goes null
/// then, which is why the flag joins the cache key: an inverting and a
/// plain run of the same string must never serve each other's raster).
TextPainter timelineGlyphPainter(
  String text,
  TextStyle style, {
  double? maxWidth,
  bool inverting = false,
}) {
  final key = (
    text,
    style.color,
    style.fontWeight,
    style.fontSize,
    maxWidth,
    inverting,
  );
  final cached = _cache.remove(key);
  if (cached != null) {
    _cache[key] = cached; // LRU touch.
    return cached;
  }
  final effectiveStyle = !inverting
      ? style
      : style.copyWith(
          color: null,
          foreground: Paint()
            ..color = const Color(0xFFFFFFFF)
            ..blendMode = BlendMode.difference,
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

/// Paints [text] as SELF-INVERTING ink (2026-08-17, the #15 outline's
/// successor): ONE white fill whose Paint blends with
/// [BlendMode.difference], so every glyph pixel flips against whatever the
/// block already painted beneath it — dark digits on the near-white paper,
/// light digits over dark lanes and pictures, with no outline pass at all.
/// The bright-stroke-under-fill pair this replaces carried the number over
/// pictures by wrapping it in a halo; the difference blend gets the same
/// legibility from the destination pixels themselves.
///
/// ⚠️The glyph must land in the SAME raster as the pixels it inverts
/// against: difference against a not-yet-composited transparent backdrop
/// resolves to the plain white fill.
void paintTimelineInvertingGlyph(
  Canvas canvas,
  Offset offset,
  String text,
  TextStyle style, {
  double? maxWidth,
}) {
  timelineGlyphPainter(
    text,
    style,
    maxWidth: maxWidth,
    inverting: true,
  ).paint(canvas, offset);
}
