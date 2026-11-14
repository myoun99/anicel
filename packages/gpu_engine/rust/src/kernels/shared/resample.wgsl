// R1, the integer resample: one destination pixel from the source through
// the destination-to-source map, every value an integer with its bits and
// its rounding fixed by the spec (gpu-int-spec-canvas 1b (1/4) R1). The
// executor's rows and the canvas's selection transforms call this one
// function (관제 14:51). The spec is the source: where this file and that
// card part, ask the card's owner, canvas base.
//
// ⚠️The measurements in these notes were taken on the CPU reference R1 —
// this algorithm in doubles (`resample_kernel.dart`, gone 2026-11-13,
// tip-coverage-is-a-second-r1), its contracts pinned on this one since.
//
// ## Why two modes and not two resamplers
//
// Preserving the source colours exactly means the last operation has to be
// a CHOICE, not a mixture — and "smooth when enlarged" is precisely the
// production of in-between values. Those requirements collide head-on, so
// no single accumulator can serve both. What CAN be shared is everything
// before it: the inverse map, the Jacobian, the exact-translation short
// circuit and the flat-support early-out. The accumulator splits, and so
// does the way each one reaches into the source:
//
// * Blend (RESAMPLE_BLEND) — gathers taps under a tent and takes their
//   weighted mean. New colours by definition.
// * Pick (RESAMPLE_PICK) — supersamples the preimage and elects the colour
//   holding the most of it, copying its 32-bit word through byte for
//   byte.
//
// The bit that selects the branch comes from a property the user set, not
// from inspecting the picture.
//
// ## The contract Pick keeps
//
// > Every output pixel is a byte-exact copy of some input pixel that
// > overlapped that pixel's preimage.
//
// Stated about provenance rather than about colour counts, it is
// content-independent and mechanically testable.
//
// The invariant that makes it true: **a Pick payload never enters colour
// arithmetic.** It is carried as one 32-bit word, compared as one word and
// stored as one word. Splitting it into channels, premultiplying it, or
// letting it through an unpremultiply is how a resampler that advertises
// "no anti-aliasing" still leaks a couple of least-significant bits.
//
// ## Footprint
//
// A destination pixel is not a point: it is a unit square whose preimage
// is a parallelogram, and sampling it as a point is exactly what makes
// nearest-neighbour drop thin lines under reduction. Both modes read that
// preimage — but they read it in different ways, and the difference is
// the whole design.
//
// **Blend reconstructs**, so it needs a filter support. The radius comes
// from the inverse Jacobian — one output step along x moves `(a, d)` in
// source space, one along y moves `(b, e)` — so the tent reaches
// `|a| + |b|` horizontally and `|d| + |e|` vertically. Those extents
// describe the preimage's axis-aligned BOUNDING BOX rather than the
// preimage, which for a weighted mean is a slightly wider blur and
// nothing worse.
//
// **Pick elects**, and an election held over the bounding box is not an
// election over the preimage. A rotation makes the box bigger than what
// it contains by `1 + |sin 2θ|` — twice the area at 45° — and every
// square unit of the excess is ground the destination pixel never
// reached. Three rounds of separable weighting tried to shrink that box
// back down onto the parallelogram, and all three failed the same way,
// because a product of two one-dimensional weights integrates over a
// RECTANGLE and a rotated anisotropic preimage is not one: shrink the box
// and no tap scores at all, so opaque artwork grows transparent holes;
// leave it and taps outside the image outvote the taps inside it. The
// problem is not which box.
//
// So Pick does not use a box. It SUPERSAMPLES: the destination pixel is
// cut into an N×N grid, every subsample goes through the same inverse
// map, and whichever source pixel it lands in gets a vote. The colour
// holding the most votes wins, and that IS the area argmax by
// construction — of the true preimage, at any angle, under any
// anisotropy, through a perspective divide, none of which the accumulator
// needs to know about. There is no footprint to starve and none to flood.
// (Here a homography's subsamples move by its Jacobian at the pixel
// centre — resample_landing — rather than each through the divide.)
// `test/services/resample/coverage_truth.dart` is the same computation
// written for clarity rather than speed, and the kernel is pinned against
// it.
//
// The measured consequence: a one-pixel LINE now survives while
// `scale > 0.5` at EVERY angle, where the boxed version needed
// `scale > (|cos θ| + |sin θ|)/2` — 0.707 at 45°, which is why an
// ordinary rotate-and-shrink used to erase line art.
//
// An ISOLATED one-pixel mark is a different sum and a different bound: it
// holds `scale²` of its preimage against a ground that votes as one
// token, so it needs `scale > 1/√2` at every angle including 0°. That is
// the area argmax answering correctly rather than a footprint failing —
// the oracle drops it in the same place.
//
// The radius floor is 1.0 and belongs to Blend alone now; Pick has no
// radius left to floor (the app's kSelectionResampleRadiusFloor says why).
//
// Needs shared/wide.wgsl before it. Its host defines
//   fn resample_texel(source: u32, x: i32, y: i32) -> u32
// — the straight RGBA8 word (A<<24|B<<16|G<<8|R) at (x, y) of whichever
// source `source` names, 0 outside it.
//
// The rounding names are the spec's: rnd(x, k) = (x + 2^(k-1)) >> k,
// arithmetic, so a half always goes up; divr(n, d) = ⌊(2n + d) / (2d)⌋.
// Positions are Q.16 source pixels; |u| >= 2^31 is outside.

