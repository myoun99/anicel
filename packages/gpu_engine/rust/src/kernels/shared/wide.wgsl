// Signed 64- and 128-bit integers on u32 words. WGSL has no 64-bit
// integer, and the integer specs need exact sums and products past 32 bits
// (gpu-int-spec-canvas 1b 공통: an i64 is two u32 emulated exactly, a
// product is four 16-bit pieces; a device with SHADER_INT64 would get the
// same values, being integers). Two's complement throughout, so a sum
// wraps as an i64 does — keeping a value in range is the caller's.
// Needs nothing before it.

// x the low word, y the high.
alias Wide = vec2<u32>;
// x the lowest word.
alias Wide128 = vec4<u32>;

fn wide(v: i32) -> Wide {
  return Wide(bitcast<u32>(v), select(0u, 0xffffffffu, v < 0));
}

fn wide_add(a: Wide, b: Wide) -> Wide {
  let low = a.x + b.x;
  return Wide(low, a.y + b.y + select(0u, 1u, low < a.x));
}

fn wide_neg(a: Wide) -> Wide {
  return wide_add(~a, Wide(1u, 0u));
}

fn wide_sub(a: Wide, b: Wide) -> Wide {
  return wide_add(a, wide_neg(b));
}

fn wide_negative(a: Wide) -> bool {
  return (a.y >> 31u) != 0u;
}

// |a| read as unsigned, so |i64::MIN| is 2^63 rather than itself.
fn wide_abs(a: Wide) -> Wide {
  return select(a, wide_neg(a), wide_negative(a));
}

fn wide_less(a: Wide, b: Wide) -> bool {
  let high_a = bitcast<i32>(a.y);
  let high_b = bitcast<i32>(b.y);
  return high_a < high_b || (high_a == high_b && a.x < b.x);
}

// a < b with both read as unsigned.
fn wide_below(a: Wide, b: Wide) -> bool {
  return a.y < b.y || (a.y == b.y && a.x < b.x);
}

// Whether a is an i32 — the high word only repeats the low's sign.
fn wide_fits(a: Wide) -> bool {
  return a.y == bitcast<u32>(bitcast<i32>(a.x) >> 31u);
}

// a >> k, arithmetic, 0 <= k < 64. A shift by 32 or more is taken modulo
// 32 in WGSL, so the word that would need one is moved instead.
fn wide_shr(a: Wide, k: u32) -> Wide {
  let high = bitcast<i32>(a.y);
  if (k == 0u) {
    return a;
  }
  if (k < 32u) {
    return Wide((a.x >> k) | (a.y << (32u - k)), bitcast<u32>(high >> k));
  }
  return Wide(bitcast<u32>(high >> (k - 32u)), bitcast<u32>(high >> 31u));
}

// a << k, 0 <= k < 64; what passes the top is lost.
fn wide_shl(a: Wide, k: u32) -> Wide {
  if (k == 0u) {
    return a;
  }
  if (k < 32u) {
    return Wide(a.x << k, (a.y << k) | (a.x >> (32u - k)));
  }
  return Wide(0u, a.x << (k - 32u));
}

// rnd(a, k) = (a + 2^(k-1)) >> k — a half always goes up. 1 <= k < 64.
fn wide_round(a: Wide, k: u32) -> Wide {
  return wide_shr(wide_add(a, wide_shl(Wide(1u, 0u), k - 1u)), k);
}

// The exact product of two u32 from four 16-bit pieces.
fn wide_mul_u32(a: u32, b: u32) -> Wide {
  let low_a = a & 0xffffu;
  let high_a = a >> 16u;
  let low_b = b & 0xffffu;
  let high_b = b >> 16u;
  let low = low_a * low_b;
  let cross_one = low_a * high_b;
  let cross = cross_one + high_a * low_b;
  // A cross sum past 2^32 carries 2^48, which is 2^16 in the high word.
  let cross_carry = select(0u, 0x10000u, cross < cross_one);
  let word = low + (cross << 16u);
  let carry = select(0u, 1u, word < low);
  return Wide(word, high_a * high_b + (cross >> 16u) + cross_carry + carry);
}

fn wide_magnitude32(a: i32) -> u32 {
  return select(bitcast<u32>(a), 0u - bitcast<u32>(a), a < 0);
}

// The exact product of two i32.
fn wide_mul_i32(a: i32, b: i32) -> Wide {
  let product = wide_mul_u32(wide_magnitude32(a), wide_magnitude32(b));
  return select(product, wide_neg(product), (a < 0) != (b < 0));
}

fn wide128_add(a: Wide128, b: Wide128) -> Wide128 {
  let low = wide_add(a.xy, b.xy);
  let carry = select(0u, 1u, wide_below(low, a.xy));
  return Wide128(low, wide_add(wide_add(a.zw, b.zw), Wide(carry, 0u)));
}

fn wide128_neg(p: Wide128) -> Wide128 {
  return wide128_add(~p, Wide128(1u, 0u, 0u, 0u));
}

