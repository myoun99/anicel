import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart' show CustomPainter, RendererBinding;
import 'package:flutter/scheduler.dart';

import '../../core/bake_once_lru.dart';
import '../../services/straight_rgba_image.dart' show uploadRawRgba;

/// A word's coverage as its final device pixels: [alpha] is [width] ×
/// [height], one byte a pixel, with a one-pixel margin on every side; the
/// ink fills [logicalWidth] × [logicalHeight] logical pixels — the size a
/// classic pass centres the word on.
class BakedWordCoverage {
  const BakedWordCoverage({
    required this.width,
    required this.height,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.alpha,
  });

  final int width;
  final int height;
  final double logicalWidth;
  final double logicalHeight;
  final Uint8List alpha;
}

/// THE bake of a word: [painter] (laid out) narrowed by [fit] at [dpr],
/// read back as coverage — what the timeline's tiles blit, and what a
/// screen draws a narrowed word from ([paintBakedWord]).
///
/// 🚨★★★TINY TEXT IS RASTERISED BIG AND SHRUNK, not rasterised tiny.
///
/// Names used to shrink to a 4px floor at deep zoom-out (R26 #38/#4) and
/// went anyway. 🧪Measured 2026-08-29: rasterising "12" at 4px leaves
/// mean alpha 136 over its box; rasterising at 12px and box-filtering to
/// the same box leaves 212. Both peak at 255, so the ink was never
/// missing — it was BLOTCHY, dark only where a stroke happened to land on
/// the grid, and a blotch tinted with cell ink reads as nothing. A word
/// keeps its type now (B, 2026-09-24) but NARROWS, and a narrow stroke
/// blotches the same way when the rasteriser is the one to draw it — so a
/// narrowed word is averaged down to its box too (below).
///
/// ⛔ABOVE THE FLOOR NOTHING CHANGES. [wordBakeScale] is 1 for any glyph
/// the rasteriser can already draw well, so zoom-in keeps the pixels it
/// has always had — 유저: 「줌인하면 텍스트는 선명하게 보고싶다」.
///
/// 🚨★★★THE RASTERISER IS NEVER ASKED FOR A NARROWED WORD (F-297, 유저
/// 2026-10-05): 「3a로 글자가 폭이 부족해서 가로 짧아진다거나 할때, 글자의
/// 세로길이나 세로 중앙정렬이 이상해짐. 3a만 이상하게 중앙에서
/// 위에존재하고. 게다가 약간 흐려지는? 이런 문제 원천적으로
/// 해결하고싶음」.
///
/// The word is rasterised exactly as the un-narrowed names beside it are —
/// ONE scale for both axes, its type's own whole number of times
/// ([wordBakeScale]) — and the narrowing is done here, by averaging that
/// raster into the narrowed box by area ([boxFilterA8]). A word narrowed
/// ALONG its line is then, down the line, the very raster its un-narrowed
/// bake is, taken by the same whole rows — it stands on that bake's rows
/// whatever draws the glyphs.
///
/// ↩️Until 2026-10-08 the rasteriser did the narrowing — each axis its own
/// scale, `scale(dpr·kx·fit.x, dpr·ky·fit.y)`, a whole number of times that
/// axis's own narrowing — on the reading that a word so drawn stands down
/// the line as it always did. 🧪It does only where whatever draws the
/// glyphs places one under a scale that differs by axis on the rows it
/// places it under a plain one. Skia on Windows did (every type 9–13px ×
/// ratio 1–2 × narrowing, to the thousandth of a pixel, 2026-10-07). The
/// Linux runner did not, the first time the pin ran there ("3" at 9px
/// narrowed to 0.85: ink on rows 0–9, the un-narrowed bake's on 1–9). And
/// IMPELLER — what the app ships on — did not either, the first time it
/// was asked (`flutter test --enable-impeller`, 2026-10-08): it draws such
/// a glyph at ONE scale and squeezes the quad, and 32 of the pin's 128
/// cases stood on other rows, by up to a whole pixel. In the app's face a
/// 12px name narrowed to 0.85 stood 0.62px low at ratio 1 and 0.76px high
/// at 1.5, up to 28% heavier — the 「3a만 … 위에」 again.
///
/// ⚠️WHAT THIS COSTS, measured the same day (the app's face at 12px, both
/// backends): along the line a mild narrowing — 0.7 to 0.95 — keeps a
/// tenth to a fifth less edge contrast at ratio 1 than that bake had (less
/// than that at 1.5), because the plain raster's soft edges are averaged
/// once more. At one over a whole number (0.5, 0.1) the two bakes measure
/// the same. Both earlier bakes had that contrast from rasterising the
/// word bigger than the names beside it, and both times its rows came
/// apart from theirs.
///
/// ↩️Before F-297 both axes took one scale as well, but the NARROWED
/// word's — the engine drew the word already narrowed, at the tighter
/// narrowing's exact ratio (12 / 8.4 = 1.43 …) — and three things followed.
/// The rows were averaged with the columns, which is the blur and the
/// 「세로길이」. The big raster was no whole multiple of the box, so the
/// average's windows did not tile it — 12 rows of ink came out over 14. And
/// the margin was one pixel of the BIG raster, 1/scale of a final one, so
/// the ink sat up and left of the box it is blitted by: a 12px name
/// narrowed to 0.7 stood 0.76px high and 0.42px left, beside neighbours
/// baked at 1 that stood where they should (the 「3a만 … 위에」).
///
/// The coverage is the painted ink's ALPHA, whatever colour [painter]
/// paints in: a caller that tints it draws the colour's own alpha twice
/// unless it keys the bake on that colour.
Future<BakedWordCoverage?> bakeWordCoverage(
  TextPainter painter, {
  required ({double x, double y}) fit,
  required double dpr,
  required double? fontSize,
}) async {
  if (painter.width <= 0 || painter.height <= 0) {
    return null;
  }
  // The raster is the word as it stands UN-narrowed with one final pixel of
  // margin round it, [times] times over — one final pixel of margin is that
  // many of its own.
  final times = wordBakeScale(fontSize ?? legibleBakeSize).toInt();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..translate(times.toDouble(), times.toDouble())
    ..scale(dpr * times);
  painter.paint(canvas, Offset.zero);
  final picture = recorder.endRecording();
  final bigWidth = ((painter.width * dpr).ceil() + 2) * times;
  final bigHeight = ((painter.height * dpr).ceil() + 2) * times;
  // ⚠️TWO holdings, two arms. `toImageSync` throws, so the picture used to
  // survive a failed bake; and `toByteData` is awaited, so the image used to
  // survive a failed read. Both are given back by structure now.
  final ui.Image image;
  try {
    image = picture.toImageSync(bigWidth, bigHeight);
  } finally {
    picture.dispose();
  }
  final ByteData? data;
  try {
    data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  } finally {
    image.dispose();
  }
  if (data == null) {
    return null;
  }
  final big = Uint8List(bigWidth * bigHeight);
  for (var i = 0; i < big.length; i += 1) {
    big[i] = data.getUint8(i * 4 + 3);
  }
  // The box the word is blitted by: its narrowed ink, and a pixel round it.
  final width = (painter.width * fit.x * dpr).ceil() + 2;
  final height = (painter.height * fit.y * dpr).ceil() + 2;
  return BakedWordCoverage(
    width: width,
    height: height,
    logicalWidth: painter.width * fit.x,
    logicalHeight: painter.height * fit.y,
    // ⛔No arm for the word that needs no average: the average of one pixel
    // IS that pixel ([boxFilterA8]), so the raster comes through it as it
    // is.
    alpha: boxFilterA8(
      big,
      bigWidth,
      bigHeight,
      width,
      height,
      along: _narrowedSpan(times, fit.x),
      down: _narrowedSpan(times, fit.y),
    ),
  );
}

