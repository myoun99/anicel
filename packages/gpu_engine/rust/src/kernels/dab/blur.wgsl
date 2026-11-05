// The blur brush's dab (I-75 흐리기 — BrushBlurPicture.blurDab, C's
// qa_blur_dab): the stroke's picture under the dab moved toward its blur by
// what the dab would lay as paint onto nothing,
//
//     picture ← picture + (blurred(picture) − picture) × laid
//
// rounded half away from zero. The picture is the stroke's planes on their
// pages (shared/pages.wgsl, from binding 4): premultiplied, 16 bits a
// channel, a tile a slot of a page. `blurred` is
// box.wgsl's three passes along the rows, then three down the columns, at
// the radius the dab's size sets; `laid` is dab.wgsl's `dab_source` over
// nothing — the dab's own coverage law on its record, white and not
// erasing, as the app measures it with the dab kernel on an empty scratch.
//
// A dab goes one of two ways (gpu-canonical-store 01:13): a way's three
// passes a dispatch, a strip a workgroup in workgroup memory
// (blur_three.wgsl), or a pass a dispatch (blur_pass.wgsl) where a strip's
// halo would leave it too few pixels to put. This file is what both read:
// the dab's block, its window's tiles, and the move. Dabs follow one
// another: each reads what the one before it moved.
//
// Needs dab.wgsl, box.wgsl and the pages (pages.rs's `source`) before it.

// A dab's block in the plan, at the word `blur_dab.x` names: its record,
// the window's first tile and its tiles a row, how many lines and how far
// along a workgroup of each strip dispatch takes, the six passes
// (gaussian.rs's `within`, the rows' three first), then for each of the
// window's tiles, row after row of them, the place of its record and the
// binding of its page.
const BLUR_RECORD: u32 = 0u;
const BLUR_TILE_COLUMN: u32 = 1u;
const BLUR_TILE_ROW: u32 = 2u;
const BLUR_TILE_COLUMNS: u32 = 3u;
const BLUR_ROWS_LINES: u32 = 4u;
const BLUR_ROWS_ALONG: u32 = 5u;
const BLUR_COLUMNS_LINES: u32 = 6u;
const BLUR_COLUMNS_ALONG: u32 = 7u;
const BLUR_PASSES: u32 = 8u;
const BLUR_PASS_WORDS: u32 = 9u;
const BLUR_GRID: u32 = 62u;

// What one dispatch of a dab puts for the next to read: the rows' blur, or
// the planes a pass a dispatch alternates between.
@group(0) @binding(1) var<storage, read_write> blur_between: array<u32>;
// Where the dab's block is, and — a pass a dispatch — which of its passes
// this dispatch is.
@group(0) @binding(2) var<uniform> blur_dab: vec4<u32>;

// The dab's block.
var<private> blur_block: u32;

// The block's `index`-th pass.
fn blur_pass(block: u32, index: u32) -> BoxPass {
  let at = block + BLUR_PASSES + index * BLUR_PASS_WORDS;
  var words: array<u32, 9>;
  for (var i = 0u; i < 9u; i++) {
    words[i] = plan[at + i];
  }
  return box_pass(words);
}

// The tile along a way that holds pixel `v`.
fn blur_tile_of(v: i32) -> i32 {
  return (v - select(0, i32(TILE_SIDE) - 1, v < 0)) / i32(TILE_SIDE);
}

// Where the block holds the window's tile that holds (x, y): the place of
// its record, then the binding of its page.
fn blur_tile(x: i32, y: i32) -> u32 {
  let column = blur_tile_of(x) - bitcast<i32>(plan[blur_block + BLUR_TILE_COLUMN]);
  let row = blur_tile_of(y) - bitcast<i32>(plan[blur_block + BLUR_TILE_ROW]);
  let tiles = u32(row) * plan[blur_block + BLUR_TILE_COLUMNS] + u32(column);
  return blur_block + BLUR_GRID + tiles * 2u;
}

// Where (x, y) is in its tile.
fn blur_local(tile: u32, x: i32, y: i32) -> vec2<u32> {
  let side = i32(TILE_SIDE);
  return vec2<u32>(
    u32(x - bitcast<i32>(plan[tile + TILE_COLUMN]) * side),
    u32(y - bitcast<i32>(plan[tile + TILE_ROW]) * side),
  );
}

// The first of the two words of (x, y) on its page, on `tile`.
fn blur_word(tile: u32, local: vec2<u32>) -> u32 {
  return (plan[tile + TILE_SLOT] * TILE_TEXELS + tile_texel(local.x, local.y)) * 2u;
}

// The picture's pixel at (x, y).
fn blur_picture(x: i32, y: i32) -> vec4<u32> {
  let held = blur_tile(x, y);
  let tile = plan[held];
  let k = plan[held + 1u];
  let at = blur_word(tile, blur_local(tile, x, y));
  return blend_unpack16(vec2<u32>(page_word(k, at), page_word(k, at + 1u)));
}

// What `was` comes to moved toward `to` by `share` of the way, rounded
// half away from zero: round(d·share / 65535) has no tie, 65535 being odd.
// The law of blend.wgsl's `blend_clip_toward(to, was, share, 65535)`; two
// so far, so they stay apart until a third comes (rule of three, 캔버스
// 베이스 11-06 02:29).
fn blur_toward(was: u32, to: u32, share: u32) -> u32 {
  if (to >= was) {
    return was + blend_mul(to - was, share);
  }
  return was - blend_mul(was - to, share);
}

// The dab's pixel at (x, y) moved toward its blur `to` by what the dab
// lays there onto nothing.
fn blur_move(x: i32, y: i32, to: vec4<u32>) {
  let held = blur_tile(x, y);
  let tile = plan[held];
  let local = blur_local(tile, x, y);
  var paper = 0u;
  if (plan[HEAD_PAPER] != NO_TABLE) {
    paper = dab_paper(tile, local.x, local.y);
  }
  let share = dab_source(plan[blur_block + BLUR_RECORD], x, y, 0u, paper);
  // Where the dab lays nothing the pixel stays — by this line. Without it,
  // blend_mul by NOTHING wraps to 0 for every difference a channel can
  // make, so no test tells the two apart (mutant w03, 11-06).
  if (share == NOTHING) {
    return;
  }
  let k = plan[held + 1u];
  let at = blur_word(tile, local);
  let was = blend_unpack16(vec2<u32>(page_word(k, at), page_word(k, at + 1u)));
  let moved = blend_pack16(vec4<u32>(
    blur_toward(was.x, to.x, share),
    blur_toward(was.y, to.y, share),
    blur_toward(was.z, to.z, share),
    blur_toward(was.w, to.w, share),
  ));
  page_put(k, at, moved.x);
  page_put(k, at + 1u, moved.y);
}
