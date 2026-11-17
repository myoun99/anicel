import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/alike_maths.dart';

import '../helpers/pinned_fingerprints.dart';

/// The sine, cosine and exponential the app hands the engine are msun's,
/// the same to the last bit on every device (board
/// `linux-libm-hands-the-engine-other-last-bits`): within an ulp of the
/// device's own here, and pinned bit for bit in the one ledger, so a device
/// that rounded them otherwise fails by name.
void main() {
  test('a sine and a cosine lie within an ulp of the device\'s own', () {
    for (final x in _angles()) {
      expect(_ulpsApart(alikeSin(x), math.sin(x)), lessThanOrEqualTo(1),
          reason: 'sin($x)');
      expect(_ulpsApart(alikeCos(x), math.cos(x)), lessThanOrEqualTo(1),
          reason: 'cos($x)');
    }
  });

  test('an exponential lies within an ulp of the device\'s own', () {
    for (final x in _powers()) {
      expect(_ulpsApart(alikeExp(x), math.exp(x)), lessThanOrEqualTo(1),
          reason: 'exp($x)');
    }
  });

  test('the bits the libm crate\'s own test pins near pi', () {
    // libm 0.2.16's sin.rs `test_near_pi`.
    expect(
      _bitsOf(alikeSin(_ofBits(0x400921fb000FD5DD))),
      0x3ea50d15ced1a4a2,
    );
  });

  test('the edges are IEEE\'s', () {
    expect(_bitsOf(alikeSin(-0.0)), _bitsOf(-0.0));
    expect(alikeCos(0), 1);
    expect(alikeExp(0), 1);
    for (final edge in [double.infinity, double.negativeInfinity]) {
      expect(alikeSin(edge), isNaN);
      expect(alikeCos(edge), isNaN);
    }
    expect(alikeSin(double.nan), isNaN);
    expect(alikeExp(double.nan), isNaN);
    expect(alikeExp(double.infinity), double.infinity);
    expect(alikeExp(1000), double.infinity);
    expect(alikeExp(double.negativeInfinity), 0);
    expect(alikeExp(-1000), 0);
  });

  test('they are the pinned bits', () {
    final values = <double>[
      for (final x in _angles()) ...[alikeSin(x), alikeCos(x)],
      for (final x in _powers()) alikeExp(x),
    ];
    final bytes = ByteData(values.length * 8);
    for (final (index, value) in values.indexed) {
      bytes.setFloat64(index * 8, value, Endian.little);
    }
    expect(
      fingerprintHex(bytes.buffer.asUint8List()),
      pinnedFingerprint('values/alike-maths'),
    );
  });
}

/// Radians every way the app turns: -100 to 100 by a 64th, -720° to 720° by
/// an eighth of a degree, the doubles nearest whole quarter turns, and far
/// turns, out to where the medium reduction stops.
Iterable<double> _angles() sync* {
  for (var i = -6400; i <= 6400; i += 1) {
    yield i / 64;
  }
  for (var eighth = -5760; eighth <= 5760; eighth += 1) {
    yield eighth / 8 * math.pi / 180;
  }
  // The doubles nearest a quarter turn and its multiples: x less a whole
  // number of them cancels down to the reduction's third round.
  for (var quarters = 1; quarters <= 1 << 20; quarters *= 3) {
    yield quarters * (math.pi / 2);
    yield -quarters * (math.pi / 2);
  }
  for (final far in [1e3, 12345.678, 1e5, 1e6, 1.5e6]) {
    yield far;
    yield -far;
  }
}

/// Exponents from where e^x is all but nought to where it all but
/// overflows, by a tenth, and near nought.
Iterable<double> _powers() sync* {
  for (var tenth = -7450; tenth <= 7090; tenth += 1) {
    yield tenth / 10;
  }
  for (final small in [1e-12, 1e-9, 2e-7, 0.3, 0.35, 0.5, 1.03]) {
    yield small;
    yield -small;
  }
}

int _bitsOf(double x) => (ByteData(8)..setFloat64(0, x)).getInt64(0);

double _ofBits(int bits) => (ByteData(8)..setInt64(0, bits)).getFloat64(0);

/// How many doubles lie between [a] and [b], ordered by value.
int _ulpsApart(double a, double b) {
  int ordered(double x) {
    final bits = _bitsOf(x);
    return bits < 0 ? -(bits & 0x7fffffffffffffff) : bits;
  }

  return (ordered(a) - ordered(b)).abs();
}
