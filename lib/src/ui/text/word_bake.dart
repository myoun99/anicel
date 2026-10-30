import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart' show CustomPainter, RendererBinding;
import 'package:flutter/scheduler.dart';

import '../../core/bake_once_lru.dart';
import '../../core/hashed_once.dart';
import '../../core/lru.dart';
import '../../models/rgba_image_bytes.dart';
import '../../services/straight_rgba_image.dart' show uploadRawRgba;
import '../look_only_frames.dart';
import '../quiet_turns.dart';

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
  final word = recordWord(painter, fit: fit, dpr: dpr, fontSize: fontSize);
  return word == null ? null : bakeRecordedWord(word);
}

/// [painter] as [bakeWordCoverage] rasters it — recorded, not yet
/// rastered: what a paint that asks for a bake keeps of the word, the
/// painter being that paint's ([BakedWords]). Null for a word of no size.
RecordedWord? recordWord(
  TextPainter painter, {
  required ({double x, double y}) fit,
  required double dpr,
  required double? fontSize,
}) {
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
  return RecordedWord._(
    picture: recorder.endRecording(),
    times: times,
    width: painter.width,
    height: painter.height,
    fit: fit,
    dpr: dpr,
  );
}

/// A word recorded for its bake ([recordWord]): its picture, until
/// [bakeRecordedWord] gives it back, and what reading its raster takes.
final class RecordedWord {
  RecordedWord._({
    required this.picture,
    required this.times,
    required this.width,
    required this.height,
    required this.fit,
    required this.dpr,
  });

  final ui.Picture picture;
  final int times;
  final double width;
  final double height;
  final ({double x, double y}) fit;
  final double dpr;
}

