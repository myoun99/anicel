import 'dart:typed_data';

// ====================================================
// Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
//
// Developed at SunPro, a Sun Microsystems, Inc. business.
// Permission to use, copy, modify, and distribute this
// software is freely granted, provided that this notice
// is preserved.
// ====================================================
//
// ====================================================
// Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
//
// Developed at SunSoft, a Sun Microsystems, Inc. business.
// Permission to use, copy, modify, and distribute this
// software is freely granted, provided that this notice
// is preserved.
// ====================================================
//
// ====================================================
// Copyright (C) 2004 by Sun Microsystems, Inc. All rights reserved.
//
// Permission to use, copy, modify, and distribute this
// software is freely granted, provided that this notice
// is preserved.
// ====================================================
//
// (FreeBSD msun's notices: the first is s_sin.c's, s_cos.c's and
// e_rem_pio2.c's, the second k_sin.c's and k_cos.c's, the third e_exp.c's
// — the files these are ported from by way of the `libm` crate 0.2.16 the
// GPU engine calls. assets/licenses/LICENSE-fdlibm.txt carries them to the
// about screen.)

/// 🗣️gpu-same-formula (유저 2026-11-05 「기기가 달라도 같아야 한다」) ·
/// native-to-rust-Q14 (2026-11-07): a sine, a cosine and an exponential
/// the same to the last bit on every device. `dart:math`'s call the
/// device's maths library, which IEEE does not require to round correctly:
/// glibc's and the Windows CRT's part in a last bit (board
/// `linux-libm-hands-the-engine-other-last-bits` — the values the app
/// hands the engine went red on Linux against a ledger pinned on Windows).
///
/// These are FreeBSD msun's, line for line as the `libm` crate the GPU
/// engine calls has them (the engine's vendored crates call it for the
/// same reason, `one_maths.rs`): IEEE's own operations alone — add,
/// subtract, multiply, divide, each rounded exactly everywhere — so a
/// device cannot round them otherwise. Within an ulp of the true value.
///
/// ⚠️Past 2^20·π/2 (about 1.6 million radians) msun reduces an angle by
/// π/2 to 1584 bits (`rem_pio2_large`); this keeps the medium reduction
/// there instead — the same on every device still, if less exact, and no
/// angle the app turns by comes near.
double alikeSin(double x) {
  final ix = _highWord(x) & 0x7fffffff;
  if (ix <= 0x3fe921fb) {
    // |x| < 2^-26: x itself.
    if (ix < 0x3e500000) {
      return x;
    }
    return _kernelSin(x, 0, 0);
  }
  if (ix >= 0x7ff00000) {
    return x - x;
  }
  final (n, y0, y1) = _reducedByHalfPi(x, ix);
  return switch (n & 3) {
    0 => _kernelSin(y0, y1, 1),
    1 => _kernelCos(y0, y1),
    2 => -_kernelSin(y0, y1, 1),
    _ => -_kernelCos(y0, y1),
  };
}

/// The cosine of [x] radians, the same on every device ([alikeSin]).
double alikeCos(double x) {
  final ix = _highWord(x) & 0x7fffffff;
  if (ix <= 0x3fe921fb) {
    // |x| < 2^-27·√2: 1.
    if (ix < 0x3e46a09e) {
      return 1;
    }
    return _kernelCos(x, 0);
  }
  if (ix >= 0x7ff00000) {
    return x - x;
  }
  final (n, y0, y1) = _reducedByHalfPi(x, ix);
  return switch (n & 3) {
    0 => _kernelCos(y0, y1),
    1 => -_kernelSin(y0, y1, 1),
    2 => -_kernelCos(y0, y1),
    _ => _kernelSin(y0, y1, 1),
  };
}