const RESAMPLE_BLEND: u32 = 0u;
const RESAMPLE_PICK: u32 = 1u;
// A whole-pixel translation in any mode, copied word for word — decided
// once on the CPU (resample.rs), where the plan reading the map needs it too.
const RESAMPLE_COPY: u32 = 2u;
const RESAMPLE_NEAREST: u32 = 3u;

// 1 in Q.20, the matrix's scale.
const RESAMPLE_ONE: i32 = 1048576;
// Blend's radius ceiling and exact Pick's widest preimage: 16 px, Q.16.
//
// Unlike the floor this is not a quality knob. A homography re-derives the
// radius per pixel from `1/w` while the destination size stays fixed, so
// it grows as `1/w²` with nothing to cancel it: an ordinary corner-pin
// whose far edge is 6% of its near edge reaches r=262 — 2.8e5 taps for ONE
// output pixel, and about a second for a single 256×256 tile.
//
// Clamping is contract-safe because a narrower tent is still convex, so
// Blend still cannot ring. Past the bound minification aliases exactly as
// a mip-less sampler does, which is the honest trade.
//
// Pick needs none of this. The same corner-pin costs it 256 samples like
// every other pixel, because the subsample ceiling (resample_samples)
// bounds the work where a radius had to be clamped to.
const RESAMPLE_CEILING: u32 = 1048576u;
// A homography's w at or below 2^-12 (Q.37) is outside.
const RESAMPLE_W_FLOOR: u32 = 33554432u;
// Pick's vote table: sixteen slots is not a guess. A cel's preimage at
// these sizes holds a handful of flat colours, and the two-value line art
// this exists for holds two. On overflow the LIGHTEST incumbent is evicted
// and hands its count to the newcomer (resample_vote), which is what makes
// the guarantee statable: any token owning more than a sixteenth of the
// samples is still in the table when the vote is counted. Dropping the
// newcomer instead — the obvious cheap policy — lets a colour covering 99%
// of a preimage lose to one covering 0.1%.
const RESAMPLE_SLOTS: u32 = 16u;
// How far a tied Pick vote refines, per axis.
//
// resample_samples sets a rate that resolves an ordinary preimage; a pixel
// whose top two colours come back with equal counts is re-sampled at twice
// that, up to this.
//
// Not refining at all is not an option: it kept 54% of the oracle's ink
// at 0.55×, which is a hairline going missing.
//
// 16 rather than 32 is a cost call, and the honest version of it is
// narrower than the one this comment used to make. **A second doubling
// does change pixels** — 397 across a three-fixture sweep, and it fixes
// most of the decisively-wrong ones the sampler still has. What makes 16
// defensible is that the failures it leaves are almost all AXIS-ALIGNED,
// and those no longer reach the sampler at all: they go down the exact
// path (resample_pick_exact), where there is no quantisation to refine
// away. What is left for the sampler is rotated work, where one doubling
// is enough and a second costs 1.1–1.7× on a full canvas for pixels
// nobody can pick out.
//
// ⚠️ And do not repeat the claim this replaced — "ties that survive the
// cap are the real ones, a feature covering exactly half". Traced, the
// surviving ties were 55/45, not 50/50. The proof that SOME ties are
// unbreakable is not a proof that all surviving ones are, which is the
// same shape of error as the round before: a bound asserted in a comment,
// believed, and wrong.
const RESAMPLE_REFINE: u32 = 16u;

// The modes a host's pass may meet, fixed when its pipeline is made: a mode
// it never meets is compiled out, as what a pass holds compiled costs it
// whether it runs or not — Pick's vote table alone held a 1080p composite
// of no row at 321 µs of GPU where it holds 150 without (RTX 4080, DX12,
// 브러시/렌더링 11-06). All in unless the host says, and the copy always;
// a host hands a pass only maps of the modes it compiled in (the executor
// takes them from the words it hands it, resample.rs `ResampleModes`).
override resample_with_blend: bool = true;
override resample_with_pick: bool = true;
override resample_with_nearest: bool = true;

// Whether a pass meets a map other than the copy, so locates a point: a
// host's own call of resample_locate under it is dropped with R1's.
fn resample_with_locate() -> bool {
  return resample_with_blend || resample_with_pick || resample_with_nearest;
}

// Words one map takes, resample.rs's ResampleMap::WORDS.
const RESAMPLE_MAP_WORDS: u32 = 16u;

// The map as the CPU quantised it once: x' = a·x + b·y + c and the rest,
// a homography divided through by its corner w farthest from 0, so w is
// positive on the side of the output's centre.
struct ResampleMap {
  // Q.20
  a: i32,
  b: i32,
  d: i32,
  e: i32,
  // Q.(36 − shift)
  g: i32,
  h: i32,
  // Blend's radius floor, Q.16.
  floor: u32,
  // RESAMPLE_BLEND, RESAMPLE_PICK or RESAMPLE_COPY.
  mode: u32,
  // Q.20
  c: Wide,
  f: Wide,
  // Q.36
  i: Wide,
  // 0 when g = h = 0 and i = 1, so the map is affine — decided once on the
  // CPU (resample.rs), where the plan reading the map needs it too.
  projective: u32,
  // How much coarser than Q.36 g and h are held: 0 but for a steep
  // homography, whose g or h is past an i32 at Q.36 (resample.rs).
  shift: u32,
}

