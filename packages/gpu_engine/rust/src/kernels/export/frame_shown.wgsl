// The picture an export converts, as the screen shows it (gpu-export-path
// ①⑴): a surface's texels copied row after row, `params.stride` words from
// one row to the next (`Shown`, mod.rs) — premultiplied, as every surface
// the app shows is (premultiply.wgsl), red the low byte, or blue where the
// surface is laid BGRA (`FRAME_BGRA`, set where the pass is compiled).
// The three reads frame.wgsl gives for a run's tiles, on these rows.

override FRAME_BGRA: bool = false;

@group(0) @binding(1) var<storage, read> frame: array<u32>;

fn frame_premultiplied(x: u32, y: u32) -> u32 {
  let word = frame[y * params.stride + x];
  if (!FRAME_BGRA) {
    return word;
  }
  return (word & 0xff00ff00u) | ((word >> 16u) & 0xffu) | ((word & 0xffu) << 16u);
}

fn frame_alpha(x: u32, y: u32) -> u32 {
  return frame[y * params.stride + x] >> 24u;
}

// The premultiplied pixel made straight: each colour byte times 255 over
// its alpha, rounded half up and at most 255 — what a writer that keeps
// the alpha takes. ⚠️The engine's own law (저장 2026-11-11): the app had
// none to keep — it asked Flutter for straight bytes (`rawStraightRgba`,
// still_image_encoders.dart), whose division is the device's — and the
// user asked the files to agree with each other, not with the old ones
// (11-08 「바뀌고 나서만 동일하면되」). Integers only, so every device gives
// one byte (fill.wgsl). Alpha 255 gives the word back; alpha 0, nothing.
fn frame_straight(x: u32, y: u32) -> u32 {
  let word = frame_premultiplied(x, y);
  let alpha = word >> 24u;
  if (alpha == 255u) {
    return word;
  }
  if (alpha == 0u) {
    return 0u;
  }
  var straight = alpha << 24u;
  for (var shift = 0u; shift < 24u; shift += 8u) {
    let colour = (word >> shift) & 0xffu;
    straight |= min((colour * 255u + alpha / 2u) / alpha, 255u) << shift;
  }
  return straight;
}
