/// A picture file's colours turned to sRGB's, as the engine's decoder turns
/// them: what its file says of them — an ICC profile of a matrix and
/// curves, or a PNG's gamma and chromaticities — read to linear light,
/// carried to sRGB's primaries and written by sRGB's curve ([ToSrgb]).
///
/// 🗣️유저 2026-11-14 (a-raster-import-goes-gpu-cpu-gpu-cpu-Q1): 「프로파일
/// 대로 바꿔 읽는다(크기 상관없이)」. 🔬The device's engine (Impeller) turns
/// a file's ICC profile and a PNG's gamma to sRGB's as it decodes, while
/// the app's own reader read the values as stored — so a picture past the
/// engine's side came out apart from the same picture within it.
///
/// Every step is +, −, ×, ÷ and comparisons, the same on every device
/// (🗣️gpu-same-formula-Q2 「기기가 달라도 같아야 한다」, [srgbByteOf]): a
/// power is this file's own ([_pow]), never `math.pow`.
///
/// ⏳A profile made of tables (`A2B0` and no matrix) is not turned yet —
/// its picture reads as stored, as every picture did before.
library;

import 'dart:typed_data';

import '../../core/srgb_byte.dart';
import 'png_reading.dart';

/// How a file's colours become sRGB's: each channel's byte to linear light
/// by the file's own curve, then its primaries to sRGB's ([row]).
final class ToSrgb {
  ToSrgb._(this._curves, this._matrix);

  /// Each channel's byte → linear light: red's, green's, blue's.
  final List<Float64List> _curves;

  /// The file's linear RGB → sRGB's linear RGB, row after row.
  final Float64List _matrix;

  /// [rgba] — straight RGBA8, a row or more — turned to sRGB's colours where
  /// it lies. A clear pixel is left as it is, all zero as the readers hand
  /// one ([readPngRows]).
  void row(Uint8List rgba) {
    final [red, green, blue] = _curves;
    final m = _matrix;
    for (var i = 0; i < rgba.length; i += 4) {
      if (rgba[i + 3] == 0) {
        continue;
      }
      final r = red[rgba[i]];
      final g = green[rgba[i + 1]];
      final b = blue[rgba[i + 2]];
      rgba[i] = _byteOf(m[0] * r + m[1] * g + m[2] * b);
      rgba[i + 1] = _byteOf(m[3] * r + m[4] * g + m[5] * b);
      rgba[i + 2] = _byteOf(m[6] * r + m[7] * g + m[8] * b);
    }
  }
}

/// What turns the picture file [bytes]' colours to sRGB's — null where they
/// are sRGB's already, or where its file says nothing this turns.
ToSrgb? toSrgbOf(Uint8List bytes) {
  if (readPngColour(bytes) case final png?) {
    return _ofPng(png);
  }
  if (_jpegProfile(bytes) case final profile?) {
    return _ofProfile(profile);
  }
  return null;
}

/// Whether the picture file [bytes] is one whose colours this reads as the
/// engine's decoder does: a PNG or a JPEG that carries no profile, or one
/// of a matrix and curves or of a grey ([_turnOf]) — so the app's reader
/// may read it at any size and lay it as the engine would have.
///
/// ⏳A file whose profile this does not read (one of tables, a CMYK
/// JPEG's) is not one: the engine turns its colours, and within the
/// engine's side its picture stays the engine's to decode.
bool readsTheColoursOf(Uint8List bytes) {
  final Uint8List? profile;
  if (readPngColour(bytes) case final png?) {
    profile = png.profile;
  } else if (startsLikeJpeg(bytes)) {
    profile = _jpegProfile(bytes);
  } else {
    return false;
  }
  return profile == null || _turnOf(profile) != null;
}

