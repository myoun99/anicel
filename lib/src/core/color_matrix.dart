/// 4×5 COLOR MATRICES — the math core of the color effects (R6).
///
/// The shape is exactly `ui.ColorFilter.matrix`'s: row-major, four rows of
/// five, the fifth column a translation in **0…255** space while the
/// multipliers are unit-scale (Skia's `MakeMatrixFilterRowMajor255`). Skia
/// UNPREMULTIPLIES before applying and re-premultiplies after, so a
/// brightness offset never lights up transparent pixels — the alpha row
/// decides visibility on its own.
///
/// Every builder here is a pure function of the effect's parameters, which
/// is the whole point: the composite routes only ever ask for a matrix, and
/// the matrices are unit-testable without a canvas.
library;

import 'dart:math' as math;

/// The 4×5 identity — "this effect changes nothing".
const List<double> identityColorMatrix = <double>[
  // dart format off
  1, 0, 0, 0, 0,
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, 1, 0,
  // dart format on
];

/// Rec. 709 luminance weights — the same ones `ui.ColorFilter.saturation`
/// uses, so our saturation and Flutter's agree to the bit.
const double luminanceR = 0.2126;
const double luminanceG = 0.7152;
const double luminanceB = 0.0722;

/// `outer ∘ inner`: the matrix that applies [inner] first and then
/// [outer]. Folding a multi-part effect (hue + saturation + lightness) into
/// ONE matrix keeps it to a single Skia filter — and, unlike chaining, it
/// skips the intermediate clamp, so a hue rotation cannot lose a channel
/// that saturation was about to bring back.
///
/// Composition treats each matrix as the affine map
/// `c' = M·c + t` with `t` in 0…255: the product's translation is
/// `outer.M · inner.t + outer.t`.
List<double> composeColorMatrices(List<double> outer, List<double> inner) {
  assert(outer.length == 20 && inner.length == 20);
  final result = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row += 1) {
    for (var column = 0; column < 4; column += 1) {
      var sum = 0.0;
      for (var k = 0; k < 4; k += 1) {
        sum += outer[row * 5 + k] * inner[k * 5 + column];
      }
      result[row * 5 + column] = sum;
    }
    var translation = outer[row * 5 + 4];
    for (var k = 0; k < 4; k += 1) {
      translation += outer[row * 5 + k] * inner[k * 5 + 4];
    }
    result[row * 5 + 4] = translation;
  }
  return result;
}

/// [matrix] applied at STRENGTH [amount] (0 = identity, 1 = the matrix
/// itself): the elementwise blend with the identity.
///
/// This is exact, not an approximation — the map is affine, so
/// `((1−a)·I + a·M)·c` IS `(1−a)·c + a·(M·c)`. That is what lets an
/// adjustment layer's MIX fold into its own matrix and composite in ONE
/// pass: a crossfade drawn as two src-over passes would compound alpha and
/// make a translucent picture more opaque.
List<double> lerpColorMatrixFromIdentity(List<double> matrix, double amount) {
  final strength = amount.clamp(0.0, 1.0);
  return <double>[
    for (var index = 0; index < 20; index += 1)
      identityColorMatrix[index] +
          (matrix[index] - identityColorMatrix[index]) * strength,
  ];
}

/// Whether [matrix] is the identity (within [epsilon]) — the composite
/// routes drop such an effect instead of paying for a filter that does
/// nothing.
bool colorMatrixIsIdentity(List<double> matrix, {double epsilon = 1e-6}) {
  for (var index = 0; index < 20; index += 1) {
    if ((matrix[index] - identityColorMatrix[index]).abs() > epsilon) {
      return false;
    }
  }
  return true;
}

