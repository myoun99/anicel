// The write path's test (gpu-canonical-store 11-06 03:36): whether a tile a
// kernel put differs from the tile stored where it goes — or, where none is
// stored, from nothing — and the box its ink fills (shared/ink_box.wgsl): a
// pixel whose alpha is not 0, the question the app's `hasInk` asks
// (bitmap_tile.dart), and where. A tile with nothing stored names NO_PAGE,
// whose words page_word reads as 0, so one comparison asks both.
//
// 🗣️유저 2026-11-24 (card the-ui-isolate-still-waits-for-the-gpu-in-places-
// Q1 「A 를 커널 안에서 — 비교 커널이 상자도 같이 쓴다」): the box a tile's ink
// fills was asked of a scan of its own the moment the move tool asked, and
// waited for the GPU there. The test that tells a landing what it left reads
// every word the box is made of, so it tells the box too. ↩️Till then a
// lane stopped reading once it had found both a word unlike and one with
// ink; the box needs every word, and whether ink is left is the box's to
// say — there is no bit of it beside the box.
//
// A tile is a workgroup; its lanes take its words WRITE_LANES apart.
//
// Needs shared/tile.wgsl, shared/pages.wgsl (with its bindings),
// shared/stored.wgsl and shared/ink_box.wgsl.

const WRITE_LANES: u32 = 256u;
// The bit of a tile's word: it differs from what is stored.
const WRITE_DIFFERS: u32 = 1u;

// x: the pass's first tile among all the write is given; y: how many the
// write is given — where the boxes start in `changed`.
@group(0) @binding(0) var<uniform> written: vec4<u32>;
// Each of the pass's tiles: the binding of its page among the pass's, or
// NO_PAGE, and its slot.
@group(0) @binding(1) var<storage, read> given: array<u32>;
// The pass's tiles put, straight RGBA8 tile after tile.
@group(0) @binding(2) var<storage, read> put: array<u32>;
// A word a tile of the write — its WRITE_ bits —, then four a tile: the box
// its ink fills, as `ink_box_folded` gives it.
@group(0) @binding(3) var<storage, read_write> changed: array<atomic<u32>>;

@compute @workgroup_size(256, 1, 1)
fn write_changed(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_index) lane: u32,
) {
  let tile = group.x;
  let k = given[tile * 2u];
  let slot = given[tile * 2u + 1u];
  ink_box_start(lane);
  // A lane that has found its tile unlike reads no more of the stored one
  // (브러시/렌더링 08:20 review). No test tells it from reading on: the bits
  // are the same.
  var bits = 0u;
  var found = ink_none();
  for (var i = lane; i < TILE_TEXELS; i += WRITE_LANES) {
    let word = put[tile * TILE_TEXELS + i];
    if ((bits & WRITE_DIFFERS) == 0u && word != stored_word(k, slot, i)) {
      bits |= WRITE_DIFFERS;
    }
    found = ink_box_take(found, i, word);
  }
  if (bits != 0u) {
    atomicOr(&changed[written.x + tile], bits);
  }
  let box = ink_box_folded(found);
  if (lane == 0u) {
    let at = written.y + (written.x + tile) * 4u;
    atomicStore(&changed[at], box.x);
    atomicStore(&changed[at + 1u], box.y);
    atomicStore(&changed[at + 2u], box.z);
    atomicStore(&changed[at + 3u], box.w);
  }
}
