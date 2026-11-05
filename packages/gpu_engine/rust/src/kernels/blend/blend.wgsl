// The blend family's integer arithmetic (gpu-canonical-store ⑥): what a
// dab piles, what a stamp lands, how a stroke and a row composite. Every
// kernel that blends prepends this file (`BLEND_WGSL`) — one formula, so a
// stroke shown and the same stroke landed cannot differ.
//
// Integer ops only, and every intermediate inside u32: WGSL core has no
// 64-bit integer, and DX12 runs it through FXC, which has none either
// (gpu-engine-feasibility ③). Floats may be fused or reassociated per
// backend (gpu-engine-skeleton), so none is used.
//
// A channel and an alpha are on the 16-bit scale, 0..=65535 meaning 0..=1:
// a byte c is c·257. Colour is straight, never premultiplied (1a ①).
//
// Needs shared/isqrt.wgsl before it.

const W_ONE: u32 = 65535u;
// A channel at or under this is "at most half" — the formulas' cs <= 0.5.
// For a channel a byte gave, c·257 <= 32767 is exactly c <= 127.
const W_HALF: u32 = 32767u;

// Mode ids: the C engine's stroke table (qa_engine.c, QA_STROKE_BLEND_*),
// the one the app's layer blend maps onto (brush_stroke_blend.dart), and
// normal beside it — srcOver had no id there because it never reached
// the table.
const BLEND_BEHIND: u32 = 0u;
const BLEND_ADD: u32 = 1u;
const BLEND_DARKEN: u32 = 2u;
const BLEND_MULTIPLY: u32 = 3u;
const BLEND_COLOR_BURN: u32 = 4u;
const BLEND_LIGHTEN: u32 = 5u;
const BLEND_SCREEN: u32 = 6u;
const BLEND_COLOR_DODGE: u32 = 7u;
const BLEND_OVERLAY: u32 = 8u;
const BLEND_SOFT_LIGHT: u32 = 9u;
const BLEND_HARD_LIGHT: u32 = 10u;
const BLEND_DIFFERENCE: u32 = 11u;
const BLEND_EXCLUSION: u32 = 12u;
const BLEND_LINEAR_BURN: u32 = 13u;
const BLEND_SUBTRACT: u32 = 14u;
const BLEND_VIVID_LIGHT: u32 = 15u;
const BLEND_LINEAR_LIGHT: u32 = 16u;
const BLEND_PIN_LIGHT: u32 = 17u;
const BLEND_HARD_MIX: u32 = 18u;
const BLEND_DIVIDE: u32 = 19u;
const BLEND_DARKER_COLOR: u32 = 20u;
const BLEND_LIGHTER_COLOR: u32 = 21u;
const BLEND_HUE: u32 = 22u;
const BLEND_SATURATION: u32 = 23u;
const BLEND_CHROMA: u32 = 24u;
const BLEND_LUMINOSITY: u32 = 25u;
const BLEND_GLOW_DODGE: u32 = 26u;
const BLEND_GLOW_ADD: u32 = 27u;
const BLEND_NORMAL: u32 = 28u;

// round(a·b / 65535), for a, b <= 65535. With t = a·b + 32768,
// (t + (t >> 16)) >> 16 is that rounding exactly; t + (t >> 16) is at most
// 4,294,934,527 (11-05: every a against fifteen b and three million random
// pairs, none off).
fn blend_mul(a: u32, b: u32) -> u32 {
  let t = a * b + 32768u;
  return (t + (t >> 16u)) >> 16u;
}

// round(n·65535 / d) — the ratio n/d as a channel — for n <= d, d > 0.
// n·65535 + d/2 is at most 4,294,868,992.
fn blend_div(n: u32, d: u32) -> u32 {
  return (n * W_ONE + d / 2u) / d;
}

// A channel's byte: round(w / 257). No w is a tie, so a byte widened comes
// back as itself.
fn blend_to8(w: u32) -> u32 {
  return (w + 128u) / 257u;
}

// round(√(x/65535)) as a channel, x <= 65535: round(√(x·65535)), and
// x·65535 <= 65535² stays in u32.
fn blend_sqrt(x: u32) -> u32 {
  return isqrt_round(x * W_ONE);
}

fn blend_burn(cs: u32, cd: u32) -> u32 {
  if (cd >= W_ONE) {
    return W_ONE;
  }
  if (cs == 0u) {
    return 0u;
  }
  let lack = W_ONE - cd;
  if (lack >= cs) {
    return 0u;
  }
  return W_ONE - blend_div(lack, cs);
}