/// e to the [x], the same on every device ([alikeSin]): [x] as k·ln 2 + r,
/// |r| ≤ ln 2 / 2, e^r by msun's rational fit, scaled by 2^k.
double alikeExp(double x) {
  final high = _highWord(x);
  final sign = high >> 31;
  final hx = high & 0x7fffffff;
  if (hx >= 0x4086232b) {
    if (x.isNaN) {
      return x;
    }
    if (x > 709.782712893383973096) {
      return x * _twoTo1023;
    }
    if (x < -745.13321910194110842) {
      return 0;
    }
  }
  final double hi;
  final double lo;
  final int k;
  if (hx > 0x3fd62e42) {
    k = hx >= 0x3ff0a2b2
        ? (_invLn2 * x + (sign == 0 ? 0.5 : -0.5)).toInt()
        : 1 - sign - sign;
    hi = x - k.toDouble() * _ln2Hi;
    lo = k.toDouble() * _ln2Lo;
  } else if (hx > 0x3e300000) {
    k = 0;
    hi = x;
    lo = 0;
  } else {
    return 1 + x;
  }
  final r = hi - lo;
  final rr = r * r;
  final c = r - rr * (_p1 + rr * (_p2 + rr * (_p3 + rr * (_p4 + rr * _p5))));
  final y = 1 + (r * c / (2 - c) - lo + hi);
  return k == 0 ? y : _scaledByTwoTo(y, k);
}

/// msun's __kernel_sin: sin of [x] + [y] for |x + y| ≤ π/4, [y] the tail
/// of a reduced angle — read where [iy] is 1.
double _kernelSin(double x, double y, int iy) {
  final z = x * x;
  final w = z * z;
  final r = _s2 + z * (_s3 + z * _s4) + z * w * (_s5 + z * _s6);
  final v = z * x;
  return iy == 0
      ? x + v * (_s1 + z * r)
      : x - ((z * (0.5 * y - v * r) - y) - v * _s1);
}

/// msun's __kernel_cos: cos of [x] + [y] for |x + y| ≤ π/4.
double _kernelCos(double x, double y) {
  final z = x * x;
  final w = z * z;
  final r =
      z * (_c1 + z * (_c2 + z * _c3)) + w * w * (_c4 + z * (_c5 + z * _c6));
  final hz = 0.5 * z;
  final one = 1 - hz;
  return one + (((1 - one) - hz) + (z * r - x * y));
}

/// msun's __ieee754_rem_pio2: [x] as n·π/2 + (y0 + y1), |y0 + y1| ≤ π/4 —
/// its exact cases near the first quarter turns, then the medium
/// reduction ([alikeSin] on where that stops).
(int, double, double) _reducedByHalfPi(double x, int ix) {
  final positive = _highWord(x) >> 31 == 0;
  (int, double, double) quarters(int n) {
    final turns = n.toDouble();
    if (positive) {
      final z = x - turns * _halfPi1;
      final y0 = z - turns * _halfPi1Tail;
      return (n, y0, (z - y0) - turns * _halfPi1Tail);
    }
    final z = x + turns * _halfPi1;
    final y0 = z + turns * _halfPi1Tail;
    return (-n, y0, (z - y0) + turns * _halfPi1Tail);
  }

  if (ix <= 0x400f6a7a) {
    // |x| ~<= 5π/4; near π/2 and π the cancellation takes the medium way.
    if ((ix & 0xfffff) == 0x921fb) {
      return _mediumReduction(x, ix);
    }
    return quarters(ix <= 0x4002d97c ? 1 : 2);
  }
  if (ix <= 0x401c463b) {
    // |x| ~<= 9π/4; near 3π/2 and 2π, the medium way.
    if (ix <= 0x4015fdbc) {
      return ix == 0x4012d97c ? _mediumReduction(x, ix) : quarters(3);
    }
    return ix == 0x401921fb ? _mediumReduction(x, ix) : quarters(4);
  }
  return _mediumReduction(x, ix);
}

/// msun's medium reduction: n = rint(x / (π/2)) by the round-to-integer
/// sum, then x − n·π/2 in up to three rounds of π/2's split bits.
(int, double, double) _mediumReduction(double x, int ix) {
  final rounded = (x * _invHalfPi + _toInteger) - _toInteger;
  final n = rounded.toInt();
  var r = x - rounded * _halfPi1;
  var w = rounded * _halfPi1Tail;
  var y0 = r - w;
  final ex = ix >> 20;
  if (ex - ((_highWord(y0) >> 20) & 0x7ff) > 16) {
    var t = r;
    w = rounded * _halfPi2;
    r = t - w;
    w = rounded * _halfPi2Tail - ((t - r) - w);
    y0 = r - w;
    if (ex - ((_highWord(y0) >> 20) & 0x7ff) > 49) {
      t = r;
      w = rounded * _halfPi3;
      r = t - w;
      w = rounded * _halfPi3Tail - ((t - r) - w);
      y0 = r - w;
    }
  }
  return (n, y0, (r - y0) - w);
}