// The map from the words resample.rs's ResampleMap::words lays down, in
// the order a host keeps them — the one place that order is read.
fn resample_map(w: array<u32, RESAMPLE_MAP_WORDS>) -> ResampleMap {
  return ResampleMap(
    bitcast<i32>(w[0]),
    bitcast<i32>(w[1]),
    bitcast<i32>(w[2]),
    bitcast<i32>(w[3]),
    bitcast<i32>(w[4]),
    bitcast<i32>(w[5]),
    w[6],
    w[7],
    Wide(w[8], w[9]),
    Wide(w[10], w[11]),
    Wide(w[12], w[13]),
    w[14],
    w[15],
  );
}

// Where a destination pixel's centre lands and what its preimage spans.
struct ResamplePoint {
  // Q.16, the pixel's own centre at 0.5: rnd(u, 16) is the nearest pixel.
  u: i32,
  v: i32,
  // |du/dx| + |du/dy| and the same for v, Q.16 — a homography's capped
  // at the ceiling, past which no reader tells them apart.
  extent: vec2<u32>,
  // The Jacobian, Q.16, a homography's only: [du/dx, du/dy, dv/dx, dv/dy].
  du_dx: Wide,
  du_dy: Wide,
  dv_dx: Wide,
  dv_dy: Wide,
}

fn resample_affine(map: ResampleMap) -> bool {
  return map.projective == 0u;
}

// rnd(u, 16) without forming u + 2^15, which passes i32 near the edge.
fn resample_round16(u: i32) -> i32 {
  return (u >> 16u) + ((u >> 15u) & 1);
}

// |u| < 2^31: an i32 other than its minimum.
fn resample_within(a: Wide) -> bool {
  return wide_fits(a) && a.x != 0x80000000u;
}

// a·X + b·Y + 2c — the numerator at doubled pixel coordinates, Q.21.
fn resample_numerator(a: i32, b: i32, c: Wide, xx: i32, yy: i32) -> Wide {
  return wide_add(wide_add(wide_mul_i32(a, xx), wide_mul_i32(b, yy)), wide_shl(c, 1u));
}

// One Jacobian entry: rnd((m − rnd(projected · n, 32 − shift)) · r, 41),
// Q.16.
fn resample_derivative(m: i32, projected: Wide, n: i32, shift: u32, r: Wide) -> Wide {
  let slope = wide_sub(wide(m), wide_round(wide_mul(projected, wide(n)), 32u - shift));
  return wide128_round(wide_mul128(slope, r), 41u).xy;
}

fn resample_capped(a: Wide) -> u32 {
  return select(a.x, RESAMPLE_CEILING, a.y != 0u || a.x > RESAMPLE_CEILING);
}

// Locates pixel (x, y) — absolute, a clip already added — in the source;
// false when it lands outside.
fn resample_locate(map: ResampleMap, x: i32, y: i32, point: ptr<function, ResamplePoint>) -> bool {
  let xx = 2 * x + 1;
  let yy = 2 * y + 1;
  let nu = resample_numerator(map.a, map.b, map.c, xx, yy);
  let nv = resample_numerator(map.d, map.e, map.f, xx, yy);
  if (resample_affine(map)) {
    let half = wide(RESAMPLE_ONE);
    let u = wide_round(wide_sub(nu, half), 5u);
    let v = wide_round(wide_sub(nv, half), 5u);
    if (!resample_within(u) || !resample_within(v)) {
      return false;
    }
    (*point).u = bitcast<i32>(u.x);
    (*point).v = bitcast<i32>(v.x);
    let extent_u = wide_round(wide_add(wide(abs(map.a)), wide(abs(map.b))), 4u);
    let extent_v = wide_round(wide_add(wide(abs(map.d)), wide(abs(map.e))), 4u);
    (*point).extent = vec2<u32>(extent_u.x, extent_v.x);
    return true;
  }
  let gh = wide_add(wide_mul_i32(map.g, xx), wide_mul_i32(map.h, yy));
  let w = wide_add(wide_shl(gh, map.shift), wide_shl(map.i, 1u));
  if (!wide_less(Wide(RESAMPLE_W_FLOOR, 0u), w)) {
    return false;
  }
  // 1/w, Q.37.
  let r = wide_pow2_over(74u, w);
  let pu = wide128_round(wide_mul128(nu, r), 42u);
  let pv = wide128_round(wide_mul128(nv, r), 42u);
  if (!wide128_fits(pu) || !wide128_fits(pv)) {
    return false;
  }
  let half = Wide(32768u, 0u);
  let u = wide_sub(pu.xy, half);
  let v = wide_sub(pv.xy, half);
  if (!resample_within(u) || !resample_within(v)) {
    return false;
  }
  (*point).u = bitcast<i32>(u.x);
  (*point).v = bitcast<i32>(v.x);
  (*point).du_dx = resample_derivative(map.a, pu.xy, map.g, map.shift, r);
  (*point).du_dy = resample_derivative(map.b, pu.xy, map.h, map.shift, r);
  (*point).dv_dx = resample_derivative(map.d, pv.xy, map.g, map.shift, r);
  (*point).dv_dy = resample_derivative(map.e, pv.xy, map.h, map.shift, r);
  (*point).extent = vec2<u32>(
    resample_capped(wide_add(wide_abs((*point).du_dx), wide_abs((*point).du_dy))),
    resample_capped(wide_add(wide_abs((*point).dv_dx), wide_abs((*point).dv_dy))),
  );
  return true;
}

