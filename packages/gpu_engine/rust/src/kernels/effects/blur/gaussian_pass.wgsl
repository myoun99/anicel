// The Gaussian a pass a dispatch (pass.wgsl) — the way a way goes past the
// strips' widest box (gaussian.rs's `MOST_STRIPS_RADIUS`) or where a strip
// has no room (`strips`).
//
// Needs gaussian.wgsl and pass.wgsl before it.

@group(0) @binding(3) var<uniform> box_: BoxPass;

fn blur_tap(line: i32, p: i32) -> vec4<u32> {
  return gaussian_read(box_, line, p);
}

fn blur_put(line: i32, p: i32, mean: vec4<u32>) {
  gaussian_write(box_, line, p, mean);
}

@compute @workgroup_size(8, 8, 1)
fn box_blur(@builtin(global_invocation_id) id: vec3<u32>) {
  blur_run(box_, id);
}
