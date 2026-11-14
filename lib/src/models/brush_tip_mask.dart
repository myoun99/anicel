import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../core/bounded_memo.dart';

/// Longest mask side kept when an imported image becomes a mask; larger
/// sources are downscaled so the tip library stays a reasonable size on
/// disk. It lives with the mask rather than with any one decoder, so the
/// pure-Dart importers can honour it without dragging in `dart:ui`.
const int maxBrushTipMaskSide = 256;

/// Applies a paper texture's invert, brightness and contrast to [mask].
///
/// A mask holds COVERAGE — "how much paint" — which is the texture image
/// inverted, so the three controls do not translate one for one. Contrast
/// pivots on mid-grey and survives the inversion unchanged. Brightness does
/// not: lightening the paper means less paint.
///
/// Brightness is a lerp toward white (or black, going negative) rather than
/// an offset, which is what keeps it bounded — an offset of the size real
/// files carry (ウェット水彩 asks for 75) subtracts more than any texture
/// has, flattening the grain to nothing. Scaling cannot do that.
///
/// Baking these in keeps the samplers untouched: the tiled ones run off a
/// separable per-axis lattice, so anything that changed what a texel means
/// at sample time would cost every textured brush its fast path.
BrushTipMask brushTipMaskWithLevels(
  BrushTipMask mask, {
  bool invert = false,
  double brightness = 0.0,
  double contrast = 0.0,
}) {
  if (!invert && brightness == 0.0 && contrast == 0.0) {
    return mask;
  }
  final scale = 1.0 + contrast.clamp(-1.0, 1.0);
  final shift = brightness.clamp(-1.0, 1.0);
  final adjusted = Uint8List(mask.alpha.length);
  for (var index = 0; index < mask.alpha.length; index += 1) {
    var coverage = mask.alpha[index] / 255.0;
    if (invert) {
      coverage = 1.0 - coverage;
    }
    coverage = (coverage - 0.5) * scale + 0.5;
    coverage = shift >= 0.0
        ? coverage * (1.0 - shift)
        : 1.0 - (1.0 - coverage) * (1.0 + shift);
    adjusted[index] = (coverage * 255.0).round().clamp(0, 255);
  }
  return BrushTipMask(id: mask.id, size: mask.size, alpha: adjusted);
}

/// [brushTipMaskWithLevels], baked at most once per (mask, levels).
///
/// 🚨THE LEVELS ARE A BRUSH SETTING NOW, so the bake moved out of the
/// importers and onto the path a dab is built on — and that path runs
/// thousands of times a stroke while a 256×256 texture is 65k pixels. This
/// is what keeps it at one bake.
///
/// The three cache questions, answered before it was written:
/// ① The key is the WHOLE identity — the mask instance plus all three
///    levels — so nothing can change without changing the key.
/// ② A miss costs exactly one bake, which is what the uncached call always
///    paid. No amplification.
/// ③ It hangs off the mask itself, so an entry dies when its mask does and
///    there is no global table to grow or to sweep.
///
/// ⛔The mask is the key by IDENTITY, which is why this is an [Expando] and
/// not a map keyed by the mask. `BrushTipMask ==` walks the whole alpha
/// array, and the entries most likely to collide in a hash bucket are the
/// SAME texture at other levels — so a value-keyed map would compare 65k
/// bytes on the lookup this exists to make cheap.
///
/// ⚠️Neutral levels return the mask ITSELF and never touch the cache — the
/// overwhelmingly common brush has no levels at all.
BrushTipMask brushTipMaskWithCachedLevels(
  BrushTipMask mask, {
  bool invert = false,
  double brightness = 0.0,
  double contrast = 0.0,
}) {
  if (!invert && brightness == 0.0 && contrast == 0.0) {
    return mask;
  }
  // A slider DRAG is a fresh value every frame and every one of them is a
  // real bake, so the only thing to bound here is what the drag leaves
  // behind afterwards.
  return (_levelCache[mask] ??= BoundedMemo(_levelsPerMaskLimit)).resolve(
    (invert: invert, brightness: brightness, contrast: contrast),
    () => brushTipMaskWithLevels(
      mask,
      invert: invert,
      brightness: brightness,
      contrast: contrast,
    ),
  );
}

const int _levelsPerMaskLimit = 4;

typedef _MaskLevels = ({bool invert, double brightness, double contrast});