/// What a pixel of the narrowed box covers of the raster, along one axis:
/// the box's pixel 1 — the first past its margin — begins where the
/// raster's own margin ends ([times] in), and a pixel takes [times] of the
/// raster's for every [fit] of itself.
BoxFilterSpan _narrowedSpan(int times, double fit) {
  final step = times / fit;
  return (origin: times - step, step: step);
}

/// Whether a word of type [fontSize] narrowed by [fit] is drawn from its
/// bake ([paintBakedWord]): a word some screen axis of which is smaller
/// than the rasteriser draws well — its type times that axis's narrowing,
/// under [legibleBakeSize]. A word it draws well both ways is painted as it
/// always was.
bool wordIsBaked(double? fontSize, ({double x, double y}) fit) {
  final type = fontSize ?? legibleBakeSize;
  return type * fit.x < legibleBakeSize || type * fit.y < legibleBakeSize;
}

/// How many times its final size to rasterise a glyph that ends up
/// [fontSize] tall.
///
/// ⛔1 for anything the rasteriser draws well already, which is what
/// keeps zoom-in byte-identical. Below that, enough to land the bake at
/// [legibleBakeSize] or past it — past which more oversampling buys
/// nothing, because the box it is being averaged into is the limit.
///
/// 🚨A WHOLE NUMBER, always (F-297): along an axis that is not narrowed the
/// average takes that many of the raster's pixels for each one it leaves,
/// whole — no row of the raster is shared between two of the box's — and
/// the margin is that many too. ↩️It was the exact ratio, which is one of
/// the three ways a narrowed word's ink went astray ([bakeWordCoverage]).
double wordBakeScale(double fontSize) {
  if (fontSize >= legibleBakeSize) {
    return 1;
  }
  return (legibleBakeSize / fontSize).ceilToDouble();
}