/// A PNG's colours as its decoder reads them, in its order: a profile
/// (`iCCP`) that reads first, then sRGB's own word (`sRGB`), then the
/// primaries (`cHRM`) on the gamma (`gAMA`) or sRGB's curve, then the gamma
/// alone on sRGB's primaries.
ToSrgb? _ofPng(PngColour png) {
  if (png.profile case final profile?) {
    if (_turnOf(profile) case final turn?) {
      return _built(turn);
    }
  }
  if (png.srgb) {
    return null;
  }
  final gamma = png.gamma;
  final curve = gamma == null || gamma == 0
      ? _srgbCurve
      : _Curve.parametric([100000 / gamma, 1, 0, 0, 0, 0, 0]);
  if (png.chromaticities case final c?) {
    final [wx, wy, rx, ry, gx, gy, bx, by] = [for (final v in c) v / 100000];
    final primaries = _primariesToXyzD50(
      (x: rx, y: ry),
      (x: gx, y: gy),
      (x: bx, y: by),
      (x: wx, y: wy),
    );
    if (primaries != null) {
      return _built((curves: [curve, curve, curve], toXyzD50: primaries));
    }
  }
  if (gamma == null || gamma == 0) {
    return null;
  }
  return _built((curves: [curve, curve, curve], toXyzD50: _srgbToXyzD50));
}

/// [profile] — an ICC profile's bytes — as what turns its colours, or null
/// where it is sRGB's or not one this turns.
ToSrgb? _ofProfile(Uint8List profile) {
  final turn = _turnOf(profile);
  return turn == null ? null : _built(turn);
}

/// What a file's colours are: each channel's curve to linear light, and
/// its linear RGB → XYZ under D50, as an ICC profile's connection space
/// has them.
typedef _Turn = ({List<_Curve> curves, Float64List toXyzD50});

/// [turn] as a [ToSrgb] — null where it turns no byte more than one from
/// where it was, as sRGB's own profile does (its curves written as a table,
/// its primaries rounded): such a file is sRGB's, and its bytes are kept.
ToSrgb? _built(_Turn turn) {
  final turned = ToSrgb._(
    [
      for (final curve in turn.curves)
        Float64List.fromList([
          for (var v = 0; v < 256; v += 1) curve.at(v / 255),
        ]),
    ],
    _multiplied(_xyzD50ToSrgb, turn.toXyzD50),
  );
  return _movesABytePastOne(turned) ? turned : null;
}

/// Whether [turned] moves some byte of a grey, or of a ramp of a primary
/// or of two, more than one from where it was.
bool _movesABytePastOne(ToSrgb turned) {
  final samples = BytesBuilder(copy: false);
  for (var v = 0; v < 256; v += 1) {
    for (final (r, g, b) in [
      (v, v, v),
      (v, 0, 0),
      (0, v, 0),
      (0, 0, v),
      (v, v, 0),
      (0, v, v),
      (v, 0, v),
    ]) {
      samples.add([r, g, b, 255]);
    }
  }
  final before = samples.toBytes();
  final after = Uint8List.fromList(before);
  turned.row(after);
  for (var i = 0; i < before.length; i += 1) {
    if ((after[i] - before[i]).abs() > 1) {
      return true;
    }
  }
  return false;
}

// ICC ----------------------------------------------------------------------

/// [icc] read as a profile of a matrix and curves — RGB on XYZ — or of a
/// grey curve: null where it is neither, or does not read.
_Turn? _turnOf(Uint8List icc) {
  if (icc.length < 132) {
    return null;
  }
  final data = ByteData.sublistView(icc);
  final space = _signature(data, 16);
  if (_signature(data, 36) != 'acsp' || _signature(data, 20) != 'XYZ ') {
    return null;
  }
  final tags = _tagsOf(data);
  if (tags == null) {
    return null;
  }
  _Curve? curve(String name) => _curveOf(data, tags[name]);
  if (space == 'GRAY') {
    final grey = curve('kTRC');
    // A grey is laid on every channel, sRGB's white its white.
    return grey == null
        ? null
        : (curves: [grey, grey, grey], toXyzD50: _srgbToXyzD50);
  }
  if (space != 'RGB ') {
    return null;
  }
  final red = curve('rTRC');
  final green = curve('gTRC');
  final blue = curve('bTRC');
  final r = _xyzOf(data, tags['rXYZ']);
  final g = _xyzOf(data, tags['gXYZ']);
  final b = _xyzOf(data, tags['bXYZ']);
  if (red == null ||
      green == null ||
      blue == null ||
      r == null ||
      g == null ||
      b == null) {
    return null;
  }
  return (
    curves: [red, green, blue],
    toXyzD50: Float64List.fromList([
      r[0], g[0], b[0], //
      r[1], g[1], b[1], //
      r[2], g[2], b[2],
    ]),
  );
}

