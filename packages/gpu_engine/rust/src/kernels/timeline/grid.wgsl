// A frame grid's tile (gpu-int-spec-timeline ①): the op stream the grids
// write (timeline_grid_tile_ops.dart) drawn one thread a pixel, each
// walking the ops in order and laying every one that reaches its pixel
// by the byte-rounded integer source-over the grids have always used.
// Laid in the shader, never by the hardware's blending, which a device
// may round its own way.
//
// Integers only, as fill.wgsl has why. A rounded rect's field is taken in
// q9 — a pixel is 512 — so a q8 box's half is a whole word and a pixel's
// centre is too; its one square root is isqrt_round.
//
// Needs shared/isqrt.wgsl before it.

struct Params {
  width: u32,
  height: u32,
  // The tile's bytes before any op, as an RGBA word: r | g<<8 | b<<16 |
  // a<<24.
  background: u32,
  words: u32,
  atlas_width: u32,
  atlas_height: u32,
  pad0: u32,
  pad1: u32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read> ops: array<i32>;
@group(0) @binding(2) var atlas: texture_2d<u32>;
@group(0) @binding(3) var tile: texture_storage_2d<__FORMAT__, write>;

const OP_FILL_RECT: i32 = 1;
const OP_HLINE: i32 = 2;
const OP_VLINE: i32 = 3;
const OP_GLYPH: i32 = 4;
const OP_RRECT_FILL: i32 = 5;
const OP_RRECT_RING: i32 = 6;

// A pixel's whole width in q9, and half of it.
const ONE: i32 = 512;
const HALF: i32 = 256;

// An op's straight colour at alpha `a` over `under`, premultiplied bytes:
// opaque replaces outright, and a byte is rounded half up from the sum.
fn over(under: vec4<u32>, rgba: u32, a: u32) -> vec4<u32> {
  let rgb = vec3<u32>(rgba & 0xffu, (rgba >> 8u) & 0xffu, (rgba >> 16u) & 0xffu);
  if (a >= 255u) {
    return vec4<u32>(rgb, 255u);
  }
  let inv = 255u - a;
  let mixed = (rgb * a + under.rgb * inv + vec3<u32>(127u)) / 255u;
  return vec4<u32>(mixed, 255u - ((255u - under.a) * inv + 127u) / 255u);
}

// Whether `p` lies in the box from (x, y), `w` across and `h` down.
fn inside(p: vec2<i32>, x: i32, y: i32, w: i32, h: i32) -> bool {
  return p.x >= x && p.y >= y && p.x < x + w && p.y < y + h;
}

// A rounded box in q9: its centre, its halves, and each corner's radius
// (0 = square) — top left, top right, bottom left, bottom right.
struct Field {
  centre: vec2<i32>,
  half: vec2<i32>,
  radii: vec4<i32>,
}

// The box an RRECT op at `at` states, its corners as its mask picks them,
// each held to what the box can hold.
fn field_at(at: u32) -> Field {
  let x = ops[at + 1u];
  let y = ops[at + 2u];
  let w = ops[at + 3u];
  let h = ops[at + 4u];
  let radius = min(2 * ops[at + 5u], min(w, h));
  let mask = ops[at + 6u];
  let corner = vec4<bool>(
    (mask & 1) != 0,
    (mask & 2) != 0,
    (mask & 4) != 0,
    (mask & 8) != 0,
  );
  return Field(
    vec2<i32>(2 * x + w, 2 * y + h),
    vec2<i32>(w, h),
    select(vec4<i32>(0), vec4<i32>(radius), corner),
  );
}

// The box a ring of `outer` leaves unpainted: `line` in from each side it
// strokes and `line` + 2 pixels past each side `open` leaves open, its
// corners `line` tighter, never below square. Every edge is even in q9,
// so its halves are whole.
//
// No hold to what the hole can hold, though the C rasterizer has one: the
// outer corner is held to the outer box's shorter half and each half of
// the hole is that half less `line` or more, so a corner `line` tighter
// always fits.
fn hole_of(outer: Field, line: i32, open: i32) -> Field {
  let past = line + 2 * ONE;
  let low = outer.centre - outer.half + vec2<i32>(
    select(line, -past, (open & 1) != 0),
    select(line, -past, (open & 2) != 0),
  );
  let high = outer.centre + outer.half - vec2<i32>(
    select(line, -past, (open & 4) != 0),
    select(line, -past, (open & 8) != 0),
  );
  let half = (high - low) / 2;
  return Field(low + half, half, max(outer.radii - vec4<i32>(line), vec4<i32>(0)));
}

// How much of the pixel `p` `f` covers, in q9 (512 is all of it): half a
// pixel less the centre's signed distance to the box, held to [0, 512].
fn coverage(f: Field, p: vec2<i32>) -> i32 {
  let offset = p * ONE + vec2<i32>(HALF) - f.centre;
  var radius: i32;
  if (offset.x < 0) {
    radius = select(f.radii.z, f.radii.x, offset.y < 0);
  } else {
    radius = select(f.radii.w, f.radii.y, offset.y < 0);
  }
  let reach = abs(offset) - (f.half - vec2<i32>(radius));
  let past = max(reach, vec2<i32>(0));
  // Farther past either side than the radius and half a pixel, the
  // distance is more than half a pixel: nothing is covered. The cut also
  // keeps the sum of squares below 2^32, the radius being held to 2^15
  // (mod.rs refuses a larger one).
  if (past.x > radius + HALF || past.y > radius + HALF) {
    return 0;
  }
  let square = vec2<u32>(past) * vec2<u32>(past);
  let outside = i32(isqrt_round(square.x + square.y));
  let within = min(max(reach.x, reach.y), 0);
  return clamp(HALF - (outside + within - radius), 0, ONE);
}

// `rgba`'s alpha scaled by a q9 coverage, rounded half up.
fn covered(rgba: u32, c: i32) -> u32 {
  return (u32(c) * (rgba >> 24u) + u32(HALF)) >> 9u;
}

@compute @workgroup_size(8, 8)
fn grid(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= params.width || id.y >= params.height) {
    return;
  }
  let p = vec2<i32>(id.xy);
  let bg = params.background;
  var pixel = vec4<u32>(bg & 0xffu, (bg >> 8u) & 0xffu, (bg >> 16u) & 0xffu, bg >> 24u);
  var at = 0u;
  // The stream is whole and every op known (mod.rs checks it before a
  // pass), so each case moves `at` on by its own words.
  while (at < params.words) {
    switch (ops[at]) {
      case OP_FILL_RECT, OP_HLINE: {
        let rgba = bitcast<u32>(ops[at + 5u]);
        if (inside(p, ops[at + 1u], ops[at + 2u], ops[at + 3u], ops[at + 4u])) {
          pixel = over(pixel, rgba, rgba >> 24u);
        }
        at += 6u;
      }
      case OP_VLINE: {
        // x, y, length, thickness: the length runs down.
        let rgba = bitcast<u32>(ops[at + 5u]);
        if (inside(p, ops[at + 1u], ops[at + 2u], ops[at + 4u], ops[at + 3u])) {
          pixel = over(pixel, rgba, rgba >> 24u);
        }
        at += 6u;
      }
      case OP_GLYPH: {
        // dest x, y, atlas x, y, w, h: the atlas window laid at the
        // destination, its coverage scaling the colour's alpha.
        let rgba = bitcast<u32>(ops[at + 7u]);
        let dest = vec2<i32>(ops[at + 1u], ops[at + 2u]);
        let source = vec2<i32>(ops[at + 3u], ops[at + 4u]) + p - dest;
        let room = vec2<i32>(i32(params.atlas_width), i32(params.atlas_height));
        if (inside(p, dest.x, dest.y, ops[at + 5u], ops[at + 6u])
            && all(source >= vec2<i32>(0)) && all(source < room)) {
          let c = textureLoad(atlas, source, 0).r;
          pixel = over(pixel, rgba, ((rgba >> 24u) * c + 127u) / 255u);
        }
        at += 8u;
      }
      case OP_RRECT_FILL: {
        let rgba = bitcast<u32>(ops[at + 7u]);
        if (ops[at + 3u] > 0 && ops[at + 4u] > 0) {
          let c = coverage(field_at(at), p);
          if (c > 0) {
            pixel = over(pixel, rgba, covered(rgba, c));
          }
        }
        at += 8u;
      }
      case OP_RRECT_RING: {
        // The box's coverage less its hole's: x, y, w, h, radius, corner
        // mask, line, open mask.
        let rgba = bitcast<u32>(ops[at + 9u]);
        let line = 2 * ops[at + 7u];
        if (ops[at + 3u] > 0 && ops[at + 4u] > 0 && line > 0) {
          let box = field_at(at);
          var c = coverage(box, p);
          let hole = hole_of(box, line, ops[at + 8u]);
          if (c > 0 && hole.half.x > 0 && hole.half.y > 0) {
            c -= coverage(hole, p);
          }
          if (c > 0) {
            pixel = over(pixel, rgba, covered(rgba, c));
          }
        }
        at += 10u;
      }
      default: {
        at = params.words;
      }
    }
  }
  let packed = pixel.r | (pixel.g << 8u) | (pixel.b << 16u) | (pixel.a << 24u);
  // The one float step, as fill.wgsl's: k/255 stored to an 8-bit unorm
  // texel comes back k on every device.
  textureStore(tile, id.xy, unpack4x8unorm(packed));
}
