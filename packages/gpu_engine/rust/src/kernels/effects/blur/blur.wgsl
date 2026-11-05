// The Gaussian's integer law (gpu-canonical-store ⑦, 관제 11-05 12:19: the
// fx Gaussian goes by C's `qa_blur_box`, the blur brush's passes — one blur
// law, not two): three box passes along the rows, then three along the
// columns, each pixel of a pass the mean of the `radius` pixels either side
// of it and itself, rounded half up, on the 16-bit premultiplied scale — so
// a transparent pixel carries no colour into its neighbours. The order and
// the rounding of every pass are part of the law (BrushBlurPicture has its
// reasons).
//
// One dispatch is one pass. A thread takes a run of BLUR_RUN pixels of a
// line and slides one sum along it, as C's pass slides one along the whole
// line: a sum of integers is the same however it was gathered.
//
// Needs shared/isqrt.wgsl, blend/blend.wgsl and shared/tile.wgsl before it.

const BLUR_RUN: u32 = 64u;

// How a read past [edge_first, edge_end) along a pass is taken: as it is;
// as nothing; as the nearest pixel inside.
const BLUR_EDGE_NONE: u32 = 0u;
const BLUR_EDGE_NOTHING: u32 = 1u;
const BLUR_EDGE_REPEAT: u32 = 2u;

// One pass: along the rows (down 0) or the columns (down 1), the pixels it
// writes — [first, end) along, lines [line_first, line_end) across — its
// edge, and where its source and target hold the pixel at (x, y): the
// grid's tiles (1) or a plane whose top-left pixel is (x0, y0), `width`
// pixels a row. The grid's top-left is a pixel, its size in tiles.
struct BlurPass {
  down: u32,
  radius: u32,
  first: i32,
  end: i32,
  line_first: i32,
  line_end: i32,
  edge: u32,
  edge_first: i32,
  edge_end: i32,
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

@group(0) @binding(0) var<uniform> pass_: BlurPass;
// Straight RGBA8 tiles, or a plane: two words a pixel, 16 bits a channel.
@group(0) @binding(1) var<storage, read> pixels_in: array<u32>;
@group(0) @binding(2) var<storage, read_write> pixels_out: array<u32>;

// Where pixel (x, y) is among the grid's tiles — tile after tile, rows of
// them — or none past the grid.
fn blur_tile_word(x: i32, y: i32) -> i32 {
  let lx = x - pass_.grid_x0;
  let ly = y - pass_.grid_y0;
  if (lx < 0 || ly < 0 || u32(lx) >= pass_.grid_columns * TILE_SIDE
      || u32(ly) >= pass_.grid_rows * TILE_SIDE) {
    return -1;
  }
  let tile = (u32(ly) / TILE_SIDE) * pass_.grid_columns + u32(lx) / TILE_SIDE;
  return i32(tile * TILE_TEXELS + tile_texel(u32(lx), u32(ly)));
}

fn blur_plane_word(x: i32, y: i32, x0: i32, y0: i32, width: u32) -> u32 {
  return (u32(y - y0) * width + u32(x - x0)) * 2u;
}

// The source's pixel (x, y), premultiplied on the 16-bit scale: a stored
// word's channel × alpha, rounded — C's qa_blur_premultiplied is
// round(c·a·257 / 255), which is blend_mul(c·257, a·257) exactly.
fn blur_read(x: i32, y: i32) -> vec4<u32> {
  if (pass_.source_tiles == 1u) {
    let at = blur_tile_word(x, y);
    // Past the grid, nothing — by this line: a read past a buffer gives what
    // the device likes (WGSL), 0 on the Surface's DX12, so no test there
    // tells this line from its absence (mutant b11, 11-05).
    if (at < 0) {
      return vec4<u32>(0u);
    }
    let pixel = blend_unpack8(pixels_in[at]);
    return vec4<u32>(
      blend_mul(pixel.x, pixel.w),
      blend_mul(pixel.y, pixel.w),
      blend_mul(pixel.z, pixel.w),
      pixel.w,
    );
  }
  let at = blur_plane_word(x, y, pass_.source_x0, pass_.source_y0, pass_.source_width);
  let rg = pixels_in[at];
  let ba = pixels_in[at + 1u];
  return vec4<u32>(rg & 0xffffu, rg >> 16u, ba & 0xffffu, ba >> 16u);
}

// The pixel at `p` along `line`, by the pass's edge.
fn blur_tap(line: i32, p: i32) -> vec4<u32> {
  var at = p;
  if (pass_.edge != BLUR_EDGE_NONE && (p < pass_.edge_first || p >= pass_.edge_end)) {
    if (pass_.edge == BLUR_EDGE_NOTHING) {
      return vec4<u32>(0u);
    }
    at = clamp(p, pass_.edge_first, pass_.edge_end - 1);
  }
  if (pass_.down == 1u) {
    return blur_read(line, at);
  }
  return blur_read(at, line);
}

// round(sum / count), a half up: C's (2·sum + count) / (2·count), without
// the doubled sum a u32 could not hold.
fn blur_mean(sum: u32, count: u32) -> u32 {
  return sum / count + select(0u, 1u, (sum % count) * 2u >= count);
}

// A blurred pixel as it is stored: its alpha rounded to a byte, each
// channel over that alpha rounded once — C's qa_blur_result_tile — and
// nothing where the alpha rounds to none.
fn blur_stored(pixel: vec4<u32>) -> u32 {
  let alpha = blend_to8(pixel.w);
  if (alpha == 0u) {
    return 0u;
  }
  return blend_over_alpha(pixel.x * 255u, pixel.w)
    | (blend_over_alpha(pixel.y * 255u, pixel.w) << 8u)
    | (blend_over_alpha(pixel.z * 255u, pixel.w) << 16u)
    | (alpha << 24u);
}

fn blur_write(line: i32, p: i32, pixel: vec4<u32>) {
  let x = select(p, line, pass_.down == 1u);
  let y = select(line, p, pass_.down == 1u);
  if (pass_.target_tiles == 1u) {
    pixels_out[blur_tile_word(x, y)] = blur_stored(pixel);
    return;
  }
  let at = blur_plane_word(x, y, pass_.target_x0, pass_.target_y0, pass_.target_width);
  pixels_out[at] = pixel.x | (pixel.y << 16u);
  pixels_out[at + 1u] = pixel.z | (pixel.w << 16u);
}

@compute @workgroup_size(8, 8, 1)
fn blur(@builtin(global_invocation_id) id: vec3<u32>) {
  let line = pass_.line_first + i32(id.y);
  let start = pass_.first + i32(id.x * BLUR_RUN);
  if (line >= pass_.line_end || start >= pass_.end) {
    return;
  }
  let stop = min(start + i32(BLUR_RUN), pass_.end);
  let r = i32(pass_.radius);
  let count = pass_.radius * 2u + 1u;
  var sum = vec4<u32>(0u);
  for (var p = start - r; p <= start + r; p++) {
    sum += blur_tap(line, p);
  }
  for (var p = start; p < stop; p++) {
    blur_write(line, p, vec4<u32>(
      blur_mean(sum.x, count),
      blur_mean(sum.y, count),
      blur_mean(sum.z, count),
      blur_mean(sum.w, count),
    ));
    if (p + 1 < stop) {
      sum = sum + blur_tap(line, p + r + 1) - blur_tap(line, p - r);
    }
  }
}