/// The size at which a digit's strokes land on enough pixels for the
/// average to carry its shape. Measured, not chosen: 12px was the probe's
/// comparison point and it recovers most of the ink (mean 136 → 212).
const double legibleBakeSize = 12;

/// Where the pixels of a filtered bitmap lie on its source, along one axis:
/// pixel `i` covers the source from `origin + i * step`, for `step`.
typedef BoxFilterSpan = ({double origin, double step});

/// Box-filters an A8 bitmap down to [tw]×[th]: each pixel the mean of the
/// source it covers, BY AREA — a source pixel it covers in part counts for
/// that part.
///
/// [along] and [down] say what the pixels cover; left out, the whole source
/// is laid over the whole target. What a pixel covers past the source's
/// edge is empty.
///
/// ⛔AVERAGE, not sample. Point-sampling a big raster back down would
/// reproduce the blotchiness this exists to remove — the whole gain is
/// that every source pixel under a destination pixel contributes.
///
/// ⛔IN WHOLE NUMBERS (a cover is counted in [_coverUnit]ths of a pixel):
/// a pixel that covers whole source pixels is their plain mean, a field of
/// one value stays that value at any ratio, and the average of ONE pixel is
/// that pixel — which is how a word that needs no average keeps the pixels
/// it has always had (유저 2026-08-28: 「줌인하면 텍스트는 선명하게
/// 보고싶다」).
///
/// ↩️At a ratio that was no whole number it took every source pixel a
/// window TOUCHED, whole, so neighbouring windows shared pixels — near
/// enough while only whole ratios were asked of it. A word narrowed to 0.85
/// asks for 1.18 pixels a pixel ([bakeWordCoverage]).
///
/// ⛔NOT THE APP'S ONE RESAMPLER (`services/resample` — `resampleCoverage`
/// is how a brush tip's coverage changes size), and not by oversight. Its
/// Blend weighs under a TENT as wide as the reduction — the pixel's own
/// box, and a reconstruction on top of it — where a baked word is the box
/// alone: how much of THIS pixel is ink. 🧪Measured 2026-10-08 (the app's
/// face on Impeller, one raster through each). Through Blend a 9px name,
/// which is rasterised twice over and shrunk whether it is narrowed or
/// not, spreads onto a row this leaves clear, peaks lower (「3a」 at ratio
/// 1: 149 for 200) and keeps 16–30% less edge contrast; a 12px name
/// narrowed to a half or under keeps 14–32% less along the line; and past
/// sixteen source pixels a pixel (`kResampleRadiusCeiling`) Blend stops
/// averaging, which a narrowing to a twentieth asks of a 9px name — its
/// ink came out from a fifth short to a third over.
Uint8List boxFilterA8(
  Uint8List src,
  int sw,
  int sh,
  int tw,
  int th, {
  BoxFilterSpan? along,
  BoxFilterSpan? down,
}) {
  final columns = _coversOf(along ?? (origin: 0, step: sw / tw), tw, sw);
  final rows = _coversOf(down ?? (origin: 0, step: sh / th), th, sh);
  final out = Uint8List(tw * th);
  for (var y = 0; y < th; y += 1) {
    final row = rows[y];
    for (var x = 0; x < tw; x += 1) {
      final column = columns[x];
      var acc = 0;
      for (var j = 0; j < row.weights.length; j += 1) {
        final line = (row.first + j) * sw + column.first;
        var inLine = 0;
        for (var i = 0; i < column.weights.length; i += 1) {
          inLine += src[line + i] * column.weights[i];
        }
        acc += inLine * row.weights[j];
      }
      out[y * tw + x] = acc ~/ (row.whole * column.whole);
    }
  }
  return out;
}

