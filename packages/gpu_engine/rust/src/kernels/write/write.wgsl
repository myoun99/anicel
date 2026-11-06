// The write path's test (gpu-canonical-store 11-06 03:36): whether a tile a
// kernel put differs from the tile stored where it goes — or, where none is
// stored, from nothing — and whether any ink is left in it. A tile with
// nothing stored names NO_PAGE, whose words page_word reads as 0, so one
// comparison asks both.
//
// A tile is a workgroup; its lanes take its words WRITE_LANES apart, and a
// lane that finds one unlike, or one with ink, sets that bit of the tile's
// word.
//
// Needs shared/tile.wgsl and shared/pages.wgsl (with its bindings).

const WRITE_LANES: u32 = 256u;
// The bits of a tile's word: it differs from what is stored; ink is left in
// it — a pixel whose alpha is not 0, the question the app's `hasInk` asks
// (bitmap_tile.dart).
const WRITE_DIFFERS: u32 = 1u;
const WRITE_INKED: u32 = 2u;

// x: the pass's first tile among all the write is given.
@group(0) @binding(0) var<uniform> written: vec4<u32>;
// Each of the pass's tiles: the binding of its page among the pass's, or
// NO_PAGE, and its slot.
@group(0) @binding(1) var<storage, read> given: array<u32>;
// The pass's tiles put, straight RGBA8 tile after tile.
@group(0) @binding(2) var<storage, read> put: array<u32>;
// A word a tile of the write: its WRITE_ bits.
@group(0) @binding(3) var<storage, read_write> changed: array<atomic<u32>>;

@compute @workgroup_size(256, 1, 1)
fn write_changed(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_index) lane: u32,
) {
  let tile = group.x;
  let k = given[tile * 2u];
  let at = given[tile * 2u + 1u] * TILE_TEXELS;
  var bits = 0u;
  for (var i = lane; i < TILE_TEXELS; i += WRITE_LANES) {
    let word = put[tile * TILE_TEXELS + i];
    bits |= select(0u, WRITE_DIFFERS, word != page_word(k, at + i));
    bits |= select(0u, WRITE_INKED, (word >> 24u) != 0u);
  }
  if (bits != 0u) {
    atomicOr(&changed[written.x + tile], bits);
  }
}
