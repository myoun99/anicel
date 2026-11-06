// A bucket fill's reach (gpu-canonical-store stage 5): the pixels 4-joined
// to the seed through pixels whose four channels each lie within the
// tolerance of the seed's — the app's `pixelWithinTolerance`, qa_engine.c's
// `qa_tol_ok1`. Which pixels those are is one set however it is found, so
// these passes need not walk as the app's scanline stack walks to give its
// bytes: the seed, and every pixel a path of such pixels reaches.
//
// The picture is what the screen shows (유저 gpu-canonical-store-Q1,
// 11-06: 「화면과 똑같은 그림을 읽는다」): the composite's output tiles,
// straight RGBA8 words (A<<24|B<<16|G<<8|R), 128 × 128 a tile, the tiles of
// a grid row after row. Pixels compare premultiplied, as the screen shows
// them and as the app's raster held them.
//
// A plane of bits holds a pixel a bit, the leftmost in a word's lowest, a
// row `stride` words, over the same grid: a tile is four words of a row,
// 128 rows. Pixels outside the picture's box — a grid holds whole tiles —
// are 0 in what may fill, so nothing spreads there.
//
// Needs shared/premultiply.wgsl before it.

struct Flood {
  // The picture's box in the grid's pixels: left, top, right, bottom,
  // the last two past it.
  left: u32,
  top: u32,
  right: u32,
  bottom: u32,
  seed_x: u32,
  seed_y: u32,
  tolerance: u32,
  // Tiles across and down, and words a row of a plane: four a tile.
  across: u32,
  down: u32,
  stride: u32,
  unused_0: u32,
  unused_1: u32,
}

@group(0) @binding(0) var<uniform> flood: Flood;
// What may fill, and what has filled before a round and after it.
@group(0) @binding(1) var<storage, read> fillable: array<u32>;
@group(0) @binding(2) var<storage, read> filled_in: array<u32>;
@group(0) @binding(3) var<storage, read_write> filled_out: array<u32>;
// Set by a round that filled a pixel more.
@group(0) @binding(4) var<storage, read_write> moved: atomic<u32>;
// The picture's tiles.
@group(0) @binding(5) var<storage, read> picture: array<u32>;
@group(0) @binding(6) var<storage, read_write> fillable_out: array<u32>;
// The filled pixels' least and most x, then y.
@group(0) @binding(7) var<storage, read_write> bounds: array<atomic<u32>, 4>;

// The box a fill is finished in, in the grid's pixels — its right and
// bottom past it —, and the words a row of a plane of bits, and of the
// mask of bytes over the box (mask.wgsl's layout).
struct Crop {
  left: u32,
  top: u32,
  width: u32,
  height: u32,
  bits: u32,
  bytes: u32,
  unused_0: u32,
  unused_1: u32,
}

@group(0) @binding(8) var<uniform> crop: Crop;
@group(0) @binding(9) var<storage, read_write> mask_out: array<u32>;

const FLOOD_TILE: u32 = 128u;
const FLOOD_TILE_WORDS: u32 = 4u;

// Whether each of `pixel`'s four channels lies within the tolerance of
// `seed`'s.
fn flood_within(pixel: u32, seed: u32) -> bool {
  for (var shift = 0u; shift < 32u; shift += 8u) {
    let a = (pixel >> shift) & 0xffu;
    let b = (seed >> shift) & 0xffu;
    if (max(a, b) - min(a, b) > flood.tolerance) {
      return false;
    }
  }
  return true;
}

// The picture's pixel at (x, y) of the grid, premultiplied.
fn flood_pixel(x: u32, y: u32) -> u32 {
  let tile = (y / FLOOD_TILE) * flood.across + x / FLOOD_TILE;
  let texel = (y % FLOOD_TILE) * FLOOD_TILE + x % FLOOD_TILE;
  return premultiply8(picture[tile * FLOOD_TILE * FLOOD_TILE + texel]);
}

