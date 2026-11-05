// R4b on the GPU (gpu-census R4b — C's `qa_tile_alpha_bounds`, the app's
// `_scanInkBounds`): for each walked tile, the least and the greatest
// column and row of its pixels with ink — an alpha that is not 0 —, in the
// tile. A tile with none keeps them as they start, the least past the
// greatest.
//
// A tile is a workgroup; its lanes take its words INK_LANES apart, as they
// lie, and fold what each found into the tile's four words in the
// workgroup's memory.
//
// Needs shared/tile.wgsl, shared/pages.wgsl (with its bindings),
// mask/byte.wgsl and walk.wgsl before it.

const INK_LANES: u32 = 256u;

// x: the pass's first tile among the walk's.
@group(0) @binding(0) var<uniform> inked: vec4<u32>;
// Four words a walked tile: its ink's least column and row, then its
// greatest — TILE_SIDE and 0 where it has none.
@group(0) @binding(2) var<storage, read_write> boxes: array<u32>;

var<workgroup> least: array<atomic<u32>, 2>;
var<workgroup> greatest: array<atomic<u32>, 2>;

@compute @workgroup_size(256, 1, 1)
fn ink_box(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_index) lane: u32,
) {
  let tile = group.x;
  if (lane == 0u) {
    atomicStore(&least[0], TILE_SIDE);
    atomicStore(&least[1], TILE_SIDE);
    atomicStore(&greatest[0], 0u);
    atomicStore(&greatest[1], 0u);
  }
  workgroupBarrier();
  var low = vec2<u32>(TILE_SIDE);
  var high = vec2<u32>(0u);
  for (var i = lane; i < TILE_TEXELS; i += INK_LANES) {
    let at = vec2<u32>(i % TILE_SIDE, i / TILE_SIDE);
    if ((walk_texel(tile, at.x, at.y) >> 24u) != 0u) {
      low = min(low, at);
      high = max(high, at);
    }
  }
  // A lane that found none folds in what changes nothing.
  atomicMin(&least[0], low.x);
  atomicMin(&least[1], low.y);
  atomicMax(&greatest[0], high.x);
  atomicMax(&greatest[1], high.y);
  workgroupBarrier();
  if (lane == 0u) {
    let at = (inked.x + tile) * 4u;
    boxes[at] = atomicLoad(&least[0]);
    boxes[at + 1u] = atomicLoad(&least[1]);
    boxes[at + 2u] = atomicLoad(&greatest[0]);
    boxes[at + 3u] = atomicLoad(&greatest[1]);
  }
}
