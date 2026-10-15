import 'package:flutter/painting.dart';

/// UI-R16: ONE laid-out TextPainter cache for every painter that sets
/// writing glyph by glyph or word by word — the timeline family (row cell
/// glyphs, ruler labels, x-sheet rail numbers), the vertical-writing
/// renderer and the SE dialogue's placers.
/// Text layout is the priciest part of a painter repaint in debug, and
/// the same strings recur endlessly across repaints, rows and panels —
/// cache per (text, style) with LRU eviction.
///
/// 🚨I-57 (10-13, profile, the user's project): the dialogue's placers and
/// the vertical-writing renderer laid each glyph out afresh at every paint,
/// and an SE span measured its dialogue the same way at every layout — a
/// cut crossing built every one of them again. They lay out from here, so
/// it lives with them in `text/`: the timeline reaches the vertical writer
/// (`axis_turn.dart`), and the cache in `timeline/` would have closed the
/// circle.
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
/// ground-law sites (a glyph inked by the ground it stands on) share this
/// one cache: the resolved black and white variants of a string are simply
/// two entries, and neither can serve the other's raster.
///
/// [tightening] is what each LETTER GAP gives way (`wordTightening`): the
/// letters before the last are set that much tighter and the last keeps its
/// spacing, so the painter's box is the word's ink. ⛔Not a tighter
/// `letterSpacing` on the whole style: letter spacing follows every letter,
/// the last one too, and a word set that way measured a gap short of its
/// ink — laid by its box, its ink ran off-centre and out of its room.
TextPainter laidOutGlyph(
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
