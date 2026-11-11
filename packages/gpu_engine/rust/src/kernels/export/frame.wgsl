// The picture an export converts, as a run left it: the composite's output
// tiles for its frame — straight RGBA, red the low byte — asked row by row
// from the frame's top-left tile, `params.stride` tiles a row — tile after
// tile, as `Composite::run` leaves them. Needs tile.wgsl and
// premultiply.wgsl before it.
//
// A pass reads its picture through the three reads below alone, which
// frame_shown.wgsl gives for a frame as the screen shows it: what each
// pass makes of a pixel is one law whichever picture it is handed.

@group(0) @binding(1) var<storage, read> frame: array<u32>;

// Pixel (x, y) of the frame's word in those tiles.
fn frame_word(columns: u32, x: u32, y: u32) -> u32 {
  return ((y / TILE_SIDE) * columns + x / TILE_SIDE) * TILE_TEXELS + tile_texel(x, y);
}

fn frame_straight(x: u32, y: u32) -> u32 {
  return frame[frame_word(params.stride, x, y)];
}

fn frame_premultiplied(x: u32, y: u32) -> u32 {
  return premultiply8(frame_straight(x, y));
}

fn frame_alpha(x: u32, y: u32) -> u32 {
  return frame_straight(x, y) >> 24u;
}
