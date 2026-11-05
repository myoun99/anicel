// The walk a pass over a cel's pixels takes (cel_pixel/mod.rs's `walk`):
// what a pass is given starts with its tiles in walk order, and may hold a
// selection's rows further on. A tile is a workgroup and a row a lane. The
// verbs (cel_pixel.wgsl) and the lift (lift.wgsl) read a walked tile, its
// pixels and what covers them here alike.
//
// Needs shared/tile.wgsl, shared/pages.wgsl (with its bindings) and
// mask/byte.wgsl before it; defines byte.wgsl's `mask_word`.

// A walked tile: the binding of its page, its slot, its index in the walk,
// and where its top-left pixel is among the pass's rows of the mask — a
// word's two's complement each way.
const WALK_TILE_WORDS: u32 = 5u;

@group(0) @binding(1) var<storage, read> given: array<u32>;

fn mask_word(at: u32) -> u32 {
  return given[at];
}

fn walk_tile(tile: u32, word: u32) -> u32 {
  return given[tile * WALK_TILE_WORDS + word];
}

// Pixel (x, y) of the tile, as stored.
fn walk_texel(tile: u32, x: u32, y: u32) -> u32 {
  return page_word(walk_tile(tile, 0u), walk_tile(tile, 1u) * TILE_TEXELS + y * TILE_SIDE + x);
}

// The coverage `mask` — the pass's rows of it — gives pixel (x, y) of the
// tile.
//
// ⚠️The mask's rows end what a pass is given, so a row past them is past
// the buffer, where DX12 reads 0 — the tests cannot see byte.wgsl's guard
// on rows there, nor that `mask.height` is the pass's rows and not the
// box's (mutants c03 · w07 in the verbs, b03 · r02 in the lift, 11-06;
// mask.wgsl's head has the same); a device that clamps (Metal) would read
// the last word. A column past the box is within its row's last word,
// which the tests fill with 255.
fn walk_coverage(mask: MaskPlane, tile: u32, x: u32, y: u32) -> u32 {
  return mask_byte_of(mask, walk_tile(tile, 3u) + x, walk_tile(tile, 4u) + y);
}
