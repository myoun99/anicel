// The blur brush's dab a box pass a dispatch (gpu-canonical-store 01:13 ③,
// effects/blur/pass.wgsl): six dispatches over the dab's window, the rows'
// three then the columns' three, each reading what the one before put —
// the way a dab goes whose strips would put too few of the pixels they
// read. The passes alternate between two planes, the halves of
// `blur_between`, each laid as the rows' first pass puts: the window's
// lines, the dab's columns two radii out each side. The first pass reads
// the picture; the last moves the dab's pixels (blur.wgsl's `blur_move`).
//
// Needs blur.wgsl and effects/blur/pass.wgsl before it.

// The dispatch's pass, the `blur_dab.y`-th of the block's six.
var<private> blur_k: u32;
var<private> blur_now: BoxPass;
// The planes' first pixel and line, and their width and lines.
var<private> blur_plane_x0: i32;
var<private> blur_plane_y0: i32;
var<private> blur_plane_width: u32;
var<private> blur_plane_lines: u32;

// The first of the two words of (x, y) in plane `half`.
fn blur_plane(half: u32, x: i32, y: i32) -> u32 {
  let row = half * blur_plane_lines + u32(y - blur_plane_y0);
  return (row * blur_plane_width + u32(x - blur_plane_x0)) * 2u;
}

// (x, y) of `p` along `line`, by the pass's way.
fn blur_xy(line: i32, p: i32) -> vec2<i32> {
  return select(vec2<i32>(p, line), vec2<i32>(line, p), blur_now.down == 1u);
}

// The first pass reads the picture; each after it the plane the one before
// put — they alternate, the first putting plane 0.
fn blur_tap(line: i32, p: i32) -> vec4<u32> {
  let at = blur_xy(line, p);
  if (blur_k == 0u) {
    return blur_picture(at.x, at.y);
  }
  let word = blur_plane((blur_k - 1u) % 2u, at.x, at.y);
  return blend_unpack16(vec2<u32>(blur_between[word], blur_between[word + 1u]));
}

fn blur_put(line: i32, p: i32, mean: vec4<u32>) {
  let at = blur_xy(line, p);
  if (blur_k == 5u) {
    blur_move(at.x, at.y, mean);
    return;
  }
  let word = blur_plane(blur_k % 2u, at.x, at.y);
  let pair = blend_pack16(mean);
  blur_between[word] = pair.x;
  blur_between[word + 1u] = pair.y;
}

@compute @workgroup_size(8, 8, 1)
fn blur_pass_one(@builtin(global_invocation_id) id: vec3<u32>) {
  blur_block = blur_dab.x;
  blur_k = blur_dab.y;
  blur_now = blur_pass(blur_block, blur_k);
  let rows = blur_pass(blur_block, 0u);
  blur_plane_x0 = rows.first;
  blur_plane_y0 = rows.line_first;
  blur_plane_width = u32(rows.end - rows.first);
  blur_plane_lines = u32(rows.line_end - rows.line_first);
  blur_run(blur_now, id);
}
