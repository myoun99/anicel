// A tile — of the pool, of a row's picture, of the composite's output — is
// 128 pixels a side, rows of 128, one straight RGBA8 pixel a word, red in
// the low byte (1a ①, gpu-canonical-store).

const TILE_SIDE: u32 = 128u;
const TILE_TEXELS: u32 = 16384u;

// Pixel (x, y)'s word within its tile, x and y counted from the corner of
// any tile.
fn tile_texel(x: u32, y: u32) -> u32 {
  return (y % TILE_SIDE) * TILE_SIDE + x % TILE_SIDE;
}
