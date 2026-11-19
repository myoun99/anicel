// The unfold (F-610, 2026-11-19): a stored tile as it is — its 16384 words,
// a pixel each — whatever form it is stored in (stored.wgsl): what a read
// of the pool hands the CPU, which knows no form.
//
// A tile is a workgroup; its lanes take its words UNFOLD_LANES apart.
//
// Needs shared/tile.wgsl, shared/pages.wgsl (with its bindings) and
// shared/stored.wgsl before it.

const UNFOLD_LANES: u32 = 256u;

// Each of the pass's tiles: the binding of its page among the pass's, and
// its slot.
@group(0) @binding(1) var<storage, read> given: array<u32>;
// The pass's tiles as they are, tile after tile.
@group(0) @binding(2) var<storage, read_write> unfolded: array<u32>;

@compute @workgroup_size(256, 1, 1)
fn unfold(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_index) lane: u32,
) {
  let tile = group.x;
  let k = given[tile * 2u];
  let slot = given[tile * 2u + 1u];
  for (var texel = lane; texel < TILE_TEXELS; texel += UNFOLD_LANES) {
    unfolded[tile * TILE_TEXELS + texel] = stored_word(k, slot, texel);
  }
}
