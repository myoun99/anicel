import 'dart:convert';
import 'dart:typed_data';

/// Longest mask side kept when an imported image becomes a mask; larger
/// sources are downscaled so the tip library stays a reasonable size on
/// disk. It lives with the mask rather than with any one decoder, so the
/// pure-Dart importers can honour it without dragging in `dart:ui`.
const int maxBrushTipMaskSide = 256;

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
