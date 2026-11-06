// The integer square root every kernel takes — the blend family's soft
// light, the timeline's coverage, whatever comes next (gpu-canonical-store,
// 관제 14:51: one function in one place, however different a second
// spelling's text). Needs nothing before it.

// round(√n) for any u32 n, digit by digit — no float, so no backend's
// square root. (r+1)² is never formed: n - r² > r says the root rounds up,
// and no integer n sits on a half, so there is no tie to break.
fn isqrt_round(n: u32) -> u32 {
  var rest = n;
  var root = 0u;
  var bit = 1u << 30u;
  while (bit > rest) {
    bit = bit >> 2u;
  }
  while (bit != 0u) {
    if (rest >= root + bit) {
      rest = rest - (root + bit);
      root = (root >> 1u) + bit;
    } else {
      root = root >> 1u;
    }
    bit = bit >> 2u;
  }
  return select(root, root + 1u, rest > root);
}
