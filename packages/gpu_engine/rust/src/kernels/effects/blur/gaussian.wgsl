// The Gaussian's schedule: three box passes along the rows, then three
// along the columns, by box.wgsl's law (gpu-canonical-store ⑦, 관제 11-05
// 12:19: the fx Gaussian goes by C's `qa_blur_box`, the blur brush's
// passes — one blur law, not two).
//
// One dispatch is one pass. A thread takes a run of BLUR_RUN pixels of a
// line and slides one sum along it (box.wgsl's `blur_slide`).
//
// Needs held.wgsl and box.wgsl before it.

const BLUR_RUN: u32 = 64u;

// How a read past [edge_first, edge_end) along a pass is taken: as it is;
// as nothing; as the nearest pixel inside.
const BLUR_EDGE_NONE: u32 = 0u;
const BLUR_EDGE_NOTHING: u32 = 1u;
const BLUR_EDGE_REPEAT: u32 = 2u;

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

// Puts the pass's pixel at `p` along `line`.
fn blur_put(line: i32, p: i32, mean: vec4<u32>) {
  if (box_.down == 1u) {
    held_write(line, p, mean);
  } else {
    held_write(p, line, mean);
  }
}

@compute @workgroup_size(8, 8, 1)
fn box_blur(@builtin(global_invocation_id) id: vec3<u32>) {
  let line = box_.line_first + i32(id.y);
  let start = box_.first + i32(id.x * BLUR_RUN);
  if (line >= box_.line_end || start >= box_.end) {
    return;
  }
  blur_slide(line, start, min(start + i32(BLUR_RUN), box_.end), box_.radius);
}