/// BRIGHTNESS then CONTRAST, folded into one matrix.
///
/// [brightness] and [contrast] are the UI's −100…100 (AE's Brightness &
/// Contrast range):
/// - brightness adds `b/100` of full scale to each channel, and
/// - contrast scales each channel around mid grey by
///   `f = (100 + contrast) / 100` — 0 at −100 (flat grey), 2 at +100.
///
/// Folded: `out = f·(in + b) + 127.5·(1 − f)`.
List<double> brightnessContrastMatrix({
  required double brightness,
  required double contrast,
}) {
  final factor = (100 + contrast) / 100;
  final offset = factor * (brightness / 100 * 255) + 127.5 * (1 - factor);
  return <double>[
    // dart format off
    factor, 0,      0,      0, offset,
    0,      factor, 0,      0, offset,
    0,      0,      factor, 0, offset,
    0,      0,      0,      1, 0,
    // dart format on
  ];
}

/// HUE ROTATION by [degrees] — the standard SVG `feColorMatrix
/// type="hueRotate"` construction (a rotation in the luma-preserving
/// chroma plane).
List<double> hueRotationMatrix(double degrees) {
  final radians = degrees * math.pi / 180;
  final cosine = math.cos(radians);
  final sine = math.sin(radians);
  double term(double weight, double cosineWeight, double sineWeight) =>
      weight + cosine * cosineWeight + sine * sineWeight;
  return <double>[
    // dart format off
    term(luminanceR,  1 - luminanceR, -luminanceR),
    term(luminanceG,     -luminanceG, -luminanceG),
    term(luminanceB,     -luminanceB, 1 - luminanceB),
    0, 0,

    term(luminanceR,     -luminanceR, 0.143),
    term(luminanceG, 1 - luminanceG, 0.140),
    term(luminanceB,     -luminanceB, -0.283),
    0, 0,

    term(luminanceR,     -luminanceR, -(1 - luminanceR)),
    term(luminanceG,     -luminanceG, luminanceG),
    term(luminanceB, 1 - luminanceB, luminanceB),
    0, 0,

    0, 0, 0, 1, 0,
    // dart format on
  ];
}

/// SATURATION, [saturation] in −100…100: −100 is fully desaturated
/// (luminance only), 0 leaves the picture alone, +100 doubles the distance
/// from grey. Identical construction to `ui.ColorFilter.saturation` with
/// `1 + saturation/100`.
List<double> saturationMatrix(double saturation) {
  final scale = 1 + saturation / 100;
  final inverse = 1 - scale;
  return <double>[
    // dart format off
    inverse * luminanceR + scale, inverse * luminanceG,         inverse * luminanceB,         0, 0,
    inverse * luminanceR,         inverse * luminanceG + scale, inverse * luminanceB,         0, 0,
    inverse * luminanceR,         inverse * luminanceG,         inverse * luminanceB + scale, 0, 0,
    0,                            0,                            0,                            1, 0,
    // dart format on
  ];
}

/// LIGHTNESS, [lightness] in −100…100: positive lerps the picture toward
/// white, negative toward black (Photoshop's 명도 slider behaviour), so
/// ±100 is a flat white/black wash and 0 is a no-op.
List<double> lightnessMatrix(double lightness) {
  final amount = (lightness / 100).clamp(-1.0, 1.0);
  final scale = 1 - amount.abs();
  final offset = amount > 0 ? 255 * amount : 0.0;
  return <double>[
    // dart format off
    scale, 0,     0,     0, offset,
    0,     scale, 0,     0, offset,
    0,     0,     scale, 0, offset,
    0,     0,     0,     1, 0,
    // dart format on
  ];
}

/// HUE / SATURATION / LIGHTNESS as ONE matrix, applied in that order — the
/// single effect the UI shows as three lanes.
List<double> hueSaturationMatrix({
  required double hueDegrees,
  required double saturation,
  required double lightness,
}) {
  var matrix = hueRotationMatrix(hueDegrees);
  matrix = composeColorMatrices(saturationMatrix(saturation), matrix);
  return composeColorMatrices(lightnessMatrix(lightness), matrix);
}