fn blend_dodge(cs: u32, cd: u32) -> u32 {
  if (cd == 0u) {
    return 0u;
  }
  if (cs >= W_ONE) {
    return W_ONE;
  }
  let room = W_ONE - cs;
  if (cd >= room) {
    return W_ONE;
  }
  return blend_div(cd, room);
}

fn blend_hard_light(cs: u32, cd: u32) -> u32 {
  if (cs <= W_HALF) {
    return blend_mul(2u * cs, cd);
  }
  let raised = 2u * cs - W_ONE;
  return raised + cd - blend_mul(raised, cd);
}

fn blend_soft_light(cs: u32, cd: u32) -> u32 {
  if (cs <= W_HALF) {
    return cd - blend_mul(blend_mul(W_ONE - 2u * cs, cd), W_ONE - cd);
  }
  // ((16x - 12)x + 4)x as 16x³ - 12x² + 4x, each power one blend_mul: the
  // nested form's first product overflows u32. Never under cd (11-05, every
  // cd checked in both branches), so d - cd needs no sign.
  var d: u32;
  if (cd <= 16383u) {
    let square = blend_mul(cd, cd);
    let cube = blend_mul(square, cd);
    d = 16u * cube + 4u * cd - 12u * square;
  } else {
    d = blend_sqrt(cd);
  }
  return cd + blend_mul(2u * cs - W_ONE, d - cd);
}

// B(cs, cd) of the separable modes (qa_stroke_blend_channel's table). A
// glow reads its source already times its alpha (blend_composite).
fn blend_channel(mode: u32, cs: u32, cd: u32) -> u32 {
  switch (mode) {
    case BLEND_DARKEN: {
      return min(cs, cd);
    }
    case BLEND_MULTIPLY: {
      return blend_mul(cs, cd);
    }
    case BLEND_COLOR_BURN: {
      return blend_burn(cs, cd);
    }
    case BLEND_LIGHTEN: {
      return max(cs, cd);
    }
    case BLEND_SCREEN: {
      return cs + cd - blend_mul(cs, cd);
    }
    case BLEND_ADD, BLEND_GLOW_ADD: {
      return min(cs + cd, W_ONE);
    }
    case BLEND_COLOR_DODGE, BLEND_GLOW_DODGE: {
      return blend_dodge(cs, cd);
    }
    case BLEND_OVERLAY: {
      return blend_hard_light(cd, cs);
    }
    case BLEND_SOFT_LIGHT: {
      return blend_soft_light(cs, cd);
    }
    case BLEND_HARD_LIGHT: {
      return blend_hard_light(cs, cd);
    }
    case BLEND_DIFFERENCE: {
      return max(cs, cd) - min(cs, cd);
    }
    case BLEND_LINEAR_BURN: {
      return select(0u, cs + cd - W_ONE, cs + cd > W_ONE);
    }
    case BLEND_SUBTRACT: {
      return select(0u, cd - cs, cd > cs);
    }
    case BLEND_VIVID_LIGHT: {
      if (cs <= W_HALF) {
        return blend_burn(2u * cs, cd);
      }
      return blend_dodge(2u * cs - W_ONE, cd);
    }
    case BLEND_LINEAR_LIGHT: {
      let sum = i32(cd) + 2 * i32(cs) - i32(W_ONE);
      return u32(clamp(sum, 0, i32(W_ONE)));
    }
    case BLEND_PIN_LIGHT: {
      if (cs <= W_HALF) {
        return min(cd, 2u * cs);
      }
      return max(cd, 2u * cs - W_ONE);
    }
    case BLEND_HARD_MIX: {
      // A byte pair summing to 255 widens to exactly 65535.
      return select(0u, W_ONE, cs + cd >= W_ONE);
    }
    case BLEND_DIVIDE: {
      if (cd == 0u) {
        return 0u;
      }
      if (cs == 0u || cd >= cs) {
        return W_ONE;
      }
      return blend_div(cd, cs);
    }
    case BLEND_NORMAL: {
      return cs;
    }
    default: {
      // BLEND_EXCLUSION. blend_mul(a, b) <= min(a, b), so this is >= 0.
      return cs + cd - 2u * blend_mul(cs, cd);
    }
  }
}

// ---- The six that mix the three channels ----
// W3C Compositing Level 1's Lum, ClipColor, SetLum, Sat, SetSat, and
// Photoshop's darker / lighter colour (qa_stroke_blend_triple).

// Lum with the weights 0.3 / 0.59 / 0.11 as 19661 / 38666 / 7209 — they sum
// to 65536, so Lum(c + d) is Lum(c) + d for any whole d, exactly.
fn blend_lum(c: vec3<u32>) -> u32 {
  return (19661u * c.x + 38666u * c.y + 7209u * c.z + 32768u) >> 16u;
}