final Expando<BoundedMemo<_MaskLevels, BrushTipMask>> _levelCache = Expando(
  'brushTipMaskLevels',
);

/// [mask] smoothed by a box [across] texels wide along its rows and [down]
/// texels down its columns, centred on each texel, over the picture as the
/// samplers read it — linear between texels, nothing past its square
/// (`sampleBrushTipMaskCoverage`): what an anti-alias step lays a picture
/// tip as (`brushTipGeometry`). Widths of 0 give the picture back as it is.
///
/// 🚨★★★H60 (유저 I-86 2026-11-15 「팁이 소재면 aa off하면 소재 팁
/// 그대로인거고 거기서 aa추가하면 추가로 aa 적용되는거고」 · H60-Q2 (a)
/// 「연산은 하나, 자리는 클튜대로」): the box sits about the picture's own
/// contour, as in the user's Clip Studio samples of a picture tip
/// (`参考/CSP_decode/1115_tipAA`) — its area holds, it spreads out as far
/// as in, and the grain within is smoothed too. A round tip's ramp of the
/// same width ends at its rim instead (I-50, `RoundTipProfile`).
/// ⚠️What would spread past the square is cut there: the samplers read
/// nothing past it, and a dab reaches its square (`dirtyRegionForBrushDab`)
/// — a tip drawn to its square's edge keeps half its smoothing there.
BrushTipMask brushTipMaskSmoothed(
  BrushTipMask mask, {
  required double across,
  required double down,
}) {
  if (across == 0.0 && down == 0.0) {
    return mask;
  }
  final size = mask.size;
  final line = Float64List(size);
  final smoothed = Float64List(size);
  final rising = Float64List(size + 2);
  final rows = Float64List(size * size);
  final source = mask.alphaNormalized;
  for (var row = 0; row < size; row += 1) {
    line.setRange(0, size, source, row * size);
    _smoothedLine(line, across, smoothed, rising);
    rows.setRange(row * size, row * size + size, smoothed);
  }
  final alpha = Uint8List(size * size);
  for (var column = 0; column < size; column += 1) {
    for (var row = 0; row < size; row += 1) {
      line[row] = rows[row * size + column];
    }
    _smoothedLine(line, down, smoothed, rising);
    for (var row = 0; row < size; row += 1) {
      alpha[row * size + column] = (smoothed[row] * 255.0).round().clamp(
        0,
        255,
      );
    }
  }
  return BrushTipMask(id: '${mask.id}~smoothed', size: size, alpha: alpha);
}

/// [line] — texels, linear between them and to nothing past either end —
/// under a box [width] texels wide centred on each, into [into]: the area
/// under it across the box, over the box's width. [rising] holds the area
/// up to each texel's centre, the one before the first's first.
void _smoothedLine(
  Float64List line,
  double width,
  Float64List into,
  Float64List rising,
) {
  final count = line.length;
  if (width == 0.0) {
    into.setRange(0, count, line);
    return;
  }
  double texel(int at) => at < 0 || at >= count ? 0.0 : line[at];
  rising[0] = 0.0;
  for (var at = 0; at <= count; at += 1) {
    rising[at + 1] = rising[at] + (texel(at - 1) + texel(at)) * 0.5;
  }
  double upTo(double x) {
    if (x <= -1.0) {
      return 0.0;
    }
    if (x >= count) {
      return rising[count + 1];
    }
    final before = x.floor();
    final past = x - before;
    final from = texel(before);
    return rising[before + 1] +
        from * past +
        (texel(before + 1) - from) * past * past * 0.5;
  }

  final half = width * 0.5;
  for (var at = 0; at < count; at += 1) {
    into[at] = (upTo(at + half) - upTo(at - half)) / width;
  }
}

