// A straight RGBA8 word premultiplied, as Flutter reads a surface it shows
// (its embedder wraps an external texture premultiplied — Skia's road says
// so, Impeller holds no other kind). The app's one premultiply
// (core/rgba_premultiply.dart; native/premultiply spells it for a tile), which
// every upload of a picture to the screen runs: each colour byte times the
// alpha over 255, rounded as Skia's SkMulDiv255Round rounds it, so a byte
// the GPU shows is the byte the app showed. Alpha 255 gives the word back,
// alpha 0 gives nothing; the sum stays under 2^16.
//
// The rounding is `div255_round`, which the cel pixel pass's blend (the
// app's `_blend`) and the lift's partial alpha (`gatherMaskedSurfacePixels`)
// take too — one spelling of it (`one_premultiply.rs`).

// `t` over 255, rounded as SkMulDiv255Round rounds a product of two bytes;
// `t` is at most 255 · 255 (a product, or a blend's two that sum to one).
fn div255_round(t: u32) -> u32 {
  let rounded = t + 128u;
  return (rounded + (rounded >> 8u)) >> 8u;
}

fn premultiply8(word: u32) -> u32 {
  let alpha = word >> 24u;
  var premultiplied = alpha << 24u;
  for (var shift = 0u; shift < 24u; shift += 8u) {
    premultiplied |= div255_round(((word >> shift) & 0xffu) * alpha) << shift;
  }
  return premultiplied;
}