/// Where each tag of a profile lies: its offset and size, by name — null
/// where the table runs past the profile.
Map<String, ({int offset, int size})>? _tagsOf(ByteData data) {
  final count = data.getUint32(128);
  if (132 + count * 12 > data.lengthInBytes) {
    return null;
  }
  return {
    for (var at = 132; at < 132 + count * 12; at += 12)
      _signature(data, at): (
        offset: data.getUint32(at + 4),
        size: data.getUint32(at + 8),
      ),
  };
}

String _signature(ByteData data, int at) => String.fromCharCodes([
  for (var i = 0; i < 4; i += 1) data.getUint8(at + i),
]);

double _s15Fixed16(ByteData data, int at) => data.getInt32(at) / 65536;

/// An `XYZ ` tag's one value — null where [tag] is not one.
List<double>? _xyzOf(ByteData data, ({int offset, int size})? tag) {
  if (tag == null ||
      tag.size < 20 ||
      tag.offset + 20 > data.lengthInBytes ||
      _signature(data, tag.offset) != 'XYZ ') {
    return null;
  }
  return [
    for (var i = 0; i < 3; i += 1) _s15Fixed16(data, tag.offset + 8 + i * 4),
  ];
}

/// A `curv` or `para` tag as a curve — null where [tag] is neither.
_Curve? _curveOf(ByteData data, ({int offset, int size})? tag) {
  if (tag == null || tag.offset + 12 > data.lengthInBytes) {
    return null;
  }
  final at = tag.offset;
  switch (_signature(data, at)) {
    case 'curv':
      final count = data.getUint32(at + 8);
      if (at + 12 + count * 2 > data.lengthInBytes) {
        return null;
      }
      if (count == 0) {
        return _Curve.parametric(const [1, 1, 0, 0, 0, 0, 0]);
      }
      if (count == 1) {
        final gamma = data.getUint16(at + 12) / 256;
        return _Curve.parametric([gamma, 1, 0, 0, 0, 0, 0]);
      }
      return _Curve.table([
        for (var i = 0; i < count; i += 1) data.getUint16(at + 12 + i * 2),
      ]);
    case 'para':
      final type = data.getUint16(at + 8);
      const counts = [1, 3, 4, 5, 7];
      if (type >= counts.length ||
          at + 12 + counts[type] * 4 > data.lengthInBytes) {
        return null;
      }
      final p = [
        for (var i = 0; i < counts[type]; i += 1)
          _s15Fixed16(data, at + 12 + i * 4),
      ];
      return _Curve.parametric(_parametricOf(type, p));
  }
  return null;
}

/// An ICC parametric curve of [type] and its [p]arameters as the one form
/// [_Curve.parametric] reads — g, a, b, c, d, e, f: (a·x + b)^g + e from d
/// on, c·x + f below it.
List<double> _parametricOf(int type, List<double> p) => switch (type) {
  0 => [p[0], 1, 0, 0, 0, 0, 0],
  1 => [p[0], p[1], p[2], 0, -p[2] / p[1], 0, 0],
  2 => [p[0], p[1], p[2], 0, -p[2] / p[1], p[3], p[3]],
  3 => [p[0], p[1], p[2], p[3], p[4], 0, 0],
  _ => [p[0], p[1], p[2], p[3], p[4], p[5], p[6]],
};

// JPEG ---------------------------------------------------------------------

/// The ICC profile a JPEG carries — its `APP2` pieces, put together in the
/// order they are numbered — or null where it carries none, or [bytes] are
/// no JPEG.
Uint8List? _jpegProfile(Uint8List bytes) {
  if (!startsLikeJpeg(bytes)) {
    return null;
  }
  final pieces = <int, Uint8List>{};
  var at = 2;
  while (at + 4 <= bytes.length && bytes[at] == 0xff) {
    final marker = bytes[at + 1];
    if (marker == 0xff) {
      at += 1;
      continue;
    }
    if (marker == 0xd9 || marker == 0xda) {
      break;
    }
    if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      at += 2;
      continue;
    }
    final end = at + 2 + (bytes[at + 2] << 8 | bytes[at + 3]);
    final start = at + 4;
    if (end > bytes.length) {
      break;
    }
    if (marker == 0xe2 && end - start > 14 && _saysIccProfile(bytes, start)) {
      pieces[bytes[start + 12]] = Uint8List.sublistView(
        bytes,
        start + 14,
        end,
      );
    }
    at = end;
  }
  if (pieces.isEmpty) {
    return null;
  }
  final profile = BytesBuilder(copy: false);
  for (final number in pieces.keys.toList()..sort()) {
    profile.add(pieces[number]!);
  }
  return profile.toBytes();
}

