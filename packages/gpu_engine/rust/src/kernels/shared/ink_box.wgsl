// The box a tile's ink fills (gpu-census R4b — C's `qa_tile_alpha_bounds`,
// the app's `_scanInkBounds`): the least and the greatest column and row
// of its pixels whose alpha is not 0, in the tile. A tile is a workgroup;
// each lane takes what it reads (`ink_box_take`), and the workgroup folds
// what each took into one box in its memory. A tile with none keeps the box
// as it starts, the least past the greatest.
//
// ⛔ONE: the ink scan (cel_pixel/ink.wgsl) and the write's test
// (write/write.wgsl) each fold the same box — 🗣️유저 2026-11-24, card
// the-ui-isolate-still-waits-for-the-gpu-in-places-Q1 「A 를 커널 안에서 —
// 비교 커널이 상자도 같이 쓴다」.
//
// Needs shared/tile.wgsl before it.

var<workgroup> ink_least: array<atomic<u32>, 2>;
var<workgroup> ink_greatest: array<atomic<u32>, 2>;

// What one lane has found so far: none, the least past the greatest.
struct InkFound {
  low: vec2<u32>,
  high: vec2<u32>,
}

fn ink_none() -> InkFound {
  return InkFound(vec2<u32>(TILE_SIDE), vec2<u32>(0u));
}

// `found` with the tile's texel `i` taken in, its word `word`.
fn ink_box_take(found: InkFound, i: u32, word: u32) -> InkFound {
  if ((word >> 24u) == 0u) {
    return found;
  }
  let at = vec2<u32>(i % TILE_SIDE, i / TILE_SIDE);
  return InkFound(min(found.low, at), max(found.high, at));
}

// Starts the workgroup's box as none. Every lane calls it, before any
// folds.
//
// ⚠️No test here tells its barrier from none (mutants i11 · i12, 11-06): on
// this device lane 0 has set the start long before another lane has read
// its 64 words. It stays: without it the start could land after a fold on
// a device that runs a lane's subgroup later (export/opaque.wgsl holds its
// word the same way).
fn ink_box_start(lane: u32) {
  if (lane == 0u) {
    atomicStore(&ink_least[0], TILE_SIDE);
    atomicStore(&ink_least[1], TILE_SIDE);
    atomicStore(&ink_greatest[0], 0u);
    atomicStore(&ink_greatest[1], 0u);
  }
  workgroupBarrier();
}

// Folds what each lane found into the workgroup's box and gives it: its
// least column and row, then its greatest — TILE_SIDE and 0 where the tile
// has none. Every lane calls it, once it has read all it reads; a lane that
// found none folds in what changes nothing.
//
// ⚠️Its barrier, as `ink_box_start`'s (mutant i12): the box is not read
// before it is whole.
fn ink_box_folded(found: InkFound) -> vec4<u32> {
  atomicMin(&ink_least[0], found.low.x);
  atomicMin(&ink_least[1], found.low.y);
  atomicMax(&ink_greatest[0], found.high.x);
  atomicMax(&ink_greatest[1], found.high.y);
  workgroupBarrier();
  return vec4<u32>(
    atomicLoad(&ink_least[0]),
    atomicLoad(&ink_least[1]),
    atomicLoad(&ink_greatest[0]),
    atomicLoad(&ink_greatest[1]),
  );
}