// The exact product of two i64: the magnitudes' four u32 products summed
// by columns, then the sign.
fn wide_mul128(a: Wide, b: Wide) -> Wide128 {
  let magnitude_a = wide_abs(a);
  let magnitude_b = wide_abs(b);
  let ll = wide_mul_u32(magnitude_a.x, magnitude_b.x);
  let lh = wide_mul_u32(magnitude_a.x, magnitude_b.y);
  let hl = wide_mul_u32(magnitude_a.y, magnitude_b.x);
  let hh = wide_mul_u32(magnitude_a.y, magnitude_b.y);
  let s1 = ll.y + lh.x;
  let c1 = select(0u, 1u, s1 < ll.y);
  let w1 = s1 + hl.x;
  let c1_more = select(0u, 1u, w1 < s1);
  let s2 = lh.y + hl.y;
  let c2 = select(0u, 1u, s2 < lh.y);
  let s2_more = s2 + hh.x;
  let c2_more = select(0u, 1u, s2_more < s2);
  // The carries into it are two at most, so adding them carries once at most.
  let w2 = s2_more + c1 + c1_more;
  let c2_last = select(0u, 1u, w2 < s2_more);
  let product = Wide128(ll.x, w1, w2, hh.y + c2 + c2_more + c2_last);
  return select(product, wide128_neg(product), wide_negative(a) != wide_negative(b));
}

// The low 64 bits of a · b — the product itself while it fits.
fn wide_mul(a: Wide, b: Wide) -> Wide {
  return wide_mul128(a, b).xy;
}

// p >> k, arithmetic, 0 <= k < 64.
fn wide128_shr(p: Wide128, k: u32) -> Wide128 {
  var q = p;
  var s = k;
  if (s >= 32u) {
    q = Wide128(q.y, q.z, q.w, bitcast<u32>(bitcast<i32>(q.w) >> 31u));
    s = s - 32u;
  }
  if (s == 0u) {
    return q;
  }
  return Wide128(
    (q.x >> s) | (q.y << (32u - s)),
    (q.y >> s) | (q.z << (32u - s)),
    (q.z >> s) | (q.w << (32u - s)),
    bitcast<u32>(bitcast<i32>(q.w) >> s),
  );
}

// rnd(p, k) of a 128-bit value, 1 <= k < 64.
fn wide128_round(p: Wide128, k: u32) -> Wide128 {
  let half = wide_shl(Wide(1u, 0u), k - 1u);
  return wide128_shr(wide128_add(p, Wide128(half, 0u, 0u)), k);
}

// Whether p is an i64 — the high words only repeat its sign.
fn wide128_fits(p: Wide128) -> bool {
  let sign = bitcast<u32>(bitcast<i32>(p.y) >> 31u);
  return p.z == sign && p.w == sign;
}

// ⌊n / d⌋ for n >= 0 and 0 < d < 2^63, when the quotient is below 2^bits
// (1 <= bits <= 64) — restoring division, n's low `bits` bits shifted in
// one at a time under n >> bits: the rest stays below d, so every step is
// on two words whatever n's width. ⛔THE ONE LONG DIVISION (CLAUDE.md
// 절대명령 1): ⌊2^e / d⌋'s and a 64-bit dividend's were two walks of their
// own until the lens blur's mean, a 128-bit dividend, made the third
// (11-05) — every division below is this one.
fn wide128_div(n: Wide128, d: Wide, bits: u32) -> Wide {
  var rest = n.zw;
  if (bits < 64u) {
    rest = wide128_shr(n, bits).xy;
  }
  var quotient = Wide(0u, 0u);
  for (var k = bits; k > 0u; k = k - 1u) {
    let at = k - 1u;
    rest = wide_shl(rest, 1u);
    rest.x = rest.x | ((n[at / 32u] >> (at % 32u)) & 1u);
    if (!wide_below(rest, d)) {
      rest = wide_sub(rest, d);
      quotient[at / 32u] = quotient[at / 32u] | (1u << (at % 32u));
    }
  }
  return quotient;
}

// divr(n, d) = ⌊(2n + d) / (2d)⌋ for n >= 0 and 0 < d < 2^62, when the
// quotient is below 2^bits.
fn wide128_divr(n: Wide128, d: Wide, bits: u32) -> Wide {
  return wide128_div(wide128_add(wide128_add(n, n), Wide128(d, 0u, 0u)), wide_shl(d, 1u), bits);
}

// ⌊2^e / d⌋ for 0 < d < 2^63 and e < 128, when the quotient fits in 63 bits.
fn wide_pow2_over(e: u32, d: Wide) -> Wide {
  var power = Wide128(0u, 0u, 0u, 0u);
  power[e / 32u] = 1u << (e % 32u);
  return wide128_div(power, d, 64u);
}

// ⌊n / d⌋ of an unsigned n, 0 < d < 2^63, when the quotient is below 2^bits
// (bits <= 32).
fn wide_div_floor(n: Wide, d: Wide, bits: u32) -> u32 {
  return wide128_div(Wide128(n, 0u, 0u), d, bits).x;
}

// divr(n, d) of an unsigned n, 0 < d < 2^62, when the quotient is below
// 2^bits (bits <= 32).
fn wide_divr(n: Wide, d: Wide, bits: u32) -> u32 {
  return wide128_divr(Wide128(n, 0u, 0u), d, bits).x;
}

// ⌊√n⌋ for 0 <= n < 2^62, digit by digit from 2^60, the top digit such an
// n has — a digit above n only halves a root of nothing, so there is no
// walk down to it first. ⚠️isqrt.wgsl's isqrt_round is the same walk on
// one word, rounded — two, so not yet one function (rule of 3, CLAUDE.md
// 절대명령 1: the third merges them).
fn wide_isqrt(n: Wide) -> u32 {
  var rest = n;
  var root = Wide(0u, 0u);
  var bit = Wide(0u, 1u << 28u);
  while (bit.x != 0u || bit.y != 0u) {
    let next = wide_add(root, bit);
    if (!wide_below(rest, next)) {
      rest = wide_sub(rest, next);
      root = wide_add(wide_shr(root, 1u), bit);
    } else {
      root = wide_shr(root, 1u);
    }
    bit = wide_shr(bit, 2u);
  }
  return root.x;
}
