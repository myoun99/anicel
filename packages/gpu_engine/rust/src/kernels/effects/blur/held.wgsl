// What a blur's passes share — the Gaussian's (gaussian.wgsl) and a blur
// along a way's (line.wgsl): where a pass reads and puts a pixel, the
// grid's tiles, straight RGBA8, or a plane of two words a pixel, 16 bits a
// channel; and the pixel between them, premultiplied on the 16-bit scale —
// read from a stored word and stored back as every blur reads and stores
// one (blend.wgsl's blend_unpack8_premultiplied and
// blend_pack8_premultiplied, C's qa_blur_premultiplied and
// qa_blur_result_tile).
//
// Needs shared/isqrt.wgsl, blend/blend.wgsl and shared/tile.wgsl before it.
// The pass that follows binds 3 and up.

// Where a pass's source and target hold the pixel at (x, y): the grid's
// tiles (1) or a plane whose top-left pixel is (x0, y0), `width` pixels a
// row. The grid's top-left is a pixel, its size in tiles.
struct Held {
  source_tiles: u32,
  source_x0: i32,
  source_y0: i32,
  source_width: u32,
  target_tiles: u32,
  target_x0: i32,
  target_y0: i32,
  target_width: u32,
  grid_x0: i32,
  grid_y0: i32,
  grid_columns: u32,
  grid_rows: u32,
}

@group(0) @binding(0) var<uniform> held: Held;
@group(0) @binding(1) var<storage, read> pixels_in: array<u32>;
@group(0) @binding(2) var<storage, read_write> pixels_out: array<u32>;

// Where pixel (x, y) is among the grid's tiles — tile after tile, rows of
// them — or none past the grid.
fn held_tile_word(x: i32, y: i32) -> i32 {
  let lx = x - held.grid_x0;
  let ly = y - held.grid_y0;
  if (lx < 0 || ly < 0 || u32(lx) >= held.grid_columns * TILE_SIDE
      || u32(ly) >= held.grid_rows * TILE_SIDE) {
    return -1;
  }
  let tile = (u32(ly) / TILE_SIDE) * held.grid_columns + u32(lx) / TILE_SIDE;
  return i32(tile * TILE_TEXELS + tile_texel(u32(lx), u32(ly)));
}

// Where pixel (x, y) begins in a plane of `words` words a pixel.
fn held_plane_word(x: i32, y: i32, x0: i32, y0: i32, width: u32, words: u32) -> u32 {
  return (u32(y - y0) * width + u32(x - x0)) * words;
}

// The source's pixel (x, y), premultiplied on the 16-bit scale.
fn held_read(x: i32, y: i32) -> vec4<u32> {
  if (held.source_tiles == 1u) {
    let at = held_tile_word(x, y);
    // Past the grid, nothing — by this line: a read past a buffer gives what
    // the device likes (WGSL), 0 on the Surface's DX12, so no test there
    // tells this line from its absence (mutant b11, 11-05).
    if (at < 0) {
      return vec4<u32>(0u);
    }
    return blend_unpack8_premultiplied(pixels_in[at]);
  }
  let at = held_plane_word(x, y, held.source_x0, held.source_y0, held.source_width, 2u);
  return blend_unpack16(vec2<u32>(pixels_in[at], pixels_in[at + 1u]));
}

// Puts `pixel` at (x, y) in the target — stored, among the tiles.
fn held_write(x: i32, y: i32, pixel: vec4<u32>) {
  if (held.target_tiles == 1u) {
    pixels_out[held_tile_word(x, y)] = blend_pack8_premultiplied(pixel);
    return;
  }
  let at = held_plane_word(x, y, held.target_x0, held.target_y0, held.target_width, 2u);
  let pair = blend_pack16(pixel);
  pixels_out[at] = pair.x;
  pixels_out[at + 1u] = pair.y;
}