/// [word]'s raster read back as its coverage ([bakeWordCoverage]); its
/// picture is given back whatever comes of it.
Future<BakedWordCoverage?> bakeRecordedWord(RecordedWord word) async {
  final RecordedWord(:picture, :times, :fit, :dpr) = word;
  final bigWidth = ((word.width * dpr).ceil() + 2) * times;
  final bigHeight = ((word.height * dpr).ceil() + 2) * times;
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
  final width = (word.width * fit.x * dpr).ceil() + 2;
  final height = (word.height * fit.y * dpr).ceil() + 2;
  return BakedWordCoverage(
    width: width,
    height: height,
    logicalWidth: word.width * fit.x,
    logicalHeight: word.height * fit.y,
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
///
/// ⛔NOT A PICTURE'S OWN MIP CHAIN EITHER (`display_resample.dart`), which
/// would spare a paint the wait for its bake. A chain halves both axes at
/// once, and a word narrows along its line alone: 🧪measured 2026-10-30
/// (the app's face on Impeller, 52 words × types × narrowings, one raster
/// through each, `medium`), 34 came out on more rows than this leaves — a
/// 12px 「12」 narrowed to a quarter inks all 14 rows of its box for 9, peak
/// 76 for 214, the blur of F-297 back. Even narrowed by a half both ways its
/// levels stand half a texel off these windows, the margin being one pixel.
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

/// The pixels a bake is cut for: the ROOT TRANSFORM's ratio — null with no
/// view on screen (a painter called by itself), where no word is baked and
/// each is painted as it always was.
///
/// The root transform's ratio carries the app's UI scale — the view's own
/// ratio does not, and a bake cut for it would be shrunk by the GPU again
/// (`EffectiveDevicePixelRatio` is this number where there is a context; a
/// painter has none).
double? wordBakePixelRatio() {
  final views = RendererBinding.instance.renderViews;
  return views.isEmpty ? null : views.first.configuration.devicePixelRatio;
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
/// same way, from a picture or from decoded pixels alike, at `low`; only a
/// raster averaged on the CPU — the tiles' bake — came out smooth. So a
/// narrowed word on a screen is drawn from that bake, as a tile word is.
/// (`medium` does not speck, and is no answer either: [boxFilterA8].)
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
/// handed back to be painted plainly. Whoever is painting
/// ([BakedWords.paintAs]) is woken when the exact one lands.
bool paintBakedWord(
  Canvas canvas,
  TextPainter painter,
  Offset origin,
  ({double x, double y}) fit,
) {
  final span = painter.text;
  final fontSize = span?.style?.fontSize;
  final dpr = wordBakePixelRatio();
  if (span == null || dpr == null || !wordIsBaked(fontSize, fit)) {
    return false;
  }
  final baked = BakedWords.instance._bakeFor(
    _Word((
      span: span,
      scaler: painter.textScaler,
      dpr: dpr,
      width: painter.width,
      height: painter.height,
    )),
    fit,
    () => recordWord(painter, fit: fit, dpr: dpr, fontSize: fontSize),
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

/// What draws a narrowed word from a stand-in — another narrowing's bake,
/// or the word as the rasteriser sets it — and is to be painted again when
/// THAT word's bake lands ([BakedWords.paintAs]).
abstract interface class WordBakeWaiter {
  void wordBakeLanded();
}

/// A painter that may set a narrowed word ([paintBakedWord]) — painted
/// again when a word it drew from a stand-in has its bake land, on top of
/// whatever else it repaints on. What it paints is [paintWords].
///
/// 🚨★★★ONLY THE PAINTER THAT WAITS FOR THE WORD
/// (playback-making-pictures-shakes-the-frames, 10-11). ↩️Every such painter
/// was painted again on every landing, on the reading that bakes land in a
/// burst while a zoom settles or a scroll brings new words in, when these
/// painters are painting anyway. One painter bringing new words alone
/// breaks that reading, and the playhead's number does on every frame of a
/// first pass through a cut: 🔬each landing painted nine rail rows, the
/// frame viewport and the rulers again — about 1,300 render objects. A word
/// answers 「어디가 바뀌었나」 itself.
///
/// ⛔A painter mixing this in overrides [paintWords], never [paint]: [paint]
/// is what makes it the one waiting
/// (`test/architecture/a_word_painter_paints_its_words_test.dart`).
mixin RepaintOnWordBakes on CustomPainter implements WordBakeWaiter {
  /// Who listens to each painter — the render objects it is painted for.
  static final Expando<List<VoidCallback>> _listeners = Expando();

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    (_listeners[this] ??= []).add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _listeners[this]?.remove(listener);
  }

  /// Everything this painter's picture is drawn from, as one value — or
  /// null for a painter whose picture is not kept, which paints its words
  /// at every paint.
  ///
  /// A painter that answers draws the picture kept for an equal answer, by
  /// any painter of its kind before it: a row built again — a tab opened
  /// again, a panel unfolded — draws what the row it replaces set. The same
  /// picture draws the same pixels, so the answer must hold every input the
  /// words are drawn from; [paint] adds the size and the pixels a bake is
  /// cut for.
  Object? get pictureKey => null;

  /// ⛔A paint that drew a word from a stand-in is NOT kept
  /// ([BakedWords.paintAs]): the bake on its way wakes this painter to paint
  /// again, and a kept stand-in would answer it.
  @override
  void paint(Canvas canvas, Size size) {
    final drawnFrom = pictureKey;
    if (drawnFrom == null) {
      BakedWords.instance.paintAs(this, () => paintWords(canvas, size));
      return;
    }
    final key = (runtimeType, drawnFrom, size, wordBakePixelRatio());
    if (_pictures.use(key) case final kept?) {
      canvas.drawPicture(kept);
      return;
    }
    final recorder = ui.PictureRecorder();
    final settled = BakedWords.instance.paintAs(
      this,
      () => paintWords(Canvas(recorder), size),
    );
    final picture = recorder.endRecording();
    canvas.drawPicture(picture);
    if (settled) {
      _pictures.keep(key, picture);
    } else {
      picture.dispose();
    }
  }

  /// The pictures kept lately ([pictureKey]), by what each is drawn from.
  ///
  /// Thirty-two: the rows of both rails a screen shows, kept over a
  /// reopening of either. A row scrolled across a span is a new window at
  /// each paint, and letting an old one go costs its painter one paint of
  /// its words — what every paint paid before.
  static final Lru<Object, ui.Picture> _pictures = Lru(
    entryCap: () => 32,
    letGo: (_, picture) => picture.dispose(),
  );

  /// Lets go of every kept picture — a project closing: what a picture is
  /// drawn from ([pictureKey]) holds its rows' cel answers, and through them
  /// that project's whole session (F-505, measured: the holder of a closed
  /// tab once its timeline tiles let go). The project on screen sets its
  /// rows again.
  static void clearKeptPictures() {
    for (final picture in _pictures.values) {
      picture.dispose();
    }
    _pictures.clear();
  }

  /// What [paint] is to any other painter.
  void paintWords(Canvas canvas, Size size);

  @override
  void wordBakeLanded() {
    for (final listener in [...?_listeners[this]]) {
      listener();
    }
  }
}

/// A word apart from its narrowing: the spans it is set in — text, style
/// and ink, the letter gaps it gave included — the painter's scaling, the
/// pixel grid, and the box it was laid in (a word laid short, ellipsis and
/// all, is not the word laid whole).
///
/// Hashed once ([HashedOnce]): a paint looks its word up several times —
/// its bake taken out and put back, the word's latest bake, its waiters —
/// and a span's hash walks its style and every child's.
typedef _Word =
    HashedOnce<
      ({
        InlineSpan span,
        TextScaler scaler,
        double dpr,
        double width,
        double height,
      })
    >;

/// A word at one narrowing — what one bake is of — hashed once, as its word
/// is.
typedef _Bake = HashedOnce<({_Word word, double x, double y})>;

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
    costOf: (image) =>
        image == null ? 0 : estimatedImageBytes(image.width, image.height),
    retire: (image) => image?.dispose(),
  );

  /// What the baked words' pictures weigh resident, for the memory census.
  int get imageBytes => _images.held;

  /// Each word's latest bake, whatever its narrowing — what the word is
  /// drawn from while the bake for a new narrowing is in flight.
  final Map<_Word, _Bake> _latestOf = {};

  /// Who is painting now ([paintAs]) — the one a stand-in drawn now waits
  /// for.
  WordBakeWaiter? _painting;

  /// Who drew each word from a stand-in, waiting for its bake.
  final Map<_Word, Set<WordBakeWaiter>> _waiting = {};

  /// How many words someone waits for.
  @visibleForTesting
  int get debugWaitingWords => _waiting.length;

  /// The waiters the next frame wakes: those whose word's bake finished.
  final Set<WordBakeWaiter> _toWake = {};
  bool _wakeScheduled = false;

  /// How many frames have woken waiters or followed a landing — what a test
  /// waits on.
  @visibleForTesting
  int get debugLandingFrames => _landingFrames;
  int _landingFrames = 0;

  /// How many words the paint running now ([paintAs]) drew from a stand-in
  /// while their own bake is on its way.
  int _standIns = 0;

  /// Runs [paint] as [waiter]: a word it draws from a stand-in wakes it —
  /// and only it — when that word's bake lands.
  ///
  /// True when it drew none so — every narrowed word from its own bake, or
  /// from all it will ever have: what a painter that KEEPS its picture asks
  /// before it keeps it. A kept stand-in is never woken, and would stand in
  /// for the bake for as long as the picture is kept.
  bool paintAs(WordBakeWaiter waiter, VoidCallback paint) {
    final outerWaiter = _painting;
    final outerStandIns = _standIns;
    _painting = waiter;
    _standIns = 0;
    try {
      paint();
      return _standIns == 0;
    } finally {
      _painting = outerWaiter;
      // A painter painted inside another drew into it: its stand-ins are
      // the outer paint's too.
      _standIns += outerStandIns;
    }
  }

  /// [word]'s bake at [fit] once it landed, else its latest at another
  /// narrowing (null: none yet) — asking [record] for the exact one, and
  /// putting whoever paints down as waiting for it. ⛔Not for a bake that
  /// is done and came to nothing: nothing will land.
  ui.Image? _bakeFor(
    _Word word,
    ({double x, double y}) fit,
    RecordedWord? Function() record,
  ) {
    final key = _Bake((word: word, x: fit.x, y: fit.y));
    final exact = _images.peek(key);
    if (exact != null) {
      return exact;
    }
    if (!_images.isDone(key)) {
      _standIns += 1;
      final waiter = _painting;
      if (waiter != null) {
        (_waiting[word] ??= {}).add(waiter);
      }
      if (!_baking.contains(word)) {
        unawaited(_images.ensure(key, () => _land(key, record)));
      }
    }
    final latest = _latestOf[word];
    return latest == null ? null : _images.peek(latest);
  }

  /// The words with a bake in flight. One narrowing at a time a word: a
  /// zoom moves its narrowing every frame, and the narrowings it passes
  /// through are drawn from the bake it has instead of each baked in turn.
  final Set<_Word> _baking = {};

  /// Where a bake takes its turn to put the word on the GPU ([_land]).
  @visibleForTesting
  QuietTurns quietTurns = QuietTurns.instance;

  /// How long a bake has taken from its turn to its landing, at the most of
  /// late.
  final QuietSpan _bakeSpan = QuietSpan();

  /// A bake asked for is waited for: a word shown from a stand-in is shown
  /// from its bake once it lands.
  static bool _neverGone() => false;

  /// The bake of [key], and its waiters woken once it is done — landed, or
  /// come to nothing: a waiter for another narrowing of the word asks for
  /// its own when it paints again.
  ///
  /// 🚨THE WORD IS RECORDED IN THE PAINT THAT ASKED, AND RASTERED, READ BACK
  /// AND UPLOADED IN ITS TURN in the quiet between a run's held frames
  /// ([QuietTurns]) — 🔬6–18 of them queued the first pass's page turns
  /// 12–19 ms (release, 2026-10-15). Recorded then because the painter is
  /// that paint's: laid out again, or gone, by the time the turn comes.
  /// The stand-in the word is drawn from meanwhile is what it always was.
  Future<ui.Image?> _land(
    _Bake key,
    RecordedWord? Function() record,
  ) async {
    _baking.add(key.value.word);
    final recorded = record();
    QuietTurn? turn;
    var landed = false;
    try {
      if (recorded == null) {
        return null;
      }
      turn = await quietTurns.inAQuiet(_bakeSpan, gone: _neverGone);
      final coverage = await bakeRecordedWord(recorded);
      if (coverage == null) {
        return null;
      }
      final image = await _imageOf(coverage);
      // Bounded with the images it points into: past four words an image,
      // the stale ones only point at retired bakes.
      if (_latestOf.length > 4 * _capacity) {
        _latestOf.clear();
      }
      _latestOf[key.value.word] = key;
      landed = true;
      return image;
    } on Object {
      // A bake the engine refused leaves the word painted as it always was.
      return null;
    } finally {
      // The word is shown as soon as it is baked: the turn given back waits
      // for the GPU on its own ([QuietTurn.landed]).
      unawaited(landed ? turn?.landed() : turn?.gaveUp());
      _baking.remove(key.value.word);
      final waiters = _waiting.remove(key.value.word);
      if (waiters != null) {
        _toWake.addAll(waiters);
      }
      if (landed || waiters != null) {
        _wakeNextFrame();
      }
    }
  }

  /// Wakes [_toWake] in one frame — as many bakes as finish before it.
  ///
  /// 🚨THE FRAME IS ASKED FOR ONLY TO LOOK ([askOnlyToLook]): what it draws
  /// is what the waiters it wakes paint again, and a bake nobody waited for
  /// paints nothing. Asked for to draw, every landing drew a frame, and a
  /// playing cut drew them between its film frames (card
  /// playback-draws-frames-the-film-did-not-change-in, 10-24).
  void _wakeNextFrame() {
    if (_wakeScheduled) {
      return;
    }
    _wakeScheduled = true;
    askOnlyToLook(() {
      SchedulerBinding.instance
        ..scheduleFrameCallback((_) {
          _wakeScheduled = false;
          _landingFrames += 1;
          final woken = List.of(_toWake);
          _toWake.clear();
          for (final waiter in woken) {
            waiter.wordBakeLanded();
          }
        })
        ..scheduleFrame();
    });
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
