// The Gaussian a pass a dispatch — the way a way goes whose strip has no
// room in a workgroup (gaussian.rs's `strips`). A thread takes a run of
// BLUR_RUN pixels of a line and slides one sum along it (box.wgsl's
// `blur_slide`).
//
// Needs gaussian.wgsl before it.

const BLUR_RUN: u32 = 64u;

@group(0) @binding(3) var<uniform> box_: BoxPass;

fn blur_tap(line: i32, p: i32) -> vec4<u32> {
  return gaussian_read(box_, line, p);
}

fn blur_put(line: i32, p: i32, mean: vec4<u32>) {
  gaussian_write(box_, line, p, mean);
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