/// What one filtered pixel covers of its source along one axis: the source
/// pixels from [first] on, each by its covered part in [_coverUnit]ths, and
/// the [whole] of the cover — the part past the source's edges counted in.
typedef _Cover = ({int first, List<int> weights, int whole});

const int _coverUnit = 4096;

List<_Cover> _coversOf(BoxFilterSpan span, int count, int extent) => [
  for (var index = 0; index < count; index += 1)
    _coverOf(span.origin + index * span.step, span.step, extent),
];

_Cover _coverOf(double from, double length, int extent) {
  final to = from + length;
  final start = from.floor();
  final first = math.max(0, start);
  final weights = <int>[];
  var whole = 0;
  for (var pixel = start; pixel < to; pixel += 1) {
    final covered = math.min(to, pixel + 1.0) - math.max(from, pixel);
    final weight = (covered * _coverUnit).round();
    whole += weight;
    if (pixel >= first && pixel < extent) {
      weights.add(weight);
    }
  }
  return (first: first, weights: weights, whole: whole);
}

/// Paints [painter] narrowed by [fit] with its top-left at [origin] from
/// its BAKE ([bakeWordCoverage]) — true when it did, false when the caller
/// is to paint the word itself (it asked for the bake, which lands later).
///
/// 🗣️F-224 (유저 2026-10-01): 「8%정도에서 대사 텍스트가 많으면 안보이는데,
/// 약간 2치화된 폰트느낌? 그래서 좀 부드러운 필터 건다거나 아무튼 더 잘
/// 보이게」. 🔬Captured on this machine's engine (Impeller, an integration
/// run, 2026-10-01): a glyph drawn through `canvas.scale(0.1, 1)` comes out
/// as black and white specks — the engine samples the narrowed glyph
/// without averaging it. A glyph IMAGE drawn smaller by the GPU specked the
/// same way, from a picture or from decoded pixels alike (no mips for
/// either); only a raster averaged on the CPU — the tiles' bake — came out
/// smooth. So a narrowed word on a screen is drawn from that bake, as a
/// tile word is.
///
/// Only where the bake would differ: a word whose narrowed type is under
/// [legibleBakeSize] ([wordIsBaked]). Anything the rasteriser draws well is
/// painted as it always was.
///
/// The bake is drawn in the word's own ink, its style's colour — the one
/// solid every fitted word is set in.
///
/// While the exact bake is in flight the word is drawn from the last bake
/// of it at another narrowing, if there is one; only a word never baked is
/// handed back to be painted plainly. [BakedWords.landed] says when to
/// paint again.
bool paintBakedWord(
  Canvas canvas,
  TextPainter painter,
  Offset origin,
  ({double x, double y}) fit,
) {
  final span = painter.text;
  final fontSize = span?.style?.fontSize;
  // The ROOT TRANSFORM's pixels are what a bake is cut for — with no view on
  // screen (a painter called by itself) there are none, and the word is
  // painted as it always was.
  final views = RendererBinding.instance.renderViews;
  if (span == null ||
      views.isEmpty ||
      !wordIsBaked(fontSize, fit)) {
    return false;
  }
  // The root transform's ratio carries the app's UI scale — the view's own
  // ratio does not, and a bake cut for it would be shrunk by the GPU again
  // (`EffectiveDevicePixelRatio` is this number where there is a context; a
  // painter has none).
  final dpr = views.first.configuration.devicePixelRatio;
  final baked = BakedWords.instance._bakeFor(
    (
      span: span,
      scaler: painter.textScaler,
      dpr: dpr,
      width: painter.width,
      height: painter.height,
    ),
    fit,
    () => bakeWordCoverage(painter, fit: fit, dpr: dpr, fontSize: fontSize),
  );
  if (baked == null) {
    return false;
  }
  final color = span.style?.color ?? const Color(0xFF000000);
  canvas.drawImageRect(
    baked,
    Rect.fromLTWH(0, 0, baked.width.toDouble(), baked.height.toDouble()),
    // The bake's one-pixel margin, back in logical pixels.
    Rect.fromLTWH(
      origin.dx - 1 / dpr,
      origin.dy - 1 / dpr,
      painter.width * fit.x + 2 / dpr,
      painter.height * fit.y + 2 / dpr,
    ),
    Paint()
      ..filterQuality = FilterQuality.low
      ..colorFilter = ColorFilter.mode(
        color.withValues(alpha: 1),
        BlendMode.srcIn,
      ),
  );
  return true;
}

