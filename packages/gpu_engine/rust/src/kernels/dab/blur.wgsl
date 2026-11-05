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
// A dab is two dispatches (gpu-canonical-store 01:13): `blur_rows` works the
// rows' three passes over the dab's window, a strip a workgroup, in
// workgroup memory — each strip reads past what it puts as far as the
// passes read past the dab, so no pass waits on another workgroup's —; and
// `blur_columns` works the columns' three down the dab's columns the same
// way, then moves the dab's pixels. Dabs follow one another: each reads
// what the one before it moved.
//
// Needs dab.wgsl and box.wgsl before it.

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

// The pixels a workgroup's strip holds, in each half of its room: a pass
// reads one half and puts the other. Two halves of 1024 are the 16KB every
// device gives a workgroup.
const BLUR_ROOM: u32 = 1024u;
const BLUR_LANES: u32 = 256u;
var<workgroup> blur_room: array<vec2<u32>, 2048>;

// The strip: its lines from `blur_line0`, each `blur_span` pixels from
// `blur_span0`; the half a pass reads and the half it puts.
var<private> blur_line0: i32;
var<private> blur_span0: i32;
var<private> blur_span: u32;
var<private> blur_from: u32;
var<private> blur_to: u32;

// Where the strip's pixel `p` along `line` is in a half.
fn blur_at(line: i32, p: i32) -> u32 {
  return u32(line - blur_line0) * blur_span + u32(p - blur_span0);
}

fn blur_tap(line: i32, p: i32) -> vec4<u32> {
  return dab_four(blur_room[blur_from + blur_at(line, p)]);
}

fn blur_put(line: i32, p: i32, mean: vec4<u32>) {
  blur_room[blur_to + blur_at(line, p)] = dab_pair(mean);
}

// The block's `index`-th pass.
fn blur_pass(block: u32, index: u32) -> BoxPass {
  let at = block + BLUR_PASSES + index * BLUR_PASS_WORDS;
  return BoxPass(
    plan[at],
    plan[at + 1u],
    bitcast<i32>(plan[at + 2u]),
    bitcast<i32>(plan[at + 3u]),
    bitcast<i32>(plan[at + 4u]),
    bitcast<i32>(plan[at + 5u]),
    plan[at + 6u],
    bitcast<i32>(plan[at + 7u]),
    bitcast<i32>(plan[at + 8u]),
  );
}

// The tile along a way that holds pixel `v`.
fn blur_tile_of(v: i32) -> i32 {
  return (v - select(0, i32(TILE_SIDE) - 1, v < 0)) / i32(TILE_SIDE);
}

// The place of the record of the window's tile that holds (x, y).
fn blur_tile(block: u32, x: i32, y: i32) -> u32 {
  let column = blur_tile_of(x) - bitcast<i32>(plan[block + BLUR_TILE_COLUMN]);
  let row = blur_tile_of(y) - bitcast<i32>(plan[block + BLUR_TILE_ROW]);
  return plan[block + BLUR_GRID + u32(row) * plan[block + BLUR_TILE_COLUMNS] + u32(column)];
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

// Sets the strip that puts [put0, put1) along lines [line0, line1) by the
// way whose first pass is `first` and last `last`: what the first reads.
fn blur_strip(first: BoxPass, last: BoxPass, put0: i32, put1: i32, line0: i32) {
  let r = i32(first.radius);
  blur_line0 = line0;
  blur_span0 = put0 - (last.first - first.first) - r;
  blur_span = u32(put1 + (first.end - last.end) + r - blur_span0);
}

// The three passes of the way whose first is the block's `first`-th, over
// the strip, which is in the first half; the last puts its pixels in the
// second. Each pass puts as far past the strip as it puts past the dab, the
// lanes taking runs of a line between them.
fn blur_three(block: u32, first: u32, put0: i32, put1: i32, lines: u32, lane: u32) {
  let last = blur_pass(block, first + 2u);
  for (var k = 0u; k < 3u; k++) {
    let pass_ = blur_pass(block, first + k);
    let start = put0 - (last.first - pass_.first);
    let stop = put1 + (pass_.end - last.end);
    let along = u32(stop - start);
    let run = max(1u, (lines * along + BLUR_LANES - 1u) / BLUR_LANES);
    let runs = (along + run - 1u) / run;
    blur_from = select(BLUR_ROOM, 0u, k != 1u);
    blur_to = BLUR_ROOM - blur_from;
    for (var t = lane; t < lines * runs; t += BLUR_LANES) {
      let s = start + i32((t % runs) * run);
      blur_slide(blur_line0 + i32(t / runs), s, min(s + i32(run), stop), pass_.radius);
    }
    workgroupBarrier();
  }
}

// The rows' three passes over a strip of the window: workgroup (x, y) puts
// its run of the dab's columns on its lines of the window's rows.
@compute @workgroup_size(256)
fn blur_rows_pass(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_index) lane: u32,
) {
  let block = blur_dab.x;
  let first = blur_pass(block, 0u);
  let last = blur_pass(block, 2u);
  let along = plan[block + BLUR_ROWS_ALONG];
  let put0 = last.first + i32(group.x * along);
  let put1 = min(put0 + i32(along), last.end);
  let line0 = first.line_first + i32(group.y * plan[block + BLUR_ROWS_LINES]);
  let line1 = min(line0 + i32(plan[block + BLUR_ROWS_LINES]), first.line_end);
  let lines = u32(line1 - line0);
  blur_strip(first, last, put0, put1, line0);
  for (var i = lane; i < lines * blur_span; i += BLUR_LANES) {
    let x = blur_span0 + i32(i % blur_span);
    let y = line0 + i32(i / blur_span);
    let tile = blur_tile(block, x, y);
    let at = blur_word(tile, blur_local(tile, x, y));
    blur_room[i] = vec2<u32>(planes[at], planes[at + 1u]);
  }
  workgroupBarrier();
  blur_three(block, 0u, put0, put1, lines, lane);
  let width = u32(last.end - last.first);
  let puts = u32(put1 - put0);
  for (var i = lane; i < lines * puts; i += BLUR_LANES) {
    let x = put0 + i32(i % puts);
    let y = line0 + i32(i / puts);
    let pair = blur_room[BLUR_ROOM + blur_at(y, x)];
    let at = (u32(y - first.line_first) * width + u32(x - last.first)) * 2u;
    blur_rows[at] = pair.x;
    blur_rows[at + 1u] = pair.y;
  }
}