// Whether every source pixel within (reach.x, reach.y) of the centre holds
// one word — then both modes answer that word: there is nothing to average
// and nothing to elect. Most of a cel is one colour, which is why this is
// here at all.
fn resample_flat(source: u32, centre: vec2<i32>, reach: vec2<i32>, word: ptr<function, u32>) -> bool {
  let first = resample_texel(source, centre.x - reach.x, centre.y - reach.y);
  for (var dy = -reach.y; dy <= reach.y; dy = dy + 1) {
    for (var dx = -reach.x; dx <= reach.x; dx = dx + 1) {
      if (resample_texel(source, centre.x + dx, centre.y + dy) != first) {
        return false;
      }
    }
  }
  *word = first;
  return true;
}

// s · 2^shift − position, both Q.16 measured from the same origin: the
// true difference is small, so the wrapping u32 arithmetic lands on it.
fn resample_offset(s: i32, shift: u32, position: i32, twice: bool) -> i32 {
  let scaled = bitcast<u32>(position) << select(0u, 1u, twice);
  return bitcast<i32>((bitcast<u32>(s) << shift) - scaled);
}

// Blend: the tent mean. Every tap within the radius weighs
// rnd(max(0, R − |s · 2^16 − u|), 8) per axis — the spec's 1 − d/R scaled
// by R, which is every tap's alike and cancels.
//
// Colour is averaged weighted by alpha as well: a transparent tap has no
// colour to contribute, and letting its zeroes into the mean is what
// fringes a soft edge with black. A tent rather than a cubic, as the app's
// ResampleMode.blend says: a cubic's negative lobe haloes every inked edge.
//
// The spec answers a reach of one word with that word. Where its taps hold
// alpha, the tent mean already is that word — divr(A·W, W) = A and
// divr(C·A·W, A·W) = C — so the taps are walked once, and the reach again
// only where they hold no alpha, which they cannot tell from 0: where a
// tap read a word with colour, or none weighed anything. Probing first
// read a reach twice wherever it failed late: forty turned cels of sparse
// lines over clear took 16.9 ms so, 4.5 walked once, and 6.1 probing every
// clear reach (a 2048² canvas, RTX 4080, 2026-11-05).
fn resample_blend(map: ResampleMap, source: u32, point: ResamplePoint) -> u32 {
  let radius = min(max(point.extent, vec2<u32>(map.floor)), vec2<u32>(RESAMPLE_CEILING));
  let reach = vec2<i32>((radius + vec2<u32>(0xffffu)) >> vec2<u32>(16u));
  let centre = vec2<i32>(resample_round16(point.u), resample_round16(point.v));
  var red = Wide(0u, 0u);
  var green = Wide(0u, 0u);
  var blue = Wide(0u, 0u);
  var alpha = Wide(0u, 0u);
  var weight = Wide(0u, 0u);
  // Every word a tap read, or-ed together.
  var seen = 0u;
  for (var dy = -reach.y; dy <= reach.y; dy = dy + 1) {
    let sy = centre.y + dy;
    let near_y = i32(radius.y) - abs(resample_offset(sy, 16u, point.v, false));
    let wy = u32(max(near_y, 0) + 128) >> 8u;
    if (wy == 0u) {
      continue;
    }
    for (var dx = -reach.x; dx <= reach.x; dx = dx + 1) {
      let sx = centre.x + dx;
      let near_x = i32(radius.x) - abs(resample_offset(sx, 16u, point.u, false));
      let wx = u32(max(near_x, 0) + 128) >> 8u;
      if (wx == 0u) {
        continue;
      }
      let w = wx * wy;
      let texel = resample_texel(source, sx, sy);
      seen = seen | texel;
      let held = (texel >> 24u) * w;
      red = wide_add(red, wide_mul_u32(texel & 0xffu, held));
      green = wide_add(green, wide_mul_u32((texel >> 8u) & 0xffu, held));
      blue = wide_add(blue, wide_mul_u32((texel >> 16u) & 0xffu, held));
      alpha = wide_add(alpha, Wide(held, 0u));
      weight = wide_add(weight, Wide(w, 0u));
    }
  }
  // No weight is no alpha too.
  if (all(alpha == Wide(0u, 0u))) {
    var word = 0u;
    let unweighed = all(weight == Wide(0u, 0u));
    if ((seen != 0u || unweighed) && resample_flat(source, centre, reach, &word)) {
      return word;
    }
    return 0u;
  }
  let a = wide_divr(alpha, weight, 8u);
  if (a == 0u) {
    return 0u;
  }
  let r = wide_divr(red, alpha, 8u);
  let g = wide_divr(green, alpha, 8u);
  let b = wide_divr(blue, alpha, 8u);
  return (a << 24u) | (b << 16u) | (g << 8u) | r;
}

