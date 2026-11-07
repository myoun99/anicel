// fx Gaussian Blur, a way a pass (gaussian.rs, 🗣️유저 gpu-canonical-store-
// Q2): each pixel it puts the sum of its way's weights over the pixels
// `reach` either side of it and itself, on held.wgsl's premultiplied 16-bit
// scale, rounded half up once. The weights sum to 65536, so a sum of
// 65535s is 65535·65536 at most and, with the half, stays inside a u32;
// a weight beside the middle is under a third of them, so two pixels under
// one are too.
//
// Needs held.wgsl before it.

// How a read past the picture is taken: as nothing; as the nearest pixel
// inside.
const GAUSSIAN_EDGE_NOTHING: u32 = 1u;

// One pass: along the rows (down 0) or the columns (down 1), how far its
// weights reach, the pixels it puts — [first, end) along, lines
// [line_first, line_end) across —, how it reads past [edge_first, edge_end)
// along and [cross_first, cross_end) across, and where its weights begin
// (gaussian.rs's `Pass::words`).
struct GaussianPass {
  down: u32,
  reach: u32,
  first: i32,
  end: i32,
  line_first: i32,
  line_end: i32,
  edge: u32,
  edge_first: i32,
  edge_end: i32,
  cross_first: i32,
  cross_end: i32,
  weights: u32,
}

@group(0) @binding(3) var<uniform> gaussian_: GaussianPass;
// Each way's weights, its middle's first: the rows' then the columns'.
@group(0) @binding(4) var<storage, read> gaussian_weights: array<u32>;

// The pixel the pass reads at `p` along `line`: past the picture, nothing
// or the nearest pixel inside.
fn gaussian_tap(line: i32, p: i32) -> vec4<u32> {
  var at = p;
  var across = line;
  if (p < gaussian_.edge_first || p >= gaussian_.edge_end
      || line < gaussian_.cross_first || line >= gaussian_.cross_end) {
    if (gaussian_.edge == GAUSSIAN_EDGE_NOTHING) {
      return vec4<u32>(0u);
    }
    at = clamp(p, gaussian_.edge_first, gaussian_.edge_end - 1);
    across = clamp(line, gaussian_.cross_first, gaussian_.cross_end - 1);
  }
  if (gaussian_.down == 1u) {
    return held_read(across, at);
  }
  return held_read(at, across);
}

// A thread a pixel, neighbours along a row side by side: along the rows x
// is along, down the columns it is across.
@compute @workgroup_size(8, 8, 1)
fn gaussian_blur(@builtin(global_invocation_id) id: vec3<u32>) {
  let down = gaussian_.down == 1u;
  let p = gaussian_.first + i32(select(id.x, id.y, down));
  let line = gaussian_.line_first + i32(select(id.y, id.x, down));
  if (p >= gaussian_.end || line >= gaussian_.line_end) {
    return;
  }
  let middle = gaussian_.weights;
  var sum = gaussian_weights[middle] * gaussian_tap(line, p);
  for (var i = 1u; i <= gaussian_.reach; i++) {
    let d = i32(i);
    let pair = gaussian_tap(line, p - d) + gaussian_tap(line, p + d);
    sum += gaussian_weights[middle + i] * pair;
  }
  let pixel = (sum + vec4<u32>(32768u)) >> vec4<u32>(16u);
  if (down) {
    held_write(line, p, pixel);
  } else {
    held_write(p, line, pixel);
  }
}
