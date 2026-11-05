// The Gaussian: three box passes along the rows, then three along the
// columns, by box.wgsl's law (gpu-canonical-store ⑦, 관제 11-05 12:19: the
// fx Gaussian goes by C's `qa_blur_box`, the blur brush's passes — one blur
// law, not two). How its passes read and put the picture, however they are
// dispatched: a pass a dispatch (gaussian_pass.wgsl) or a way's three in one
// (gaussian_three.wgsl).
//
// Needs held.wgsl and box.wgsl before it.

// How a read past [edge_first, edge_end) along a pass is taken: as it is;
// as nothing; as the nearest pixel inside.
const BLUR_EDGE_NONE: u32 = 0u;
const BLUR_EDGE_NOTHING: u32 = 1u;
const BLUR_EDGE_REPEAT: u32 = 2u;

// The pixel `pass_` reads at `p` along `line`, by its edge.
fn gaussian_read(pass_: BoxPass, line: i32, p: i32) -> vec4<u32> {
  var at = p;
  if (pass_.edge != BLUR_EDGE_NONE && (p < pass_.edge_first || p >= pass_.edge_end)) {
    if (pass_.edge == BLUR_EDGE_NOTHING) {
      return vec4<u32>(0u);
    }
    at = clamp(p, pass_.edge_first, pass_.edge_end - 1);
  }
  if (pass_.down == 1u) {
    return held_read(line, at);
  }
  return held_read(at, line);
}

// Puts `pass_`'s pixel at `p` along `line`.
fn gaussian_write(pass_: BoxPass, line: i32, p: i32, pixel: vec4<u32>) {
  if (pass_.down == 1u) {
    held_write(line, p, pixel);
  } else {
    held_write(p, line, pixel);
  }
}