// Pick's vote table, the invocation's own. At module scope rather than a
// struct handed down by pointer, for the speed: subsampled Pick ran
// 7.4 ms with the struct where this runs 5.0, exact Pick and Blend the
// same (a 1.3x turn over a megapixel of noise; DXC, RTX 4080,
// 2026-11-05). FXC, which first forced this, is gone
// (gpu-engine-feasibility-Q4).
var<private> resample_keys: array<u32, 16>;
var<private> resample_weights: array<Wide, 16>;
var<private> resample_slots: u32;
var<private> resample_evicted: bool;

// A token seen before adds its weight; a new one takes a free slot; with
// none free the lightest slot (lowest index on a tie) gives up its key and
// keeps its weight, and the table is marked for a recount. A recount adds
// only to the keys that survived.
//
// An inherited count over-estimates its new owner, which could hand the
// election to a token that merely arrived late; so once the surviving keys
// are known they are counted again exactly — only after an eviction, so
// the ordinary preimage (line art holds two or three colours) never pays.
// ⚠️The recount is DEFENSIVE and no test pins it: a search over a thousand
// fixtures found none where an inherited count beats the true argmax, so
// no test fails if it goes. Said out loud rather than left to look like
// coverage: the eviction ITSELF is pinned ("a dominant colour still wins
// past 16 distinct tokens"), the correction on top of it is not.
fn resample_vote(token: u32, weight: Wide, recount: bool) {
  var slot = RESAMPLE_SLOTS;
  for (var s = 0u; s < resample_slots; s = s + 1u) {
    if (slot == RESAMPLE_SLOTS && resample_keys[s] == token) {
      slot = s;
    }
  }
  if (slot == RESAMPLE_SLOTS) {
    if (recount) {
      return;
    }
    if (resample_slots < RESAMPLE_SLOTS) {
      slot = resample_slots;
      resample_slots = resample_slots + 1u;
      resample_weights[slot] = Wide(0u, 0u);
    } else {
      slot = 0u;
      for (var s = 1u; s < RESAMPLE_SLOTS; s = s + 1u) {
        if (wide_below(resample_weights[s], resample_weights[slot])) {
          slot = s;
        }
      }
      resample_evicted = true;
    }
    resample_keys[slot] = token;
  }
  resample_weights[slot] = wide_add(resample_weights[slot], weight);
}

fn resample_clear() {
  for (var s = 0u; s < resample_slots; s = s + 1u) {
    resample_weights[s] = Wide(0u, 0u);
  }
}

// The heaviest slot; the first met on a tie.
//
// The first met, in a fixed scan order, is what keeps the answer identical
// on every device and every split of the output. On the exact path a tie
// is REAL — the areas are equal and nothing further will separate them.
// ⚠️The visible cost, written down because it looks like a defect and is
// not one: at EXACTLY half scale a one-pixel line covers exactly one of
// the two source pixels its preimage spans, every pixel along an
// axis-aligned line ties at once, and the whole line goes to the ground.
// Measured: 1 ink pixel kept where a supersampled oracle keeps 32 — the
// oracle differing only because its own tie-break is a map's insertion
// order. Both answers ARE the area argmax; neither is more correct.
//
// Two tie-breaks were built and measured and both were reverted, so do not
// reach for a third without a sweep. Deciding by the pixel's own centre
// fixes 0.500 and destroys 0.750 — 95 ink pixels down to 3 — because at
// 0.750 the tie is between a feature and a ground the centre happens to
// sit in. The same rule on the supersampled path traded 0.55 for 0.70 in
// exactly the same shape. The tie is genuinely undecidable from area, and
// every rule that decides it anyway wins one scale by losing another.
fn resample_best() -> u32 {
  var best = 0u;
  for (var s = 1u; s < resample_slots; s = s + 1u) {
    if (wide_below(resample_weights[best], resample_weights[s])) {
      best = s;
    }
  }
  return best;
}

// The length one source pixel shares with the preimage along one axis, in
// doubled coordinates (Q.17): min(s·2^17 + 2^16, 2u + extent) −
// max(s·2^17 − 2^16, 2u − extent), with 2u taken off all four.
fn resample_cover(s: i32, position: i32, extent: u32) -> i32 {
  let t = resample_offset(s, 17u, position, true);
  return min(t + 65536, i32(extent)) - max(t - 65536, -i32(extent));
}

