// The composite's pixels as output tiles: each in `work` past the stack,
// straight as every engine pixel is, until mod.rs copies them out — and
// nothing outside the output's pixels, as a canvas's picture ends at the
// canvas while its tiles reach on to their 128th pixel.

fn put(tile: u32, texel: u32, x: i32, y: i32, inside: bool, word: u32) {
  work[pass_.out_at + tile * TILE_TEXELS + texel] = select(0u, word, inside);
}
