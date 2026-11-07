// The blur brush's box law (C's `qa_blur_box`, I-75 흐리기): each pixel of
// a pass the mean of the `radius` pixels either side of it and itself,
// rounded half up, on the premultiplied 16-bit scale. The order and the
// rounding of every pass are part of the law (BrushBlurPicture has its
// reasons); which pixels each pass writes is boxes.rs's `passes`.
//
// Written once for both schedules (gpu-canonical-store 01:13, 01:15 (b)):
// a pass a dispatch (pass.wgsl), and three passes a dispatch over strips in
// workgroup memory (three.wgsl), over a dab's window. Each brings its own
// `blur_tap` — the pixel at `p` along `line` — and `blur_put`.

// One pass: along the rows (down 0) or the columns (down 1), the pixels it
// writes — [first, end) along, lines [line_first, line_end) across.
struct BoxPass {
  down: u32,
  radius: u32,
  first: i32,
  end: i32,
  line_first: i32,
  line_end: i32,
}

// A pass from its words, in the order above (boxes.rs's `Pass::words`).
fn box_pass(words: array<u32, 6>) -> BoxPass {
  return BoxPass(
    words[0],
    words[1],
    bitcast<i32>(words[2]),
    bitcast<i32>(words[3]),
    bitcast<i32>(words[4]),
    bitcast<i32>(words[5]),
  );
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
