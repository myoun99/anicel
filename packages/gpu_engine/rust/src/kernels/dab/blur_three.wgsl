// The blur brush's dab a way's three passes a dispatch (gpu-canonical-store
// 01:13), a strip a workgroup in workgroup memory (effects/blur/three.wgsl):
// `blur_rows_pass` blurs the rows over the dab's window into
// `blur_between`, the dab's columns on the window's lines, and
// `blur_columns_pass` blurs the columns of that down the dab, its last pass
// moving the dab's pixels.
//
// Needs blur.wgsl and effects/blur/three.wgsl before it.

// The rows' blur's first pixel and line, and its width.
var<private> blur_rows_x0: i32;
var<private> blur_rows_y0: i32;
var<private> blur_rows_width: u32;

// The block's way whose first pass is its `first`-th.
fn blur_passes(block: u32, first: u32) -> array<BoxPass, 3> {
  return array<BoxPass, 3>(
    blur_pass(block, first),
    blur_pass(block, first + 1u),
    blur_pass(block, first + 2u),
  );
}

// The first of the two words of (x, y) in the rows' blur.
fn blur_rows_at(x: i32, y: i32) -> u32 {
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
    return blur_picture(p, line);
  }
  let at = blur_rows_at(line, p);
  return blend_unpack16(vec2<u32>(blur_between[at], blur_between[at + 1u]));
}

// What a way's last pass puts: the rows' into the rows' blur; the
// columns', the dab's pixel moved toward it.
fn blur_store(last: BoxPass, line: i32, p: i32, pixel: vec4<u32>) {
  if (last.down == 0u) {
    let at = blur_rows_at(p, line);
    let pair = blend_pack16(pixel);
    blur_between[at] = pair.x;
    blur_between[at + 1u] = pair.y;
    return;
  }
  blur_move(line, p, pixel);
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