// A word of what may fill: 32 pixels of a row, those outside the box 0;
// and the seed, in a plane that holds nothing yet.
@compute @workgroup_size(8, 8, 1)
fn flood_tolerance(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= flood.stride || id.y >= flood.down * FLOOD_TILE) {
    return;
  }
  let seed = flood_pixel(flood.seed_x, flood.seed_y);
  var word = 0u;
  if (id.y >= flood.top && id.y < flood.bottom) {
    for (var k = 0u; k < 32u; k++) {
      let x = id.x * 32u + k;
      if (x >= flood.left && x < flood.right && flood_within(flood_pixel(x, id.y), seed)) {
        word |= 1u << k;
      }
    }
  }
  fillable_out[id.y * flood.stride + id.x] = word;
  // The seed fills first, whatever it reads as (the app's
  // `filled[seed] = 255` before its stack): the first round spreads from it.
  if (id.y == flood.seed_y && id.x == flood.seed_x / 32u) {
    filled_out[id.y * flood.stride + id.x] = 1u << (flood.seed_x % 32u);
  }
}

// A run's pixels from its seeds toward its higher bits: `fill` plus seeds
// within it carries through each run from its lowest seed to the run's
// end, and the run's bits that carry flipped are those pixels.
fn flood_up_bits(seeds: u32, fill: u32) -> u32 {
  return (((fill + seeds) ^ fill) & fill) | seeds;
}

// The same toward the lower bits.
fn flood_down_bits(seeds: u32, fill: u32) -> u32 {
  return reverseBits(flood_up_bits(reverseBits(seeds), reverseBits(fill)));
}

// A row's seeds spread along it through `fill`, word to word: each run the
// seeds touch, whole. Seeds lie in `fill` — the seed is within its own
// tolerance and in the box, and every other came through `fill` — so the
// carries see no bit past it (mutants f15 · f16, 11-06).
fn flood_along(seeds: vec4<u32>, fill: vec4<u32>) -> vec4<u32> {
  let r0 = flood_up_bits(seeds.x, fill.x);
  let r1 = flood_up_bits(seeds.y | ((r0 >> 31u) & fill.y), fill.y);
  let r2 = flood_up_bits(seeds.z | ((r1 >> 31u) & fill.z), fill.z);
  let r3 = flood_up_bits(seeds.w | ((r2 >> 31u) & fill.w), fill.w);
  let l3 = flood_down_bits(seeds.w, fill.w);
  let l2 = flood_down_bits(seeds.z | ((l3 << 31u) & fill.z), fill.z);
  let l1 = flood_down_bits(seeds.y | ((l2 << 31u) & fill.y), fill.y);
  let l0 = flood_down_bits(seeds.x | ((l1 << 31u) & fill.x), fill.x);
  return vec4<u32>(r0 | l0, r1 | l1, r2 | l2, r3 | l3);
}

fn flood_fillable_row(at: u32) -> vec4<u32> {
  return vec4<u32>(fillable[at], fillable[at + 1u], fillable[at + 2u], fillable[at + 3u]);
}

fn flood_filled_row(at: u32) -> vec4<u32> {
  return vec4<u32>(filled_in[at], filled_in[at + 1u], filled_in[at + 2u], filled_in[at + 3u]);
}

var<workgroup> tile_fill: array<vec4<u32>, 128>;
var<workgroup> tile_seen: array<vec4<u32>, 128>;
var<workgroup> tile_moved: atomic<u32>;
var<workgroup> tile_again: u32;

// A round over a tile, a thread a row: what filled before, and what its
// neighbours across the tile's sides had filled, spread through the tile
// until nothing in it moves. Rounds run until one moves nothing anywhere;
// each reads one plane and puts the other, so no tile reads what another
// put in the same round.
@compute @workgroup_size(128, 1, 1)
fn flood_round(
  @builtin(workgroup_id) tile: vec3<u32>,
  @builtin(local_invocation_index) r: u32,
) {
  let at = (tile.y * FLOOD_TILE + r) * flood.stride + tile.x * FLOOD_TILE_WORDS;
  let fill = flood_fillable_row(at);
  let before = flood_filled_row(at);
  var seeds = before;
  if (tile.x > 0u) {
    seeds.x |= (filled_in[at - 1u] >> 31u) & fill.x;
  }
  if (tile.x + 1u < flood.across) {
    seeds.w |= (filled_in[at + FLOOD_TILE_WORDS] << 31u) & fill.w;
  }
  if (r == 0u && tile.y > 0u) {
    seeds |= flood_filled_row(at - flood.stride) & fill;
  }
  if (r + 1u == FLOOD_TILE && tile.y + 1u < flood.down) {
    seeds |= flood_filled_row(at + flood.stride) & fill;
  }
  var seen = flood_along(seeds, fill);
  tile_fill[r] = fill;
  tile_seen[r] = seen;
  loop {
    if (r == 0u) {
      atomicStore(&tile_moved, 0u);
    }
    workgroupBarrier();
    var above = vec4<u32>(0u);
    var below = vec4<u32>(0u);
    if (r > 0u) {
      above = tile_seen[r - 1u];
    }
    if (r + 1u < FLOOD_TILE) {
      below = tile_seen[r + 1u];
    }
    let grown = flood_along(seen | ((above | below) & fill), fill);
    workgroupBarrier();
    if (any(grown != seen)) {
      seen = grown;
      tile_seen[r] = seen;
      atomicStore(&tile_moved, 1u);
    }
    workgroupBarrier();
    if (r == 0u) {
      tile_again = atomicLoad(&tile_moved);
    }
    if (workgroupUniformLoad(&tile_again) == 0u) {
      break;
    }
  }
  filled_out[at] = seen.x;
  filled_out[at + 1u] = seen.y;
  filled_out[at + 2u] = seen.z;
  filled_out[at + 3u] = seen.w;
  if (any(seen != before)) {
    atomicStore(&moved, 1u);
  }
}