/// Whether [bytes] begin as a JPEG does: its start of image — what picks
/// the JPEG road both here and where the file is read (`readFileRows`).
bool startsLikeJpeg(Uint8List bytes) =>
    bytes.length >= 4 && bytes[0] == 0xff && bytes[1] == 0xd8;

/// Whether the `APP2` payload at [start] begins `ICC_PROFILE\0`.
bool _saysIccProfile(Uint8List bytes, int start) {
  const said = 'ICC_PROFILE';
  for (var i = 0; i < said.length; i += 1) {
    if (bytes[start + i] != said.codeUnitAt(i)) {
      return false;
    }
  }
  return bytes[start + said.length] == 0;
}

// Curves -------------------------------------------------------------------

/// A curve from a channel's value, 0 to 1, to linear light.
final class _Curve {
  _Curve.parametric(List<double> gabcdef) : _p = gabcdef, _table = null;

  _Curve.table(List<int> entries) : _p = null, _table = entries;

  final List<double>? _p;
  final List<int>? _table;

  double at(double x) {
    final p = _p;
    if (p != null) {
      final [g, a, b, c, d, e, f] = p;
      return x >= d ? _pow(a * x + b, g) + e : c * x + f;
    }
    final table = _table!;
    final last = table.length - 1;
    final place = x <= 0 ? 0.0 : (x >= 1 ? last.toDouble() : x * last);
    final low = place.floor();
    final high = low < last ? low + 1 : low;
    final between = place - low;
    return (table[low] + (table[high] - table[low]) * between) / 65535;
  }
}

/// sRGB's own curve, as a PNG with primaries and no gamma reads by.
final _srgbCurve = _Curve.parametric(const [
  2.4,
  1 / 1.055,
  0.055 / 1.055,
  1 / 12.92,
  0.04045,
  0,
  0,
]);

/// [x] to the power [y]: zero where [x] is none — exp(y · ln x), each this
/// file's own series, so the same on every device.
double _pow(double x, double y) {
  if (x <= 0) {
    return 0;
  }
  if (x == 1) {
    return 1;
  }
  return _exp(y * _ln(x));
}

const double _ln2 = 0.6931471805599453;
const double _sqrt2 = 1.4142135623730951;

/// The natural log of [x] > 0: x as m · 2^e, m within √½ and √2, and
/// ln m = 2 · artanh((m − 1) / (m + 1)) by its series.
double _ln(double x) {
  var m = x;
  var e = 0;
  while (m >= _sqrt2) {
    m /= 2;
    e += 1;
  }
  while (m < _sqrt2 / 2) {
    m *= 2;
    e -= 1;
  }
  final s = (m - 1) / (m + 1);
  final s2 = s * s;
  var term = s;
  var sum = 0.0;
  for (var k = 1; k < 44; k += 2) {
    sum += term / k;
    term *= s2;
  }
  return 2 * sum + e * _ln2;
}

/// e to the [y]: y as k · ln 2 + r, r within ±½ ln 2, and e^r by its series.
double _exp(double y) {
  if (y < -745) {
    return 0;
  }
  final k = (y / _ln2).round();
  final r = y - k * _ln2;
  var term = 1.0;
  var sum = 1.0;
  for (var n = 1; n < 26; n += 1) {
    term *= r / n;
    sum += term;
  }
  for (var i = 0; i < k; i += 1) {
    sum *= 2;
  }
  for (var i = 0; i > k; i -= 1) {
    sum /= 2;
  }
  return sum;
}

// Matrices -----------------------------------------------------------------

