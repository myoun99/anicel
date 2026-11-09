// A view's screen of frame grid tiles (grid-on-the-engine ⓑ, 관제
// 2026-11-08 16:42): each tile a row lays, through R1 — the map from the
// screen's pixels to the tile's — onto the pixels whose centres its box
// holds, and what none holds clear. Premultiplied once, here, as Flutter
// reads a surface (premultiply.wgsl): the tile is stored straight, as R1
// reads a word (grid.wgsl).
//
// Needs shared/wide.wgsl, shared/resample.wgsl and shared/premultiply.wgsl
// before it.

struct Laid {
  // The screen's pixels this dispatch makes: from (left, top), so many
  // across and down.
  left: u32,
  top: u32,
  columns: u32,
  rows: u32,
  // The tile's pixels across and down.
  width: u32,
  height: u32,
  // R1's words (resample.rs's ResampleMap::words): the screen's pixel to
  // the tile's.
  map: array<u32, 15>,
}

@group(0) @binding(0) var<storage, read> laid: Laid;
@group(0) @binding(1) var tile: texture_2d<f32>;
@group(0) @binding(2) var screen: texture_storage_2d<__FORMAT__, write>;

// 🚨THE TILE'S OWN TEXEL, NOT resample.wgsl's "0 OUTSIDE IT" (card
// the-grid-screen-lets-a-frame-line-through-a-white-block): this pass lays
// only the pixels whose centres the box holds, so each of them is inside
// the tile — but for R1's fixed point. Its scale is a Q.20 word, and at a
// stretch a centre on the tile's edge lands a hair past that edge: read as
// 0, S5 at 312 % showed a column of the sheet through a block. Nearest and
// the copy are all that reach this (lay.rs `laid_by`), so outside can only
// be that hair.
fn resample_texel(source: u32, x: i32, y: i32) -> u32 {
  let last = vec2<i32>(i32(laid.width) - 1, i32(laid.height) - 1);
  // The one float step: an 8-bit unorm texel read as a float packs back to
  // its byte on every device, as grid.wgsl's store comes back.
  return pack4x8unorm(textureLoad(tile, clamp(vec2<i32>(x, y), vec2<i32>(0), last), 0));
}

@compute @workgroup_size(8, 8, 1)
fn lay_clear(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= laid.columns || id.y >= laid.rows) {
    return;
  }
  textureStore(screen, vec2<u32>(laid.left + id.x, laid.top + id.y), vec4<f32>(0.0));
}

@compute @workgroup_size(8, 8, 1)
fn lay_tile(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= laid.columns || id.y >= laid.rows) {
    return;
  }
  let x = laid.left + id.x;
  let y = laid.top + id.y;
  let word = resample(resample_map(laid.map), 0u, i32(x), i32(y));
  textureStore(screen, vec2<u32>(x, y), unpack4x8unorm(premultiply8(word)));
}
