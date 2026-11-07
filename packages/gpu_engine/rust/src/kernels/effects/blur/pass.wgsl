// A box pass a dispatch (gpu-canonical-store 01:13 ③): a thread takes a
// run of BLUR_RUN pixels of a line and slides one sum along it (box.wgsl's
// `blur_slide`). The blur brush goes so past its strips' widest box
// (kernels/dab/blur_pass.wgsl) — where three passes' halo leaves a strip
// too few pixels to put (three.wgsl).
//
// Needs box.wgsl before it, and from what includes it `blur_tap` and
// `blur_put`.

const BLUR_RUN: u32 = 64u;

// The run of `pass_` thread `id` takes: line `id.y`, run `id.x` along.
fn blur_run(pass_: BoxPass, id: vec3<u32>) {
  let line = pass_.line_first + i32(id.y);
  let start = pass_.first + i32(id.x * BLUR_RUN);
  // A thread whose run starts past the pass's end would only read, 2r + 1
  // taps put nowhere: no test tells this half of the guard from its absence
  // (mutant q02, 11-06), only the time it saves.
  if (line >= pass_.line_end || start >= pass_.end) {
    return;
  }
  blur_slide(line, start, min(start + i32(BLUR_RUN), pass_.end), pass_.radius);
}