// Pick where the preimage is an axis-aligned rectangle: each tap weighs
// the area it shares with it, so nothing is quantised and a tie is real.
//
// ⚠️READ THIS BEFORE CONCLUDING THE FOOTPRINT BOX IS BACK. It is not. A
// destination pixel's preimage is a parallelogram, and the reason three
// rounds of separable weighting failed is that a product of two
// one-dimensional weights integrates over a RECTANGLE. But the preimage
// sometimes IS a rectangle — sides parallel to the axes, by construction
// rather than by approximation — and then the separable product
// (resample_cover × resample_cover) is not an estimate of the area, it is
// the area.
//
// Exactly when: the two destination steps are `(a, d)` and `(b, e)`, so
// they land on the axes either when `b` and `d` are both zero (no
// rotation, or a half turn) or when `a` and `e` are both zero (a quarter
// turn, which swaps the axes and is just as rectangular). The quarter turn
// is not an afterthought — it is where the worst measured failures were,
// and it reaches this path exactly because the app's `SelectionAffine`
// carries cos and sin from a table, so 90° really does give `a == 0`
// rather than 6.1e-17. Every failure this exactness fixes lives at 0°, 90°
// and 180°; every failure the supersampler fixes lives everywhere else.
//
// Why it MATTERS rather than merely being cheaper: counting n samples
// quantises coverage to multiples of 1/n, so a feature owning `scale` of
// its preimage only wins when `n·scale` rounds strictly past n/2. That
// leaves an ambiguity band of `(0.5, 0.5 + 1/(2n))` where the vote comes
// back exactly tied, and a tie goes to the token met first, which under
// reduction is systematically the ground. An axis-aligned 1px line
// presents the SAME coverage at every pixel along its length, so the whole
// line flips together: measured on the supersampler alone, a 90° reduction
// to 0.525 kept 5 ink pixels where the truth keeps 38. The line did not
// thin. It vanished. Raising the refinement cap narrows the band and never
// closes it. Computing the area instead of sampling it closes it: here
// 0.525 simply beats 0.475.
//
// The preimage spans `u ± extent/2` with NO FLOOR applied: a floor above
// the true extent claims the preimage reaches further than it does, which
// is what deleted line art when the floor was 1.5. The bound — extents at
// most the ceiling (RESAMPLE_CEILING), so the tap window stays bounded:
// past a 16× reduction a one-pixel feature has long lost its own area
// argmax and the supersampler's cap is the honest answer.
fn resample_pick_exact(source: u32, point: ResamplePoint) -> u32 {
  // ⌈ext / 2^17⌉: a covered pixel is never further from the centre one.
  // The spec's ⌈(ext + 2^16) / 2^17⌉ looks one ring more for no value —
  // canvas base let it go for the speed (gpu-int-spec-canvas 16:48).
  let reach = vec2<i32>((point.extent + vec2<u32>(0x1ffffu)) >> vec2<u32>(17u));
  let centre = vec2<i32>(resample_round16(point.u), resample_round16(point.v));
  var word = 0u;
  if (resample_flat(source, centre, reach, &word)) {
    return word;
  }
  resample_slots = 0u;
  resample_evicted = false;
  for (var round = 0; round < 2; round = round + 1) {
    for (var dy = -reach.y; dy <= reach.y; dy = dy + 1) {
      let sy = centre.y + dy;
      let cover_y = resample_cover(sy, point.v, point.extent.y);
      if (cover_y <= 0) {
        continue;
      }
      for (var dx = -reach.x; dx <= reach.x; dx = dx + 1) {
        let sx = centre.x + dx;
        let cover_x = resample_cover(sx, point.u, point.extent.x);
        if (cover_x <= 0) {
          continue;
        }
        let weight = wide_mul_u32(u32(cover_x), u32(cover_y));
        resample_vote(resample_texel(source, sx, sy), weight, round == 1);
      }
    }
    if (!resample_evicted || round == 1) {
      break;
    }
    resample_clear();
  }
  if (resample_slots == 0u) {
    return 0u;
  }
  return resample_keys[resample_best()];
}

// Subsamples per axis from the squared step: the least n of 8..15 with
// step² <= (n/2)² · 2^32 = n² · 2^30, else 16.
//
// The step is one destination pixel's along one axis — `(a, d)` along x,
// `(b, e)` along y — and its length is what decides how densely that axis
// is cut: two samples per source pixel. Taking the rate from the
// preimage's AREA instead looks equivalent and is not: a map that shrinks
// 5:1 along one axis while magnifying 2× along the other has an area of
// 2.5 and needs ten samples across, and reading the area gave it four — it
// dropped a whole column of an opaque image. Anisotropy is the case this
// whole feature kept failing on, so the rate is measured per axis or not
// at all.
//
// **8** is the floor as MARGIN above the two-per-source-pixel rate the
// rule gives near 1:1 — not as a rescue, which is what an earlier version
// of this comment claimed on a measurement that does not reproduce. Rate
// 4 collapses on a hairline only with the refinement (RESAMPLE_REFINE)
// disabled; with refinement in place the two are close, and over the
// sweep in `resample_kernel_test.dart` rate 4 keeps 91.7% of the oracle's
// ink at worst against 8's 95.8%, at the same worst disagreement. **8 buys
// the margin. The refinement loop buys the drawing.**
//
// **16** is the ceiling because nothing above it moved on the rotated
// work the sampler is responsible for: 24 and 32 per axis returned the
// same pixels for four and sixteen times the samples. It is also what
// bounds Pick's work without a radius clamp: a corner-pin that used to ask
// for 2.5×10⁸ taps in a single destination pixel asks for 256 samples like
// every other pixel, and aliases past that exactly as a mip-less sampler
// does.
fn resample_samples(along: u32, across: u32) -> u32 {
  let step = wide_add(wide_mul_u32(along, along), wide_mul_u32(across, across));
  for (var n = 8u; n < 16u; n = n + 1u) {
    if (!wide_below(wide_shl(Wide(n * n, 0u), 30u), step)) {
      return n;
    }
  }
  return 16u;
}

// Subsample s of n, from the pixel centre: divr((2s+1)·2^15, n) − 2^15.
fn resample_subsample(s: u32, n: u32) -> i32 {
  return i32(((2u * s + 1u) * 65536u + n) / (2u * n)) - 32768;
}