var<workgroup> tile_box: array<atomic<u32>, 4>;

// The filled pixels' box over a tile, a thread a row, folded into
// `bounds` — which starts at nothing: the least at the most a word holds,
// the most at 0.
@compute @workgroup_size(128, 1, 1)
fn flood_bounds(
  @builtin(workgroup_id) tile: vec3<u32>,
  @builtin(local_invocation_index) r: u32,
) {
  if (r == 0u) {
    atomicStore(&tile_box[0], 0xffffffffu);
    atomicStore(&tile_box[1], 0u);
    atomicStore(&tile_box[2], 0xffffffffu);
    atomicStore(&tile_box[3], 0u);
  }
  workgroupBarrier();
  let y = tile.y * FLOOD_TILE + r;
  let seen = flood_filled_row(y * flood.stride + tile.x * FLOOD_TILE_WORDS);
  if (any(seen != vec4<u32>(0u))) {
    var first = 96u + countTrailingZeros(seen.w);
    if (seen.z != 0u) {
      first = 64u + countTrailingZeros(seen.z);
    }
    if (seen.y != 0u) {
      first = 32u + countTrailingZeros(seen.y);
    }
    if (seen.x != 0u) {
      first = countTrailingZeros(seen.x);
    }
    var last = 31u - countLeadingZeros(seen.x);
    if (seen.y != 0u) {
      last = 63u - countLeadingZeros(seen.y);
    }
    if (seen.z != 0u) {
      last = 95u - countLeadingZeros(seen.z);
    }
    if (seen.w != 0u) {
      last = 127u - countLeadingZeros(seen.w);
    }
    let x0 = tile.x * FLOOD_TILE;
    atomicMin(&tile_box[0], x0 + first);
    atomicMax(&tile_box[1], x0 + last);
    atomicMin(&tile_box[2], y);
    atomicMax(&tile_box[3], y);
  }
  workgroupBarrier();
  if (r == 0u && atomicLoad(&tile_box[0]) != 0xffffffffu) {
    atomicMin(&bounds[0], atomicLoad(&tile_box[0]));
    atomicMax(&bounds[1], atomicLoad(&tile_box[1]));
    atomicMin(&bounds[2], atomicLoad(&tile_box[2]));
    atomicMax(&bounds[3], atomicLoad(&tile_box[3]));
  }
}

// A word of the mask a fill is finished from: four of the box's pixels,
// 255 where the flood filled and 0 where it did not — the app's `filled`
// cropped (`_cropAndFinishFloodRegion`).
@compute @workgroup_size(8, 8, 1)
fn flood_mask(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= crop.bytes || id.y >= crop.height) {
    return;
  }
  let y = crop.top + id.y;
  var word = 0u;
  for (var k = 0u; k < 4u; k++) {
    let x = id.x * 4u + k;
    // Past the box's last column, where the row's last word is not full,
    // what it put would land in the row's padding, which no pass reads —
    // so the stop is for its work alone (mutant m09, 11-06: equivalent).
    if (x >= crop.width) {
      break;
    }
    let at = crop.left + x;
    let bit = (filled_in[y * crop.bits + at / 32u] >> (at % 32u)) & 1u;
    word |= (bit * 255u) << (k * 8u);
  }
  mask_out[id.y * crop.bytes + id.x] = word;
}
