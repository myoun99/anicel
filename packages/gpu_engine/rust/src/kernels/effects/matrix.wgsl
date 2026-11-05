// A colour matrix over one straight pixel (gpu-canonical-store ⑥): fx
// Brightness & Contrast and Hue/Saturation and an onion skin's tint, which
// the app folds into one 4×5 matrix (`core/color_matrix.dart`) and Flutter's
// `ColorFilter.matrix` runs in floating point. Each channel is its row of
// the matrix over the pixel's four bytes plus the row's translation,
// clamped to a byte. The pixel is straight, so Impeller's unpremultiply
// before and premultiply after fall away; a pixel the matrix leaves no
// alpha keeps the colour its rows give, as a key leaves one (key.wgsl) —
// what lays it premultiplies.
//
// ⛔NO MATRIX IS DEFINED HERE — the app makes it from its effects; this
// runs it. A matrix is twenty words its host reads through
//   fn matrix_word(at: u32) -> u32
// row after row as `ColorFilter.matrix` lists them: a row's four
// multipliers, then its translation in 0…255 units, each q(·, 16) as an
// i32's bits and below 2^15 in magnitude (effects/mod.rs's `matrix_words`).
//
// A channel is clamp(rnd(Σ M·c + T, 16), 0, 255), exact in i32 alone (the
// integer spec, gpu-canonical-store 11-06 07:31): with M = H·2^16 + L, H the
// arithmetic shift and L the low half in [0, 2^16), the sum is
// 2^16·(Σ H·c + T_H) + (Σ L·c + T_L), so its rnd is
// (Σ H·c + T_H) + ((Σ L·c + T_L + 2^15) >> 16) — each sum below 2^26,
// where the products whole would pass 2^31.

const MATRIX_ROW_WORDS: u32 = 5u;

// The matrix at `at` over a straight RGBA8 word (A<<24|B<<16|G<<8|R).
fn matrix_rgba8(at: u32, texel: u32) -> u32 {
  // The pixel's bytes, then the 1 a row's translation multiplies.
  var bytes = array<u32, 5>(
    texel & 0xffu, (texel >> 8u) & 0xffu, (texel >> 16u) & 0xffu, texel >> 24u, 1u,
  );
  var word = 0u;
  for (var row = 0u; row < 4u; row += 1u) {
    var whole = 0i;
    var part = 0u;
    for (var column = 0u; column < MATRIX_ROW_WORDS; column += 1u) {
      let m = matrix_word(at + row * MATRIX_ROW_WORDS + column);
      whole += (bitcast<i32>(m) >> 16u) * i32(bytes[column]);
      part += (m & 0xffffu) * bytes[column];
    }
    let channel = clamp(whole + i32((part + 0x8000u) >> 16u), 0, 255);
    word |= u32(channel) << (row * 8u);
  }
  return word;
}
