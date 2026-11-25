// R4b on the GPU (gpu-census R4b — C's `qa_tile_alpha_bounds`, the app's
// `_scanInkBounds`): for each walked tile, the box its ink fills
// (shared/ink_box.wgsl has the fold).
//
// A tile is a workgroup; its lanes take its words INK_LANES apart, as they
// lie.
//
// Needs shared/tile.wgsl, shared/pages.wgsl (with its bindings),
// mask/byte.wgsl, walk.wgsl and shared/ink_box.wgsl before it.

const INK_LANES: u32 = 256u;

// x: the pass's first tile among the walk's.
@group(0) @binding(0) var<uniform> inked: vec4<u32>;
// Four words a walked tile: its ink's least column and row, then its
// greatest — TILE_SIDE and 0 where it has none.
@group(0) @binding(2) var<storage, read_write> boxes: array<u32>;

@compute @workgroup_size(256, 1, 1)
fn ink_box(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_index) lane: u32,
) {
  let tile = group.x;
  ink_box_start(lane);
  var found = ink_none();
  // Neighbouring lanes read neighbouring words. Reading down the columns
  // instead finds the same box (mutant i08, 11-06) — slower, not wrong.
  for (var i = lane; i < TILE_TEXELS; i += INK_LANES) {
    found = ink_box_take(found, i, walk_texel(tile, i % TILE_SIDE, i / TILE_SIDE));
  }
  let box = ink_box_folded(found);
  if (lane == 0u) {
    let at = (inked.x + tile) * 4u;
    boxes[at] = box.x;
    boxes[at + 1u] = box.y;
    boxes[at + 2u] = box.z;
    boxes[at + 3u] = box.w;
  }
}