// What `was` comes to moved toward `to` by `share` of the way, rounded
// half away from zero: round(d·share / 65535) has no tie, 65535 being odd.
fn blur_toward(was: u32, to: u32, share: u32) -> u32 {
  if (to >= was) {
    return was + blend_mul(to - was, share);
  }
  return was - blend_mul(was - to, share);
}

// The columns' three passes down a strip of the dab's columns, then the
// dab's pixels on it moved toward their blur: workgroup (x, y) takes its
// columns and its run of the dab's rows.
@compute @workgroup_size(256)
fn blur_columns_pass(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_index) lane: u32,
) {
  let block = blur_dab.x;
  let rows_first = blur_pass(block, 0u);
  let rows_last = blur_pass(block, 2u);
  let first = blur_pass(block, 3u);
  let last = blur_pass(block, 5u);
  let along = plan[block + BLUR_COLUMNS_ALONG];
  let put0 = last.first + i32(group.y * along);
  let put1 = min(put0 + i32(along), last.end);
  let line0 = first.line_first + i32(group.x * plan[block + BLUR_COLUMNS_LINES]);
  let line1 = min(line0 + i32(plan[block + BLUR_COLUMNS_LINES]), first.line_end);
  let lines = u32(line1 - line0);
  blur_strip(first, last, put0, put1, line0);
  let width = u32(rows_last.end - rows_last.first);
  for (var i = lane; i < lines * blur_span; i += BLUR_LANES) {
    let x = line0 + i32(i / blur_span);
    let y = blur_span0 + i32(i % blur_span);
    let at = (u32(y - rows_first.line_first) * width + u32(x - rows_last.first)) * 2u;
    blur_room[i] = vec2<u32>(blur_rows[at], blur_rows[at + 1u]);
  }
  workgroupBarrier();
  blur_three(block, 3u, put0, put1, lines, lane);
  let record = plan[block + BLUR_RECORD];
  let puts = u32(put1 - put0);
  for (var i = lane; i < lines * puts; i += BLUR_LANES) {
    let x = line0 + i32(i / puts);
    let y = put0 + i32(i % puts);
    let tile = blur_tile(block, x, y);
    let local = blur_local(tile, x, y);
    var paper = 0u;
    if (plan[HEAD_PAPER] != NO_TABLE) {
      paper = dab_paper(tile, local.x, local.y);
    }
    let share = dab_source(record, x, y, 0u, paper);
    if (share == NOTHING) {
      continue;
    }
    let at = blur_word(tile, local);
    let was = dab_four(vec2<u32>(planes[at], planes[at + 1u]));
    let to = dab_four(blur_room[BLUR_ROOM + blur_at(x, y)]);
    let moved = dab_pair(vec4<u32>(
      blur_toward(was.x, to.x, share),
      blur_toward(was.y, to.y, share),
      blur_toward(was.z, to.z, share),
      blur_toward(was.w, to.w, share),
    ));
    planes[at] = moved.x;
    planes[at + 1u] = moved.y;
  }
}
