// A chain's tiles as the plug-in's passes read them: straight RGBA, red
// the low byte, tile after tile, `params.stride` tiles a row — as
// `Composite::run` leaves them. Needs tile.wgsl before it.
//
// ↩️Till 2026-11-17 the export's passes read a run's output tiles by this
// file too, beside a frame as the screen shows it (export's
// frame_shown.wgsl); no call of the app's handed them tiles after
// 4f10d408f, and that read went (card
// the-export-s-tile-entries-have-no-caller).
//
// A pass binds the tiles it reads from the word `params.frame_base`,
// taken off every read here.

@group(0) @binding(1) var<storage, read> frame: array<u32>;

// Pixel (x, y)'s word in those tiles.
fn frame_word(columns: u32, x: u32, y: u32) -> u32 {
  return ((y / TILE_SIDE) * columns + x / TILE_SIDE) * TILE_TEXELS + tile_texel(x, y);
}

fn frame_straight(x: u32, y: u32) -> u32 {
  return frame[frame_word(params.stride, x, y) - params.frame_base];
}
