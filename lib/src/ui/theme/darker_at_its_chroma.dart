import 'dart:math' as math;
import 'dart:ui' show Color;

/// [colour] darkened until it stands [contrast]:1 against [ground]: its
/// CIELAB lightness lowered, its hue and chroma kept — the same colour,
/// darker. A colour that already stands there is handed back as it is.
///
/// ⛔Not HSL's lightness: that keeps HSL's SATURATION, which a pale colour
/// has at full — the paper's #FFFDF7 came out amber and a pastel label a
/// vivid one. Measured against the light panel (I-143-Q7): the paper goes
/// to a warm grey (#85837E), a pastel green to a muted one (#539153), and
/// the accents stay as vivid as they were picked.
Color darkenedToStandOn(Color colour, Color ground, {double contrast = 3}) {
  final key = (colour.toARGB32(), ground.toARGB32(), contrast);
  return _darkened[key] ??= _darken(colour, ground, contrast);
}

/// Pure in its three inputs, and the inputs are few — the label palette and
/// the accents against a panel or two — so every answer is kept.
final _darkened = <(int, int, double), Color>{};

Color _darken(Color colour, Color ground, double contrast) {
  final groundLuminance = ground.computeLuminance();
  final (l, a, b) = _labOf(colour);
  var lightness = l;
  var shown = colour;
  while (lightness > 0 &&
      (groundLuminance + 0.05) / (shown.computeLuminance() + 0.05) <
          contrast) {
    lightness = math.max(0, lightness - 0.5);
    shown = _colourOf(lightness, a, b, alpha: colour.a);
  }
  return shown;
}

double _linear(double channel) => channel <= 0.04045
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

double _gamma(double channel) => channel <= 0.0031308
    ? 12.92 * channel
    : 1.055 * math.pow(channel, 1 / 2.4) - 0.055;

// D65 white.
const _xn = 0.95047;
const _zn = 1.08883;

double _f(double t) =>
    t > 216 / 24389 ? math.pow(t, 1 / 3).toDouble() : t * 841 / 108 + 4 / 29;

double _fInverse(double t) =>
    t > 6 / 29 ? t * t * t : (t - 4 / 29) * 108 / 841;

(double, double, double) _labOf(Color colour) {
  final r = _linear(colour.r);
  final g = _linear(colour.g);
  final b = _linear(colour.b);
  final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / _xn;
  final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / _zn;
  return (116 * _f(y) - 16, 500 * (_f(x) - _f(y)), 200 * (_f(y) - _f(z)));
}

Color _colourOf(double l, double a, double b, {required double alpha}) {
  final fy = (l + 16) / 116;
  final x = _fInverse(fy + a / 500) * _xn;
  final y = _fInverse(fy);
  final z = _fInverse(fy - b / 200) * _zn;
  double channel(double linear) => _gamma(linear.clamp(0, 1)).clamp(0, 1);
  return Color.from(
    alpha: alpha,
    red: channel(3.2406 * x - 1.5372 * y - 0.4986 * z),
    green: channel(-0.9689 * x + 1.8758 * y + 0.0415 * z),
    blue: channel(0.0557 * x - 0.2040 * y + 1.0570 * z),
  );
}
