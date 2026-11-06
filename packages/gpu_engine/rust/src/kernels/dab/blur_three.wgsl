// The blur brush's dab a way's three passes a dispatch (gpu-canonical-store
// 01:13), a strip a workgroup in workgroup memory (effects/blur/three.wgsl):
// `blur_rows_pass` blurs the rows over the dab's window into
// `blur_between`, the dab's columns on the window's lines, and
// `blur_columns_pass` blurs the columns of that down the dab, its last pass
// moving the dab's pixels. A dab of few workgroups goes in turn instead:
// `blur_dabs_in_turn` takes a run of them in one workgroup, one after
// another.
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

// The dab's block at `block`, and where the rows' blur keeps its pixels:
// the rows' lines, the dab's columns.
fn blur_begin(block: u32) {
  blur_block = block;
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
  blur_begin(blur_dab.x);
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
  blur_begin(blur_dab.x);
  let run = plan[blur_block + BLUR_COLUMNS_ALONG];
  let lines = plan[blur_block + BLUR_COLUMNS_LINES];
  blur_way(blur_passes(blur_block, 3u), group.x, group.y, run, lines, lane);
}

// A dab's place in a list of dabs in turn: its block, then its rows' and
// its columns' workgroups across and down.
const BLUR_TURN_WORDS: u32 = 5u;

// A way's strips and bands one after another in this workgroup, as its
// dispatch's workgroups would put them: each puts lines and runs no other
// does, so only the room between them waits.
fn blur_way_in_turn(
  passes: array<BoxPass, 3>,
  groups: vec2<u32>,
  run: u32,
  lines: u32,
  lane: u32,
) {
  for (var band = 0u; band < groups.y; band++) {
    for (var strip = 0u; strip < groups.x; strip++) {
      blur_way(passes, strip, band, run, lines, lane);
      workgroupBarrier();
    }
  }
}

// Dabs one after another in one workgroup (11-06 — a small blur dab's floor
// was its two dispatches): `blur_dab.y` of them from the list at
// `blur_dab.x`, each way of each as its dispatch would put it. The storage
// barriers stand where a dispatch's end stood: the rows' blur put before
// the columns read it, the dab's pixels moved before the next dab reads
// them. ⚠️No test sees one of them go, nor the workgroup barrier between
// bands: one workgroup's threads keep step closely enough on the GPU here
// that the race does not show (mutants u11 · u12 · u13, 11-06). WGSL's
// memory model wants all three.
@compute @workgroup_size(256)
fn blur_dabs_in_turn(@builtin(local_invocation_index) lane: u32) {
  for (var k = 0u; k < blur_dab.y; k++) {
    let at = blur_dab.x + k * BLUR_TURN_WORDS;
    blur_begin(plan[at]);
    let rows = vec2<u32>(plan[at + 1u], plan[at + 2u]);
    let columns = vec2<u32>(plan[at + 3u], plan[at + 4u]);
    let rows_run = plan[blur_block + BLUR_ROWS_ALONG];
    let rows_lines = plan[blur_block + BLUR_ROWS_LINES];
    blur_way_in_turn(blur_passes(blur_block, 0u), rows, rows_run, rows_lines, lane);
    storageBarrier();
    let columns_run = plan[blur_block + BLUR_COLUMNS_ALONG];
    let columns_lines = plan[blur_block + BLUR_COLUMNS_LINES];
    blur_way_in_turn(blur_passes(blur_block, 3u), columns, columns_run, columns_lines, lane);
    storageBarrier();
  }
}
