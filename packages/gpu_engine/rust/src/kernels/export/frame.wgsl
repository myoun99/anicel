// The picture an export converts: the composite's output tiles for its
// frame, asked row by row from the frame's top-left tile, `columns` tiles
// a row — tile after tile, as `Composite::run` leaves them. Needs
// tile.wgsl before it.

// Pixel (x, y) of the frame's word in those tiles.
fn frame_word(columns: u32, x: u32, y: u32) -> u32 {
  return ((y / TILE_SIDE) * columns + x / TILE_SIDE) * TILE_TEXELS + tile_texel(x, y);
}