// resample_subsample(s, n) for s = 0, 1, … in turn, with no division a
// subsample: each s adds 2^17 to the numerator, so the quotient grows by
// 2^17 / 2n and the remainder carries.
struct ResampleOffsets {
  quotient: u32,
  remainder: u32,
  step: u32,
  carry: u32,
  twice: u32,
}

fn resample_offsets(n: u32) -> ResampleOffsets {
  let twice = 2u * n;
  let first = 65536u + n;
  return ResampleOffsets(first / twice, first % twice, 131072u / twice, 131072u % twice, twice);
}

// The next subsample's offset from the pixel centre, Q.16.
fn resample_next_offset(offsets: ptr<function, ResampleOffsets>) -> i32 {
  let offset = i32((*offsets).quotient) - 32768;
  (*offsets).quotient += (*offsets).step;
  (*offsets).remainder += (*offsets).carry;
  if ((*offsets).remainder >= (*offsets).twice) {
    (*offsets).remainder -= (*offsets).twice;
    (*offsets).quotient += 1u;
  }
  return offset;
}

// The part of a subsample's move its row's offset `oy` gives, unrounded:
// b·oy and e·oy (Q.20), or a homography's du/dy·oy and dv/dy·oy (Q.16).
// Taken once a row, as the row's subsamples all share it.
fn resample_row_move(map: ResampleMap, point: ResamplePoint, oy: i32) -> array<Wide, 2> {
  if (resample_affine(map)) {
    return array<Wide, 2>(wide_mul_i32(map.b, oy), wide_mul_i32(map.e, oy));
  }
  return array<Wide, 2>(wide_mul(point.du_dy, wide(oy)), wide_mul(point.dv_dy, wide(oy)));
}

// Where one subsample lands, as a source pixel: the centre moved by the
// map's linear part — a homography's Jacobian at the pixel centre standing
// in for it — at offset `ox` in a row whose move is `row`. False where it
// lands outside.
fn resample_landing(
  map: ResampleMap,
  point: ResamplePoint,
  ox: i32,
  row: array<Wide, 2>,
  at: ptr<function, vec2<i32>>,
) -> bool {
  var du: Wide;
  var dv: Wide;
  if (resample_affine(map)) {
    du = wide_round(wide_add(wide_mul_i32(map.a, ox), row[0]), 20u);
    dv = wide_round(wide_add(wide_mul_i32(map.d, ox), row[1]), 20u);
  } else {
    du = wide_round(wide_add(wide_mul(point.du_dx, wide(ox)), row[0]), 16u);
    dv = wide_round(wide_add(wide_mul(point.dv_dx, wide(ox)), row[1]), 16u);
  }
  let su = wide_add(wide(point.u), du);
  let sv = wide_add(wide(point.v), dv);
  if (!resample_within(su) || !resample_within(sv)) {
    return false;
  }
  *at = vec2<i32>(resample_round16(bitcast<i32>(su.x)), resample_round16(bitcast<i32>(sv.x)));
  return true;
}

// |du/dx| or the like, capped at 16 px for the step length.
fn resample_step(a: Wide) -> u32 {
  let magnitude = wide_abs(a);
  return select(magnitude.x, RESAMPLE_CEILING, magnitude.y != 0u || magnitude.x > RESAMPLE_CEILING);
}

