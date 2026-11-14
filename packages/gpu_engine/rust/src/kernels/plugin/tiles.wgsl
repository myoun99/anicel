// A plug-in's pictures between a chain's tiles and the plug-in's rows
// (a-plugin-step-goes-through-the-cpu-and-back): a chain holds a picture
// tile after tile over its rectangle, row by row of tiles (frame.wgsl's
// read), and a plug-in reads and writes one row after row (fx_wgsl's
// prelude.wgsl) — a pass each way on the device, so neither the plug-in's
// spec nor its CPU run knows of tiles, and no picture leaves the GPU.
// Needs tile.wgsl, premultiply.wgsl and frame.wgsl before it.

struct Params {
  // The tiles' step from one row of tiles to the next (frame.wgsl's).
  stride: u32,
  // Their rows of tiles.
  tile_rows: u32,
  // The picture's top-left pixel from the tiles' top-left, and its size.
  left: i32,
  top: i32,
  width: u32,
  height: u32,
  // The picture's first word in `rows`: its plane's among a plug-in's
  // layers, one after another.
  first: u32,
  pad0: u32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(2) var<storage, read_write> rows: array<u32>;
@group(0) @binding(3) var<storage, read_write> tiles: array<u32>;

// Whether pixel (x, y), from the tiles' top-left, lies in them.
fn in_the_tiles(x: i32, y: i32) -> bool {
  return x >= 0 && y >= 0 && u32(x) < params.stride * TILE_SIDE
    && u32(y) < params.tile_rows * TILE_SIDE;
}

// The picture's pixels from the tiles, row after row: clear past them, as
// the chain's read answered there (`ChainRead::pixels`).
@compute @workgroup_size(16, 16)
fn plugin_rows_of_tiles(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= params.width || id.y >= params.height) {
    return;
  }
  let x = params.left + i32(id.x);
  let y = params.top + i32(id.y);
  var word = 0u;
  if (in_the_tiles(x, y)) {
    word = frame_straight(u32(x), u32(y));
  }
  rows[params.first + id.y * params.width + id.x] = word;
}

// The tiles holding the picture's pixels, clear past it, as a chain puts
// what a plug-in made in place of what it read (`Op::Put`). A pixel no
// alpha shows is (0,0,0,0) whatever colour the plug-in gave it — as a
// landing packs one (blend.wgsl's `blend_pack8`) and the app's decoders
// hand one back (`zeroFullyClearPixels`).
@compute @workgroup_size(16, 16)
fn plugin_tiles_of_rows(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= params.stride * TILE_SIDE || id.y >= params.tile_rows * TILE_SIDE) {
    return;
  }
  let x = i32(id.x) - params.left;
  let y = i32(id.y) - params.top;
  var word = 0u;
  if (x >= 0 && y >= 0 && u32(x) < params.width && u32(y) < params.height) {
    let drawn = rows[params.first + u32(y) * params.width + u32(x)];
    word = select(drawn, 0u, (drawn >> 24u) == 0u);
  }
  tiles[frame_word(params.stride, id.x, id.y)] = word;
}
