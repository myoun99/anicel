// The write path's test (gpu-canonical-store 11-06 03:36): whether a tile a
// kernel put differs from the tile stored where it goes — or, where none is
// stored, from nothing. A tile with nothing stored names NO_PAGE, whose
// words page_word reads as 0, so one comparison asks both.
//
// A tile is a workgroup; its lanes take its words WRITE_LANES apart, and a
// lane that finds one unlike sets the tile's word.
//
// Needs shared/tile.wgsl and shared/pages.wgsl (with its bindings).

const WRITE_LANES: u32 = 256u;

// x: the pass's first tile among all the write is given.
@group(0) @binding(0) var<uniform> written: vec4<u32>;
// Each of the pass's tiles: the binding of its page among the pass's, or
// NO_PAGE, and its slot.
@group(0) @binding(1) var<storage, read> given: array<u32>;
// The pass's tiles put, straight RGBA8 tile after tile.
@group(0) @binding(2) var<storage, read> put: array<u32>;
// A word a tile of the write: 1 where it changed.
@group(0) @binding(3) var<storage, read_write> changed: array<atomic<u32>>;

@compute @workgroup_size(256, 1, 1)
fn write_changed(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_index) lane: u32,
) {
  let tile = group.x;
  let k = given[tile * 2u];
  let at = given[tile * 2u + 1u] * TILE_TEXELS;
  var differs = false;
  for (var i = lane; i < TILE_TEXELS; i += WRITE_LANES) {
    differs = differs || put[tile * TILE_TEXELS + i] != page_word(k, at + i);
  }
  if (differs) {
    atomicOr(&changed[written.x + tile], 1u);
  }
}
