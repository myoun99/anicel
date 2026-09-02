import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Longest mask side kept when an imported image becomes a mask; larger
/// sources are downscaled so the tip library stays a reasonable size on
/// disk. It lives with the mask rather than with any one decoder, so the
/// pure-Dart importers can honour it without dragging in `dart:ui`.
const int maxBrushTipMaskSide = 256;

/// [width] × [height] shrunk to fit [maxBrushTipMaskSide] on the long side,
/// aspect kept, never below 1; unchanged when it already fits.
///
/// 🚨ONE fit for the image decoder and the cut-piece tip (the audit's clone
/// scan, 2026-09-03); the resizers stay each source's own.
({int width, int height}) brushTipMaskFitted(int width, int height) {
  final longSide = math.max(width, height);
  if (longSide <= maxBrushTipMaskSide) {
    return (width: width, height: height);
  }
  final scale = maxBrushTipMaskSide / longSide;
  return (
    width: math.max(1, (width * scale).round()),
    height: math.max(1, (height * scale).round()),
  );
}

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
  BrushTipMask({required this.id, required this.size, required Uint8List alpha})
    : alpha = Uint8List.fromList(alpha) {
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