/// [x]·2^[n] (the `libm` crate's scalbn): pre-scaled by 2^±1023-ish where
/// 2^n itself is out of range.
double _scaledByTwoTo(double x, int n) {
  var y = x;
  var e = n;
  if (e > 1023) {
    y *= _twoTo1023;
    e -= 1023;
    if (e > 1023) {
      y *= _twoTo1023;
      e -= 1023;
      if (e > 1023) {
        e = 1023;
      }
    }
  } else if (e < -1022) {
    y *= _twoToMinus969;
    e += 969;
    if (e < -1022) {
      y *= _twoToMinus969;
      e += 969;
      if (e < -1022) {
        e = -1022;
      }
    }
  }
  return y * _ofWords((0x3ff + e) << 20, 0);
}

final ByteData _word = ByteData(8);

int _highWord(double x) {
  _word.setFloat64(0, x, Endian.little);
  return _word.getUint32(4, Endian.little);
}

/// The double whose high and low 32 bits are [high] and [low] — how each
/// constant below is written, bit for bit as msun has it.
double _ofWords(int high, int low) {
  _word.setUint32(4, high, Endian.little);
  _word.setUint32(0, low, Endian.little);
  return _word.getFloat64(0, Endian.little);
}

final _s1 = _ofWords(0xBFC55555, 0x55555549);
final _s2 = _ofWords(0x3F811111, 0x1110F8A6);
final _s3 = _ofWords(0xBF2A01A0, 0x19C161D5);
final _s4 = _ofWords(0x3EC71DE3, 0x57B1FE7D);
final _s5 = _ofWords(0xBE5AE5E6, 0x8A2B9CEB);
final _s6 = _ofWords(0x3DE5D93A, 0x5ACFD57C);

final _c1 = _ofWords(0x3FA55555, 0x5555554C);
final _c2 = _ofWords(0xBF56C16C, 0x16C15177);
final _c3 = _ofWords(0x3EFA01A0, 0x19CB1590);
final _c4 = _ofWords(0xBE927E4F, 0x809C52AD);
final _c5 = _ofWords(0x3E21EE9E, 0xBDB4B1C4);
final _c6 = _ofWords(0xBDA8FAE9, 0xBE8838D4);

final _invHalfPi = _ofWords(0x3FE45F30, 0x6DC9C883);
final _halfPi1 = _ofWords(0x3FF921FB, 0x54400000);
final _halfPi1Tail = _ofWords(0x3DD0B461, 0x1A626331);
final _halfPi2 = _ofWords(0x3DD0B461, 0x1A600000);
final _halfPi2Tail = _ofWords(0x3BA3198A, 0x2E037073);
final _halfPi3 = _ofWords(0x3BA3198A, 0x2E000000);
final _halfPi3Tail = _ofWords(0x397B839A, 0x252049C1);

/// 1.5·2^52: added and taken away, it rounds to an integer.
const double _toInteger = 6755399441055744;

final _ln2Hi = _ofWords(0x3FE62E42, 0xFEE00000);
final _ln2Lo = _ofWords(0x3DEA39EF, 0x35793C76);
final _invLn2 = _ofWords(0x3FF71547, 0x652B82FE);
final _p1 = _ofWords(0x3FC55555, 0x5555553E);
final _p2 = _ofWords(0xBF66C16C, 0x16BEBD93);
final _p3 = _ofWords(0x3F11566A, 0xAF25DE2C);
final _p4 = _ofWords(0xBEBBBD41, 0xC5D26BF1);
final _p5 = _ofWords(0x3E663769, 0x72BEA4D0);

final _twoTo1023 = _ofWords(0x7FE00000, 0);

/// 2^-1022 · 2^53, msun's step into the subnormals.
final _twoToMinus969 = _ofWords(0x03600000, 0);