fn blend_sat(c: vec3<u32>) -> u32 {
  return max(max(c.x, c.y), c.z) - min(min(c.x, c.y), c.z);
}

// Every channel (c - min)·s / (max - min), the way Skia writes SetSat: no
// ranking of the three, ties included.
fn blend_set_sat(c: vec3<u32>, s: u32) -> vec3<u32> {
  let low = min(min(c.x, c.y), c.z);
  let spread = max(max(c.x, c.y), c.z) - low;
  if (spread == 0u) {
    return vec3<u32>(0u);
  }
  let half = spread / 2u;
  return vec3<u32>(
    ((c.x - low) * s + half) / spread,
    ((c.y - low) * s + half) / spread,
    ((c.z - low) * s + half) / spread,
  );
}

// ClipColor's move of one channel toward the luminosity l: l + (v - l)·k/n,
// on magnitudes. |v - l| and k are at most 65535, so the product and its
// rounding fit u32.
fn blend_clip_toward(v: i32, l: i32, k: u32, n: u32) -> i32 {
  let offset = v - l;
  let moved = i32((u32(abs(offset)) * k + n / 2u) / n);
  return l + select(moved, -moved, offset < 0);
}

// SetLum(c, l) with its ClipColor. The luminosity after the shift is l
// itself (blend_lum's weights sum to 65536), so it is not measured again
// on channels that may lie outside the scale.
fn blend_set_lum(c: vec3<u32>, l: u32) -> vec3<u32> {
  let shift = i32(l) - i32(blend_lum(c));
  var v = vec3<i32>(c) + vec3<i32>(shift);
  let lum = i32(l);
  let low = min(min(v.x, v.y), v.z);
  let high = max(max(v.x, v.y), v.z);
  if (low < 0 && lum - low != 0) {
    let n = u32(lum - low);
    v = vec3<i32>(
      blend_clip_toward(v.x, lum, l, n),
      blend_clip_toward(v.y, lum, l, n),
      blend_clip_toward(v.z, lum, l, n),
    );
  }
  if (high > i32(W_ONE) && high - lum != 0) {
    let n = u32(high - lum);
    let k = W_ONE - l;
    v = vec3<i32>(
      blend_clip_toward(v.x, lum, k, n),
      blend_clip_toward(v.y, lum, k, n),
      blend_clip_toward(v.z, lum, k, n),
    );
  }
  return vec3<u32>(clamp(v, vec3<i32>(0), vec3<i32>(i32(W_ONE))));
}

fn blend_triple(mode: u32, cs: vec3<u32>, cd: vec3<u32>) -> vec3<u32> {
  switch (mode) {
    case BLEND_DARKER_COLOR: {
      // A tie keeps what is there.
      return select(cd, cs, cs.x + cs.y + cs.z < cd.x + cd.y + cd.z);
    }
    case BLEND_LIGHTER_COLOR: {
      return select(cd, cs, cs.x + cs.y + cs.z > cd.x + cd.y + cd.z);
    }
    case BLEND_HUE: {
      return blend_set_lum(blend_set_sat(cs, blend_sat(cd)), blend_lum(cd));
    }
    case BLEND_SATURATION: {
      return blend_set_lum(blend_set_sat(cd, blend_sat(cs)), blend_lum(cd));
    }
    case BLEND_CHROMA: {
      return blend_set_lum(cs, blend_lum(cd));
    }
    default: {
      // BLEND_LUMINOSITY.
      return blend_set_lum(cd, blend_lum(cs));
    }
  }
}

fn blend_is_triple(mode: u32) -> bool {
  return mode >= BLEND_DARKER_COLOR && mode <= BLEND_LUMINOSITY;
}

fn blend_glows(mode: u32) -> bool {
  return mode == BLEND_GLOW_DODGE || mode == BLEND_GLOW_ADD;
}

// What a pixel that ends with no alpha holds: nothing, its colour too.
fn blend_settled(colour: vec3<u32>, alpha: u32) -> vec4<u32> {
  return select(vec4<u32>(colour, alpha), vec4<u32>(0u), alpha == 0u);
}

// One division over the alpha out, rounded once: the colour is the weights'
// sum over their total, and the weights sum to that total exactly — so
// three equal colours give that colour back, whatever the alphas.
fn blend_over_alpha(numerator: u32, alpha: u32) -> u32 {
  return min((numerator + alpha / 2u) / alpha, W_ONE);
}