/// [brushTipMaskSmoothed] at the widths a dab asks, each rounded to an
/// eighth of an octave, baked at most once per (mask, widths) — [mask]
/// itself at widths of 0.
///
/// The three cache questions:
/// ① The key is the mask by identity and both rounded widths — nothing
///    else goes into the bake.
/// ② A miss costs one bake, what the uncached call always paid.
/// ③ It hangs off the mask, so its entries go with it.
/// 📏An eighth of an octave lays a width at most 4.4% off the one asked
/// (H60-Q3 「클튜랑 픽셀단위로 맞출필요는없음」): a pressure stroke whose size
/// moves over two octaves meets about [_smoothingsPerMaskLimit] of them.
BrushTipMask brushTipMaskSmoothedCached(
  BrushTipMask mask, {
  required double across,
  required double down,
}) {
  if (across == 0.0 && down == 0.0) {
    return mask;
  }
  int eighths(double width) =>
      width == 0.0 ? _noWidth : (math.log(width) / math.ln2 * 8).round();
  double widthOf(int eighths) =>
      eighths == _noWidth ? 0.0 : math.pow(2.0, eighths / 8).toDouble();
  final key = (eighths(across), eighths(down));
  return (_smoothedCache[mask] ??= BoundedMemo(_smoothingsPerMaskLimit))
      .resolve(
        key,
        () => brushTipMaskSmoothed(
          mask,
          across: widthOf(key.$1),
          down: widthOf(key.$2),
        ),
      );
}

const int _smoothingsPerMaskLimit = 16;

/// An eighth-octave count no width rounds to: a width of 0.
const int _noWidth = -1 << 30;

final Expando<BoundedMemo<(int, int), BrushTipMask>> _smoothedCache =
    Expando('brushTipMaskSmoothed');


/// A sampled (bitmap) brush tip: a square grayscale alpha mask.
///
/// This is the engine primitive Photoshop ABR "sampled brush" tips map onto:
/// coverage comes from bilinear-sampling the mask in tip space instead of
/// the parametric circle/square tests. Masks are square by design — ABR
/// import pads arbitrary tip bitmaps to square with transparent border.
///
/// Immutable; committed dabs reference the mask object directly, so a
/// stroke keeps rendering identically even if the tip is later removed from
/// the library.
class BrushTipMask {
  BrushTipMask({
    required this.id,
    required this.size,
    required Uint8List alpha,
  }) : alpha = Uint8List.fromList(alpha) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'BrushTipMask.id must not be empty.');
    }
    if (size <= 0) {
      throw ArgumentError.value(
        size,
        'size',
        'BrushTipMask.size must be greater than 0.',
      );
    }
    if (this.alpha.length != size * size) {
      throw ArgumentError.value(
        alpha.length,
        'alpha',
        'BrushTipMask.alpha must hold size * size bytes.',
      );
    }
  }

  /// Stable identifier (e.g. `builtin-chalk`, an ABR sampled-tip UUID).
  final String id;

  /// Edge length of the square mask in mask pixels.
  final int size;

  /// Row-major alpha bytes (0 = transparent, 255 = full coverage).
  final Uint8List alpha;

  /// [alpha] pre-divided by 255.0 — exactly the `alpha[i] / 255.0` every
  /// sampler computes per texel read, cached once so the rasterizer hot
  /// loops skip the per-pixel conversion. Derived render data only.
  late final Float64List alphaNormalized = _normalizeAlpha();

  Float64List _normalizeAlpha() {
    final normalized = Float64List(alpha.length);
    for (var index = 0; index < alpha.length; index += 1) {
      normalized[index] = alpha[index] / 255.0;
    }
    return normalized;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'size': size,
    'alpha': base64Encode(alpha),
  };

  /// A mask of [width] × [height] coverage bytes padded to the centred
  /// square the engine's samplers require.
  ///
  /// 🚨ONE padding for the image decoder, the cut-piece tip and the ABR
  /// sampled tip (the audit's clone scan, 2026-09-03).
  factory BrushTipMask.square({
    required String id,
    required Uint8List pixels,
    required int width,
    required int height,
  }) {
    final side = math.max(width, height);
    final alpha = Uint8List(side * side);
    final offsetX = (side - width) ~/ 2;
    final offsetY = (side - height) ~/ 2;
    for (var y = 0; y < height; y += 1) {
      alpha.setRange(
        (offsetY + y) * side + offsetX,
        (offsetY + y) * side + offsetX + width,
        pixels,
        y * width,
      );
    }
    return BrushTipMask(id: id, size: side, alpha: alpha);
  }

  factory BrushTipMask.fromJson(Map<String, dynamic> json) {
    return BrushTipMask(
      id: json['id'] as String,
      size: json['size'] as int,
      alpha: base64Decode(json['alpha'] as String),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! BrushTipMask || other.id != id || other.size != size) {
      return false;
    }
    for (var index = 0; index < alpha.length; index += 1) {
      if (other.alpha[index] != alpha[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(id, size, alpha.length);

  @override
  String toString() => 'BrushTipMask(id: $id, size: $size)';
}
