// R1, the integer resample: one destination pixel from the source through
// the destination-to-source map, every value an integer with its bits and
// its rounding fixed by the spec (gpu-int-spec-canvas 1b (1/4) R1). The
// executor's rows and the canvas's selection transforms call this one
// function (관제 14:51). The spec is the source: where this file and that
// card part, ask the card's owner, canvas base.
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
// A whole-pixel translation in either mode, copied word for word — decided
// once on the CPU (resample.rs), where the plan reading the map needs it too.
const RESAMPLE_COPY: u32 = 2u;

// 1 in Q.20, the matrix's scale.
const RESAMPLE_ONE: i32 = 1048576;
// Blend's radius ceiling and exact Pick's widest preimage: 16 px, Q.16.
const RESAMPLE_CEILING: u32 = 1048576u;
// A homography's w at or below 2^-12 (Q.37) is outside.
const RESAMPLE_W_FLOOR: u32 = 33554432u;
const RESAMPLE_SLOTS: u32 = 16u;
// How far a tied Pick vote refines, per axis.
const RESAMPLE_REFINE: u32 = 16u;

// The map as the CPU quantised it once: x' = a·x + b·y + c and the rest,
// a homography divided through by its largest w at the output's corners.
struct ResampleMap {
  // Q.20
  a: i32,
  b: i32,
  d: i32,
  e: i32,
  // Q.36
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
}

// The map from the 15 words resample.rs's ResampleMap::words lays down, in
// the order a host keeps them — the one place that order is read.
fn resample_map(w: array<u32, 15>) -> ResampleMap {
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

// One Jacobian entry: rnd((m − rnd(projected · n, 32)) · r, 41), Q.16.
fn resample_derivative(m: i32, projected: Wide, n: i32, r: Wide) -> Wide {
  let slope = wide_sub(wide(m), wide_round(wide_mul(projected, wide(n)), 32u));
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
  let w = wide_add(wide_add(wide_mul_i32(map.g, xx), wide_mul_i32(map.h, yy)), wide_shl(map.i, 1u));
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
  (*point).du_dx = resample_derivative(map.a, pu.xy, map.g, r);
  (*point).du_dy = resample_derivative(map.b, pu.xy, map.h, r);
  (*point).dv_dx = resample_derivative(map.d, pv.xy, map.g, r);
  (*point).dv_dy = resample_derivative(map.e, pv.xy, map.h, r);
  (*point).extent = vec2<u32>(
    resample_capped(wide_add(wide_abs((*point).du_dx), wide_abs((*point).du_dy))),
    resample_capped(wide_add(wide_abs((*point).dv_dx), wide_abs((*point).dv_dy))),
  );
  return true;
}

// Whether every source pixel within (reach.x, reach.y) of the centre holds
// one word — then both modes answer that word.
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
  var point: ResamplePoint;
  if (!resample_locate(map, x, y, &point)) {
    return 0u;
  }
  if (map.mode == RESAMPLE_BLEND) {
    return resample_blend(map, source, point);
  }
  let axis_aligned = (map.b == 0 && map.d == 0) || (map.a == 0 && map.e == 0);
  if (resample_affine(map) && axis_aligned
      && point.extent.x > 0u && point.extent.y > 0u
      && point.extent.x <= RESAMPLE_CEILING && point.extent.y <= RESAMPLE_CEILING) {
    return resample_pick_exact(source, point);
  }
  return resample_pick_sampled(map, source, point);
}