/// sRGB's linear RGB → XYZ under D50, as its ICC profile writes it.
final _srgbToXyzD50 = Float64List.fromList([
  0.436065674, 0.385147095, 0.143066406, //
  0.222488403, 0.716873169, 0.060607910, //
  0.013916016, 0.097076416, 0.714096069,
]);

final _xyzD50ToSrgb = _inverse(_srgbToXyzD50)!;

/// The white an ICC profile's connection space is under: D50, as the
/// profile's header writes it.
final _d50 = Float64List.fromList([
  0.964202880859375,
  1.0,
  0.8249053955078125,
]);

/// Bradford's cone response, what a white is carried to another by.
final _bradford = Float64List.fromList([
  0.8951, 0.2664, -0.1614, //
  -0.7502, 1.7135, 0.0367, //
  0.0389, -0.0685, 1.0296,
]);

/// A colour's place in CIE xy.
typedef _Xy = ({double x, double y});

/// Linear RGB of the primaries [red], [green] and [blue] under [white] to
/// XYZ under D50, the white carried there by Bradford's cones: null where
/// the primaries make no space.
Float64List? _primariesToXyzD50(_Xy red, _Xy green, _Xy blue, _Xy white) {
  if (red.y == 0 || green.y == 0 || blue.y == 0 || white.y == 0) {
    return null;
  }
  // Each at a luminance of one.
  List<double> xyzOf(_Xy p) => [p.x / p.y, 1, (1 - p.x - p.y) / p.y];
  final [r, g, b] = [xyzOf(red), xyzOf(green), xyzOf(blue)];
  final primaries = Float64List.fromList([
    r[0], g[0], b[0], //
    r[1], g[1], b[1], //
    r[2], g[2], b[2],
  ]);
  final whiteXyz = Float64List.fromList(xyzOf(white));
  final inverse = _inverse(primaries);
  if (inverse == null) {
    return null;
  }
  final toXyz = _multiplied(primaries, _diagonal(_applied(inverse, whiteXyz)));
  final cones = _applied(_bradford, whiteXyz);
  final toCones = _applied(_bradford, _d50);
  final adapt = _multiplied(
    _inverse(_bradford)!,
    _multiplied(
      _diagonal([for (var i = 0; i < 3; i += 1) toCones[i] / cones[i]]),
      _bradford,
    ),
  );
  return _multiplied(adapt, toXyz);
}

/// The matrix that scales each channel by its own of [d].
Float64List _diagonal(List<double> d) => Float64List.fromList([
  d[0], 0, 0, //
  0, d[1], 0, //
  0, 0, d[2],
]);

Float64List _multiplied(Float64List a, Float64List b) => Float64List.fromList([
  for (var row = 0; row < 3; row += 1)
    for (var column = 0; column < 3; column += 1)
      a[row * 3] * b[column] +
          a[row * 3 + 1] * b[3 + column] +
          a[row * 3 + 2] * b[6 + column],
]);

Float64List _applied(Float64List m, Float64List v) => Float64List.fromList([
  for (var row = 0; row < 3; row += 1)
    m[row * 3] * v[0] + m[row * 3 + 1] * v[1] + m[row * 3 + 2] * v[2],
]);

/// [m]'s inverse — null where it has none.
Float64List? _inverse(Float64List m) {
  final [a, b, c, d, e, f, g, h, i] = m;
  final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
  if (det == 0) {
    return null;
  }
  return Float64List.fromList([
    (e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det, //
    (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det, //
    (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det,
  ]);
}

// Writing ------------------------------------------------------------------

/// How finely [_bytes] reads linear light.
const int _steps = 1 << 16;

/// The sRGB byte of each [_steps]th of linear light ([srgbByteOf]).
final _bytes = Uint8List.fromList([
  for (var i = 0; i <= _steps; i += 1) srgbByteOf(i / _steps),
]);

/// The sRGB byte of linear [c], held to [0, 1]: read off [_bytes] where the
/// steps either side give one byte, else worked out ([srgbByteOf]) — the
/// byte [srgbByteOf] gives, at a table's cost.
int _byteOf(double c) {
  if (c <= 0) {
    return 0;
  }
  if (c >= 1) {
    return 255;
  }
  final low = (c * _steps).floor();
  final byte = _bytes[low];
  return byte == _bytes[low + 1] ? byte : srgbByteOf(c);
}
