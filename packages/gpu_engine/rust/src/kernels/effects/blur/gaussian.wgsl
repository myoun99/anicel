// The Gaussian's integer law (gpu-canonical-store ⑦, 관제 11-05 12:19: the
// fx Gaussian goes by C's `qa_blur_box`, the blur brush's passes — one blur
// law, not two): three box passes along the rows, then three along the
// columns, each pixel of a pass the mean of the `radius` pixels either side
// of it and itself, rounded half up, on held.wgsl's premultiplied scale.
// The order and the rounding of every pass are part of the law
// (BrushBlurPicture has its reasons).
//
// One dispatch is one pass. A thread takes a run of BLUR_RUN pixels of a
// line and slides one sum along it, as C's pass slides one along the whole
// line: a sum of integers is the same however it was gathered.
//
// Needs held.wgsl before it.

const BLUR_RUN: u32 = 64u;

// How a read past [edge_first, edge_end) along a pass is taken: as it is;
// as nothing; as the nearest pixel inside.
const BLUR_EDGE_NONE: u32 = 0u;
const BLUR_EDGE_NOTHING: u32 = 1u;
const BLUR_EDGE_REPEAT: u32 = 2u;

// One pass: along the rows (down 0) or the columns (down 1), the pixels it
// writes — [first, end) along, lines [line_first, line_end) across — and
// its edge.
struct BoxPass {
  down: u32,
  radius: u32,
  first: i32,
  end: i32,
  line_first: i32,
  line_end: i32,
  edge: u32,
  edge_first: i32,
  edge_end: i32,
}

@group(0) @binding(3) var<uniform> box_: BoxPass;

// The pixel at `p` along `line`, by the pass's edge.
fn blur_tap(line: i32, p: i32) -> vec4<u32> {
  var at = p;
  if (box_.edge != BLUR_EDGE_NONE && (p < box_.edge_first || p >= box_.edge_end)) {
    if (box_.edge == BLUR_EDGE_NOTHING) {
      return vec4<u32>(0u);
    }
    at = clamp(p, box_.edge_first, box_.edge_end - 1);
  }
  if (box_.down == 1u) {
    return held_read(line, at);
  }
  return held_read(at, line);
}

// round(sum / count), a half up: C's (2·sum + count) / (2·count), without
// the doubled sum a u32 could not hold.
fn blur_mean(sum: u32, count: u32) -> u32 {
  return sum / count + select(0u, 1u, (sum % count) * 2u >= count);
}

@compute @workgroup_size(8, 8, 1)
fn box_blur(@builtin(global_invocation_id) id: vec3<u32>) {
  let line = box_.line_first + i32(id.y);
  let start = box_.first + i32(id.x * BLUR_RUN);
  if (line >= box_.line_end || start >= box_.end) {
    return;
  }
  let stop = min(start + i32(BLUR_RUN), box_.end);
  let r = i32(box_.radius);
  let count = box_.radius * 2u + 1u;
  var sum = vec4<u32>(0u);
  for (var p = start - r; p <= start + r; p++) {
    sum += blur_tap(line, p);
  }
  for (var p = start; p < stop; p++) {
    let mean = vec4<u32>(
      blur_mean(sum.x, count),
      blur_mean(sum.y, count),
      blur_mean(sum.z, count),
      blur_mean(sum.w, count),
    );
    if (box_.down == 1u) {
      held_write(line, p, mean);
    } else {
      held_write(p, line, mean);
    }
    if (p + 1 < stop) {
      sum = sum + blur_tap(line, p + r + 1) - blur_tap(line, p - r);
    }
  }
}