// src over dst in `mode` — the W3C composite on straight alpha:
// (as(1-ad)·cs + ad(1-as)·cd + as·ad·B) / ao, ao = as + ad(1-as). The
// third weight is taken as as - as(1-ad), so the three sum to ao with no
// rounding between them: a dab over its own colour, or over nothing, lands
// its own colour exactly (ABI 40's rule, here by the formula and not by a
// shortcut beside it). Normal is the mode whose B is cs. src's alpha
// carries its opacity already.
fn blend_composite(mode: u32, src: vec4<u32>, dst: vec4<u32>) -> vec4<u32> {
  let a_s = src.w;
  let a_d = dst.w;
  if (mode == BLEND_BEHIND) {
    // dst over src: the destination's own weight is ad, the source's the
    // rest of the alpha out.
    let a_o = a_d + blend_mul(a_s, W_ONE - a_d);
    if (a_o == 0u) {
      return vec4<u32>(0u);
    }
    let rest = a_o - a_d;
    return vec4<u32>(
      blend_over_alpha(a_d * dst.x + rest * src.x, a_o),
      blend_over_alpha(a_d * dst.y + rest * src.y, a_o),
      blend_over_alpha(a_d * dst.z + rest * src.z, a_o),
      a_o,
    );
  }
  let under = blend_mul(a_d, W_ONE - a_s);
  let a_o = a_s + under;
  if (a_o == 0u) {
    return vec4<u32>(0u);
  }
  let own = blend_mul(a_s, W_ONE - a_d);
  let both = a_s - own;
  let cs = src.xyz;
  let cd = dst.xyz;
  var b: vec3<u32>;
  if (blend_is_triple(mode)) {
    b = blend_triple(mode, cs, cd);
  } else {
    // Clip Studio's 発光: B read with the source times its alpha, and not
    // mixed by the alpha after (SeparableBlendMode.glows).
    var read = cs;
    if (blend_glows(mode)) {
      read = vec3<u32>(blend_mul(cs.x, a_s), blend_mul(cs.y, a_s), blend_mul(cs.z, a_s));
    }
    b = vec3<u32>(
      blend_channel(mode, read.x, cd.x),
      blend_channel(mode, read.y, cd.y),
      blend_channel(mode, read.z, cd.z),
    );
  }
  if (blend_glows(mode)) {
    return vec4<u32>(
      blend_over_alpha(own * cs.x + a_d * b.x, a_o),
      blend_over_alpha(own * cs.y + a_d * b.y, a_o),
      blend_over_alpha(own * cs.z + a_d * b.z, a_o),
      a_o,
    );
  }
  return vec4<u32>(
    blend_over_alpha(own * cs.x + under * cd.x + both * b.x, a_o),
    blend_over_alpha(own * cs.y + under * cd.y + both * b.y, a_o),
    blend_over_alpha(own * cs.z + under * cd.z + both * b.z, a_o),
    a_o,
  );
}

// An eraser of alpha a_s on dst: the alpha falls by it, the colour stays —
// and a pixel left with no alpha holds no colour (blend_settled).
fn blend_erase(a_s: u32, dst: vec4<u32>) -> vec4<u32> {
  return blend_settled(dst.xyz, blend_mul(dst.w, W_ONE - a_s));
}

// src laid on dst by dst's alpha — `srcATop`, what a clipping group lays
// its clipped rows on its base with (I-92, drawClipAsImage): the alpha out
// is the base's, and the colour src at its alpha over the base's. The two
// weights are taken as under and ab - under, so they sum to ab exactly, as
// blend_composite's three sum to ao.
fn blend_atop(src: vec4<u32>, dst: vec4<u32>) -> vec4<u32> {
  let a_b = dst.w;
  if (a_b == 0u) {
    return vec4<u32>(0u);
  }
  let under = blend_mul(a_b, W_ONE - src.w);
  let both = a_b - under;
  return vec4<u32>(
    blend_over_alpha(both * src.x + under * dst.x, a_b),
    blend_over_alpha(both * src.y + under * dst.y, a_b),
    blend_over_alpha(both * src.z + under * dst.z, a_b),
    a_b,
  );
}

// A stored pixel — straight RGBA8, red in the low byte (1a ①) — on the
// 16-bit scale.
fn blend_unpack8(texel: u32) -> vec4<u32> {
  return vec4<u32>(
    texel & 0xffu,
    (texel >> 8u) & 0xffu,
    (texel >> 16u) & 0xffu,
    texel >> 24u,
  ) * 257u;
}

// A pixel on the 16-bit scale as it is stored, each channel rounded once
// (blend_to8); one whose alpha rounds to no byte holds no colour either
// (blend_settled), so a stored pixel never keeps a colour no one sees.
fn blend_pack8(pixel: vec4<u32>) -> u32 {
  let a = blend_to8(pixel.w);
  if (a == 0u) {
    return 0u;
  }
  return blend_to8(pixel.x) | (blend_to8(pixel.y) << 8u) | (blend_to8(pixel.z) << 16u)
    | (a << 24u);
}