// Pick elsewhere: subsample, count, and while the count comes back tied
// sample again at twice the rate, up to the refine limit.
//
// A tie is nearly always the grid's fault rather than the geometry's. A
// one-pixel line at 0.55× covers 55% of its preimage and ought to win
// outright, but eight samples across a 1.818-wide preimage land four on
// the line and four off it, and whichever tie-break is applied then
// decides the pixel by something that is not area. Measured on a
// horizontal hairline that cost 51 of 71 ink pixels — and a hairline is
// not a corner case, it is the drawing. Refining answers the question
// instead of guessing at it: at 16 per axis the same 55% reads as 8.8 of
// 16 rather than 4.4 of 8, which rounds to 9 and wins. Only tied pixels
// pay, which on line art is a fraction of one edge (RESAMPLE_REFINE says
// why one doubling is all of it).
//
// The flat probe stands in for the sampling, so it must be a true bound: a
// subsample lands in `rnd(u_s)`, `u_s` stays within `extent/2` of `u`, and
// `u` within half a pixel of the centre pixel, so no landing is further
// than `extent/2 + 1` away, and the floor of that bounds whole-pixel
// landings. That needs the preimage to BE the parallelogram the extents
// describe — true of an affine map, only linearly so under a perspective
// divide — so a homography is not probed at all; and it runs only while it
// is cheaper than the sampling it would save. A window that disagrees with
// the thing it stands in for is how an earlier design elected a colour by
// a loop bound.
//
// A homography's steps are the Jacobian at THIS pixel: taken from the
// matrix entries instead, they would describe a pixel somewhere else in
// the image — a mistake made once already.
fn resample_pick_sampled(map: ResampleMap, source: u32, point: ResamplePoint) -> u32 {
  let affine = resample_affine(map);
  var along: vec4<u32>;
  if (affine) {
    // The affine Jacobian is the matrix, Q.20 to Q.16.
    along = vec4<u32>(
      resample_step(wide_round(wide(map.a), 4u)),
      resample_step(wide_round(wide(map.d), 4u)),
      resample_step(wide_round(wide(map.b), 4u)),
      resample_step(wide_round(wide(map.e), 4u)),
    );
  } else {
    along = vec4<u32>(
      resample_step(point.du_dx),
      resample_step(point.dv_dx),
      resample_step(point.du_dy),
      resample_step(point.dv_dy),
    );
  }
  var nx = resample_samples(along.x, along.y);
  var ny = resample_samples(along.z, along.w);
  var word = 0u;
  if (affine) {
    let span = vec2<i32>((point.extent + vec2<u32>(0x20000u)) >> vec2<u32>(17u));
    // A side past 257 cells is past the 256 subsamples on its own, so
    // capping it there keeps the product from wrapping into a probe of
    // billions of cells without changing a comparison.
    let side = 2u * min(vec2<u32>(span), vec2<u32>(128u)) + 1u;
    if (side.x * side.y <= nx * ny
        && resample_flat(source, vec2<i32>(resample_round16(point.u), resample_round16(point.v)), span, &word)) {
      return word;
    }
  }
  // The source pixel read last and its word: neighbouring subsamples land
  // on few pixels, and a read is the host's whole walk to its tile.
  var read_at = vec2<i32>(0, 0);
  var read_word = 0u;
  var read_any = false;
  loop {
    resample_slots = 0u;
    resample_evicted = false;
    for (var round = 0; round < 2; round = round + 1) {
      // A run of subsamples on one word votes once, by its count: the vote
      // adds, and a token met again finds its own slot, so the table is
      // the one they fill one by one.
      var run_token = 0u;
      var run_count = 0u;
      let first = resample_offsets(nx);
      for (var sy = 0u; sy < ny; sy = sy + 1u) {
        let row = resample_row_move(map, point, resample_subsample(sy, ny));
        var offsets = first;
        for (var sx = 0u; sx < nx; sx = sx + 1u) {
          var at: vec2<i32>;
          var token = 0u;
          let ox = resample_next_offset(&offsets);
          if (resample_landing(map, point, ox, row, &at)) {
            if (!read_any || any(at != read_at)) {
              read_word = resample_texel(source, at.x, at.y);
              read_at = at;
              read_any = true;
            }
            token = read_word;
          }
          // An empty run holds token 0 with no count, so it takes the first
          // subsample either way.
          if (token == run_token) {
            run_count = run_count + 1u;
          } else {
            if (run_count != 0u) {
              resample_vote(run_token, Wide(run_count, 0u), round == 1);
            }
            run_token = token;
            run_count = 1u;
          }
        }
      }
      resample_vote(run_token, Wide(run_count, 0u), round == 1);
      if (!resample_evicted || round == 1) {
        break;
      }
      resample_clear();
    }
    let best = resample_best();
    var tied = false;
    for (var s = 0u; s < resample_slots; s = s + 1u) {
      if (s != best && all(resample_weights[s] == resample_weights[best])) {
        tied = true;
      }
    }
    if (!tied || (nx >= RESAMPLE_REFINE && ny >= RESAMPLE_REFINE)) {
      word = resample_keys[best];
      break;
    }
    nx = min(nx * 2u, RESAMPLE_REFINE);
    ny = min(ny * 2u, RESAMPLE_REFINE);
  }
  return word;
}

// Destination pixel (x, y) — absolute, a clip already added — as a
// straight RGBA8 word.
fn resample(map: ResampleMap, source: u32, x: i32, y: i32) -> u32 {
  if (map.mode == RESAMPLE_COPY) {
    let sx = wide_add(wide(x), wide_shr(map.c, 20u));
    let sy = wide_add(wide(y), wide_shr(map.f, 20u));
    if (!wide_fits(sx) || !wide_fits(sy)) {
      return 0u;
    }
    return resample_texel(source, bitcast<i32>(sx.x), bitcast<i32>(sy.x));
  }
  // No other map reaches a pass compiled for the copy alone. This and the
  // mode guards below change no byte — a pass meets only maps of the modes
  // it was compiled for — but time: they let the compiler drop a mode's
  // code, and this one locate's too (a 1080p composite of no row, 11-06:
  // 110 µs of GPU compiled for the copy alone, 321 for every mode). No
  // test here can see them; GPU timestamps can.
  if (!resample_with_locate()) {
    return 0u;
  }
  var point: ResamplePoint;
  if (!resample_locate(map, x, y, &point)) {
    return 0u;
  }
  if (resample_with_blend && map.mode == RESAMPLE_BLEND) {
    return resample_blend(map, source, point);
  }
  // Nearest: the word under the spec's point p, floor(p) a side. u is p
  // less a half, so floor(p) is rnd(u, 16) — a centre on a border reads
  // the pixel right of it and under it.
  if (resample_with_nearest && map.mode == RESAMPLE_NEAREST) {
    return resample_texel(source, resample_round16(point.u), resample_round16(point.v));
  }
  if (!resample_with_pick) {
    return 0u;
  }
  let axis_aligned = (map.b == 0 && map.d == 0) || (map.a == 0 && map.e == 0);
  if (resample_affine(map) && axis_aligned
      && point.extent.x > 0u && point.extent.y > 0u
      && point.extent.x <= RESAMPLE_CEILING && point.extent.y <= RESAMPLE_CEILING) {
    return resample_pick_exact(source, point);
  }
  return resample_pick_sampled(map, source, point);
}