/// A painter that may set a narrowed word ([paintBakedWord]) — it paints
/// again when a bake lands ([BakedWords.landed]), on top of whatever else
/// it repaints on.
///
/// ⚠️EVERY such painter, not the one whose word landed: a bake lands once
/// a word and narrowing — a burst while a zoom settles or a scroll brings
/// new words in, when these painters are painting anyway — where a tile
/// lands once a span and row on every scroll (I-22 ③ keeps those to their
/// own row).
mixin RepaintOnWordBakes on CustomPainter {
  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    BakedWords.instance.landed.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    BakedWords.instance.landed.removeListener(listener);
  }
}

/// A word apart from its narrowing: the spans it is set in — text, style
/// and ink, the letter gaps it gave included — the painter's scaling, the
/// pixel grid, and the box it was laid in (a word laid short, ellipsis and
/// all, is not the word laid whole).
typedef _Word = ({
  InlineSpan span,
  TextScaler scaler,
  double dpr,
  double width,
  double height,
});

/// A word at one narrowing — what one bake is of.
typedef _Bake = ({_Word word, double x, double y});

/// The words a screen has baked ([paintBakedWord]) — the app's one cache
/// of them, as images, and when one lands.
final class BakedWords {
  BakedWords._();

  static final BakedWords instance = BakedWords._();

  /// How many baked words are kept; a narrowed dialogue is one per glyph
  /// and narrowing, a block word one per word.
  static const int _capacity = 512;

  final BakeOnceLru<_Bake, ui.Image?> _images = BakeOnceLru(
    capacity: _capacity,
    retire: (image) => image?.dispose(),
  );

  /// Each word's latest bake, whatever its narrowing — what the word is
  /// drawn from while the bake for a new narrowing is in flight.
  final Map<_Word, _Bake> _latestOf = {};

  final ValueNotifier<int> _landed = ValueNotifier(0);
  bool _landingScheduled = false;

  /// Bumps once in a frame in which bakes landed: a painter that drew a
  /// word before its bake listens to this to draw it again.
  ValueListenable<int> get landed => _landed;

  /// [word]'s bake at [fit] once it landed, else its latest at another
  /// narrowing (null: none yet) — asking [bake] for the exact one.
  ui.Image? _bakeFor(
    _Word word,
    ({double x, double y}) fit,
    Future<BakedWordCoverage?> Function() bake,
  ) {
    final key = (word: word, x: fit.x, y: fit.y);
    final exact = _images.peek(key);
    if (exact != null) {
      return exact;
    }
    if (!_baking.contains(word)) {
      unawaited(_images.ensure(key, () => _land(key, bake)));
    }
    final latest = _latestOf[word];
    return latest == null ? null : _images.peek(latest);
  }

  /// The words with a bake in flight. One narrowing at a time a word: a
  /// zoom moves its narrowing every frame, and the narrowings it passes
  /// through are drawn from the bake it has instead of each baked in turn.
  final Set<_Word> _baking = {};

  Future<ui.Image?> _land(
    _Bake key,
    Future<BakedWordCoverage?> Function() bake,
  ) async {
    _baking.add(key.word);
    try {
      final coverage = await bake();
      if (coverage == null) {
        return null;
      }
      final image = await _imageOf(coverage);
      // Bounded with the images it points into: past four words an image,
      // the stale ones only point at retired bakes.
      if (_latestOf.length > 4 * _capacity) {
        _latestOf.clear();
      }
      _latestOf[key.word] = key;
      _announceLanding();
      return image;
    } on Object {
      // A bake the engine refused leaves the word painted as it always was.
      return null;
    } finally {
      _baking.remove(key.word);
    }
  }

  void _announceLanding() {
    if (_landingScheduled) {
      return;
    }
    _landingScheduled = true;
    SchedulerBinding.instance
      ..scheduleFrameCallback((_) {
        _landingScheduled = false;
        _landed.value += 1;
      })
      ..scheduleFrame();
  }

  /// [coverage] as white ink on clear, premultiplied — tinted where it is
  /// drawn.
  static Future<ui.Image> _imageOf(BakedWordCoverage coverage) {
    final rgba = Uint8List(coverage.width * coverage.height * 4);
    for (var i = 0; i < coverage.alpha.length; i += 1) {
      final a = coverage.alpha[i];
      rgba[i * 4] = a;
      rgba[i * 4 + 1] = a;
      rgba[i * 4 + 2] = a;
      rgba[i * 4 + 3] = a;
    }
    return uploadRawRgba(rgba, width: coverage.width, height: coverage.height);
  }
}
