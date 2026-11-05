// A straight RGBA8 word premultiplied, as Flutter reads a surface it shows
// (its embedder wraps an external texture premultiplied — Skia's road says
// so, Impeller holds no other kind). The app's one premultiply
// (core/rgba_premultiply.dart, qa_engine.c's qa_premultiply_pixel), which
// every upload of a picture to the screen runs: each colour byte times the
// alpha over 255, rounded as Skia's SkMulDiv255Round rounds it, so a byte
// the GPU shows is the byte the app showed. Alpha 255 gives the word back,
// alpha 0 gives nothing; the sum stays under 2^16.

fn premultiply8(word: u32) -> u32 {
  let alpha = word >> 24u;
  var premultiplied = alpha << 24u;
  for (var shift = 0u; shift < 24u; shift += 8u) {
    let product = ((word >> shift) & 0xffu) * alpha + 128u;
    premultiplied |= ((product + (product >> 8u)) >> 8u) << shift;
  }
  return premultiplied;
}
