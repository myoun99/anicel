// The box law of every blur that passes boxes (gpu-canonical-store ⑦, 관제
// 11-05 12:19: the fx Gaussian goes by C's `qa_blur_box`, the blur brush's
// passes — one blur law, not two): each pixel of a pass the mean of the
// `radius` pixels either side of it and itself, rounded half up, on
// held.wgsl's premultiplied scale. The order and the rounding of every pass
// are part of the law (BrushBlurPicture has its reasons); which pixels each
// pass writes is gaussian.rs's `passes`.
//
// Written once for both schedules (gpu-canonical-store 01:13): the fx
// Gaussian's, a pass a dispatch over a whole picture (gaussian.wgsl), and
// the blur brush's, three passes a dispatch in workgroup memory over a
// dab's window (kernels/dab/blur.wgsl). Each brings its own `blur_tap` —
// the pixel at `p` along `line` — and `blur_put`.

// One pass: along the rows (down 0) or the columns (down 1), the pixels it
// writes — [first, end) along, lines [line_first, line_end) across — and
// its edge (gaussian.wgsl's; a brush pass reads as it is).
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

// round(sum / count), a half up: C's (2·sum + count) / (2·count), without
// the doubled sum a u32 could not hold.
fn blur_mean(sum: u32, count: u32) -> u32 {
  return sum / count + select(0u, 1u, (sum % count) * 2u >= count);
}

// The pass's pixels [start, stop) along `line`, by one sum slid along them,
// as C's pass slides one along the whole line: a sum of integers is the
// same however it was gathered, so any cut of a line into runs puts what
// one run along all of it would.
fn blur_slide(line: i32, start: i32, stop: i32, radius: u32) {
  let r = i32(radius);
  let count = radius * 2u + 1u;
  var sum = vec4<u32>(0u);
  for (var p = start - r; p <= start + r; p++) {
    sum += blur_tap(line, p);
  }
  for (var p = start; p < stop; p++) {
    blur_put(line, p, vec4<u32>(
      blur_mean(sum.x, count),
      blur_mean(sum.y, count),
      blur_mean(sum.z, count),
      blur_mean(sum.w, count),
    ));
    if (p + 1 < stop) {
      sum = sum + blur_tap(line, p + r + 1) - blur_tap(line, p - r);
    }
  }
}
