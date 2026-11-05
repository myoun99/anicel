// The blur brush's dab (I-75 흐리기 — BrushBlurPicture.blurDab, C's
// qa_blur_dab): the stroke's picture under the dab moved toward its blur by
// what the dab would lay as paint onto nothing,
//
//     picture ← picture + (blurred(picture) − picture) × laid
//
// rounded half away from zero. The picture is the stroke's planes (dab.wgsl's
// binding 1): premultiplied, 16 bits a channel, a slot a tile. `blurred` is
// box.wgsl's three passes along the rows, then three down the columns, at
// the radius the dab's size sets; `laid` is dab.wgsl's `dab_source` over
// nothing — the dab's own coverage law on its record, white and not
// erasing, as the app measures it with the dab kernel on an empty scratch.
//
// A dab is two dispatches (gpu-canonical-store 01:13), a way's three passes
// each, a strip a workgroup in workgroup memory (effects/blur/three.wgsl):
// `blur_rows_pass` blurs the rows over the dab's window into `blur_rows`,
// and `blur_columns_pass` blurs the columns of that down the dab, its last
// pass moving the dab's pixels. Dabs follow one another: each reads what
// the one before it moved.
//
// Needs dab.wgsl, box.wgsl and three.wgsl before it.

// A dab's block in the plan, at the word `blur_dab.x` names: its record,
// the window's first tile and its tiles a row, how many lines and how far
// along a workgroup of each dispatch takes, the six passes (gaussian.rs's
// `within`, the rows' three first), then the place of each of the window's
// tiles' records, row after row of them.
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

// The rows' blur of the dab's columns over its window, a window row after
// another, from one dispatch to the next.
@group(0) @binding(4) var<storage, read_write> blur_rows: array<u32>;
// Where the dab's block is.
@group(0) @binding(5) var<uniform> blur_dab: vec4<u32>;

// The dab's block, and the rows' blur's first pixel and line and its width.
var<private> blur_block: u32;
var<private> blur_rows_x0: i32;
var<private> blur_rows_y0: i32;
var<private> blur_rows_width: u32;

// The block's `index`-th pass.
fn blur_pass(block: u32, index: u32) -> BoxPass {
  let at = block + BLUR_PASSES + index * BLUR_PASS_WORDS;
  var words: array<u32, 9>;
  for (var i = 0u; i < 9u; i++) {
    words[i] = plan[at + i];
  }
  return box_pass(words);
}

// The block's way whose first pass is its `first`-th.
fn blur_passes(block: u32, first: u32) -> array<BoxPass, 3> {
  return array<BoxPass, 3>(
    blur_pass(block, first),
    blur_pass(block, first + 1u),
    blur_pass(block, first + 2u),
  );
}

// The tile along a way that holds pixel `v`.
fn blur_tile_of(v: i32) -> i32 {
  return (v - select(0, i32(TILE_SIDE) - 1, v < 0)) / i32(TILE_SIDE);
}

// The place of the record of the window's tile that holds (x, y).
fn blur_tile(x: i32, y: i32) -> u32 {
  let column = blur_tile_of(x) - bitcast<i32>(plan[blur_block + BLUR_TILE_COLUMN]);
  let row = blur_tile_of(y) - bitcast<i32>(plan[blur_block + BLUR_TILE_ROW]);
  return plan[blur_block + BLUR_GRID + u32(row) * plan[blur_block + BLUR_TILE_COLUMNS]
    + u32(column)];
}

// Where (x, y) is in its tile.
fn blur_local(tile: u32, x: i32, y: i32) -> vec2<u32> {
  let side = i32(TILE_SIDE);
  return vec2<u32>(
    u32(x - bitcast<i32>(plan[tile + TILE_COLUMN]) * side),
    u32(y - bitcast<i32>(plan[tile + TILE_ROW]) * side),
  );
}

// The first of the two words of (x, y) in the planes, on `tile`.
fn blur_word(tile: u32, local: vec2<u32>) -> u32 {
  return (plan[tile + TILE_SLOT] * TILE_TEXELS + tile_texel(local.x, local.y)) * 2u;
}

// The first of the two words of (x, y) in the rows' blur.
fn blur_between(x: i32, y: i32) -> u32 {
  return (u32(y - blur_rows_y0) * blur_rows_width + u32(x - blur_rows_x0)) * 2u;
}

// The dab's block, and where the rows' blur keeps its pixels: the rows'
// lines, the dab's columns.
fn blur_begin() {
  blur_block = blur_dab.x;
  let first = blur_pass(blur_block, 0u);
  let last = blur_pass(blur_block, 2u);
  blur_rows_x0 = last.first;
  blur_rows_y0 = first.line_first;
  blur_rows_width = u32(last.end - last.first);
}

// What a way's first pass reads: the rows' the picture, the columns' the
// rows' blur.
fn blur_load(first: BoxPass, line: i32, p: i32) -> vec4<u32> {
  if (first.down == 0u) {
    let tile = blur_tile(p, line);
    let at = blur_word(tile, blur_local(tile, p, line));
    return blend_unpack16(vec2<u32>(planes[at], planes[at + 1u]));
  }
  let at = blur_between(line, p);
  return blend_unpack16(vec2<u32>(blur_rows[at], blur_rows[at + 1u]));
}

// What a way's last pass puts: the rows' into the rows' blur; the
// columns', the dab's pixel moved toward it.
fn blur_store(last: BoxPass, line: i32, p: i32, pixel: vec4<u32>) {
  if (last.down == 0u) {
    let at = blur_between(p, line);
    let pair = blend_pack16(pixel);
    blur_rows[at] = pair.x;
    blur_rows[at + 1u] = pair.y;
    return;
  }
  blur_move(line, p, pixel);
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
  let tile = blur_tile(x, y);
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
  let at = blur_word(tile, local);
  let was = blend_unpack16(vec2<u32>(planes[at], planes[at + 1u]));
  let moved = blend_pack16(vec4<u32>(
    blur_toward(was.x, to.x, share),
    blur_toward(was.y, to.y, share),
    blur_toward(was.z, to.z, share),
    blur_toward(was.w, to.w, share),
  ));
  planes[at] = moved.x;
  planes[at + 1u] = moved.y;
}

// The rows' three passes over the dab's window: workgroup (x, y) takes
// strip x along the dab's columns, band y of the window's rows.
@compute @workgroup_size(256)
fn blur_rows_pass(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_index) lane: u32,
) {
  blur_begin();
  let run = plan[blur_block + BLUR_ROWS_ALONG];
  let lines = plan[blur_block + BLUR_ROWS_LINES];
  blur_way(blur_passes(blur_block, 0u), group.x, group.y, run, lines, lane);
}

// The columns' three passes down the dab, then its pixels moved: workgroup
// (x, y) takes strip x down the dab's rows, band y of its columns.
@compute @workgroup_size(256)
fn blur_columns_pass(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_index) lane: u32,
) {
  blur_begin();
  let run = plan[blur_block + BLUR_COLUMNS_ALONG];
  let lines = plan[blur_block + BLUR_COLUMNS_LINES];
  blur_way(blur_passes(blur_block, 3u), group.x, group.y, run, lines, lane);
}
