// The row composite (gpu-canonical-store 2단계 ②③, round E1): one thread
// holds one output pixel and walks the plan's steps bottom to top, a stack
// of buffers in its registers — rows, folders and clipping groups, every
// one composited by the blend family on the 16-bit scale, with no rounding
// between rows. The pixel is rounded to a byte once, at the end.
//
// A walk the pages cannot all be bound for is cut into passes (mod.rs);
// between them the stack goes to `work` as it is, 16 bits a channel, so
// where the cuts fall changes no value.
//
// Needs shared/isqrt.wgsl, blend/blend.wgsl, shared/wide.wgsl and
// shared/resample.wgsl before it.

const TILE_TEXELS: u32 = 16384u;
const NO_TILE: u32 = 0xffffffffu;
const DEPTH: u32 = 8u;
const STEP_WORDS: u32 = 11u;

const STEP_ROW: u32 = 0u;
const STEP_OPEN: u32 = 1u;
const STEP_OPEN_OPAQUE: u32 = 2u;
const STEP_CLOSE: u32 = 3u;
const STEP_CLOSE_ATOP: u32 = 4u;

// One pass: the steps it runs, the stack depth it takes and leaves, the
// output tiles it covers, and where its table of pages is — which binding
// holds each page of the pool (mod.rs's NO_PAGE where it binds none).
struct Pass {
  step_begin: u32,
  step_end: u32,
  depth_in: u32,
  first: u32,
  last: u32,
  tiles_at: u32,
  tile_count: u32,
  out_at: u32,
  pages_at: u32,
}

@group(0) @binding(0) var<uniform> pass_: Pass;
// Steps (STEP_WORDS each), then the rows' tile maps, their R1 maps, each
// pass's table of pages, and the output tiles.
@group(0) @binding(1) var<storage, read> plan: array<u32>;
// The stack between passes, two words a level, then the output tiles.
@group(0) @binding(2) var<storage, read_write> work: array<u32>;
//__PAGES__

// A word of the page this pass bound as its k-th.
fn page_word(k: u32, index: u32) -> u32 {
  switch (k) {
    //__READS__
    default: {
      return 0u;
    }
  }
}

// R1's source: the stored word of the row of step `at` at its own (x, y) —
// nothing where it has no tile, where the tile's page is outside the
// step's, or where this pass binds no such page.
//
// A step: kind, mode, opacity, the first and last page it lays tiles from,
// map_at, the map's first tile column and row, its columns and rows, and
// where its R1 map is.
fn resample_texel(at: u32, x: i32, y: i32) -> u32 {
  let column = (x >> 7u) - bitcast<i32>(plan[at + 6u]);
  let row = (y >> 7u) - bitcast<i32>(plan[at + 7u]);
  let columns = plan[at + 8u];
  if (column < 0 || row < 0 || u32(column) >= columns || u32(row) >= plan[at + 9u]) {
    return 0u;
  }
  let entry = plan[plan[at + 5u] + u32(row) * columns + u32(column)];
  let page = entry >> 16u;
  if (entry == NO_TILE || page < plan[at + 3u] || page > plan[at + 4u]) {
    return 0u;
  }
  // A page the pass binds none of is NO_PAGE, no case of page_word's.
  let k = plan[pass_.pages_at + page];
  return page_word(k, (entry & 0xffffu) * TILE_TEXELS + u32(y & 127) * 128u + u32(x & 127));
}

// What the row of step `at` shows at canvas pixel (x, y), straight on the
// 16-bit scale. ⭐THE ONE PLACE A ROW IS SAMPLED: R1 (gpu-int-spec-canvas)
// for every pose, a whole-pixel move being its copy.
fn row_sample(at: u32, x: i32, y: i32) -> vec4<u32> {
  let m = plan[at + 10u];
  let map = resample_map(array<u32, 15>(
    plan[m], plan[m + 1u], plan[m + 2u], plan[m + 3u], plan[m + 4u], plan[m + 5u], plan[m + 6u],
    plan[m + 7u], plan[m + 8u], plan[m + 9u], plan[m + 10u], plan[m + 11u], plan[m + 12u],
    plan[m + 13u], plan[m + 14u],
  ));
  return blend_unpack8(resample(map, at, x, y));
}

fn level_at(level: u32, tile: u32, texel: u32) -> u32 {
  return ((level * pass_.tile_count + tile) * TILE_TEXELS + texel) * 2u;
}

fn load(level: u32, tile: u32, texel: u32) -> vec4<u32> {
  let at = level_at(level, tile, texel);
  let rg = work[at];
  let ba = work[at + 1u];
  return vec4<u32>(rg & 0xffffu, rg >> 16u, ba & 0xffffu, ba >> 16u);
}

fn save(level: u32, tile: u32, texel: u32, pixel: vec4<u32>) {
  let at = level_at(level, tile, texel);
  work[at] = pixel.x | (pixel.y << 16u);
  work[at + 1u] = pixel.z | (pixel.w << 16u);
}

// A buffer closed onto the one under it at `opacity`, in `mode`.
fn laid(mode: u32, opacity: u32, src: vec4<u32>, dst: vec4<u32>) -> vec4<u32> {
  return blend_composite(mode, vec4<u32>(src.xyz, blend_mul(src.w, opacity)), dst);
}

@compute @workgroup_size(16, 16, 1)
fn composite(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_id) local: vec3<u32>,
) {
  let tile = group.z;
  if (tile >= pass_.tile_count) {
    return;
  }
  let lx = group.x * 16u + local.x;
  let ly = group.y * 16u + local.y;
  let texel = ly * 128u + lx;
  let x = bitcast<i32>(plan[pass_.tiles_at + tile * 2u]) * 128 + i32(lx);
  let y = bitcast<i32>(plan[pass_.tiles_at + tile * 2u + 1u]) * 128 + i32(ly);

  var stack: array<vec4<u32>, DEPTH>;
  var depth = pass_.depth_in;
  if (pass_.first == 1u) {
    stack[0] = vec4<u32>(0u);
  } else {
    for (var level = 0u; level <= depth; level++) {
      stack[level] = load(level, tile, texel);
    }
  }
  for (var step = pass_.step_begin; step < pass_.step_end; step++) {
    let at = step * STEP_WORDS;
    switch (plan[at]) {
      case STEP_ROW: {
        let shown = row_sample(at, x, y);
        if (shown.w != 0u) {
          stack[depth] = laid(plan[at + 1u], plan[at + 2u], shown, stack[depth]);
        }
      }
      case STEP_OPEN: {
        depth += 1u;
        stack[depth] = vec4<u32>(0u);
      }
      // The clip's base under it, its alpha made whole: where the base is
      // not, its colour is nothing — black (drawOpaque).
      case STEP_OPEN_OPAQUE: {
        depth += 1u;
        stack[depth] = vec4<u32>(stack[depth - 1u].xyz, W_ONE);
      }
      case STEP_CLOSE: {
        let closed = stack[depth];
        depth -= 1u;
        stack[depth] = laid(plan[at + 1u], plan[at + 2u], closed, stack[depth]);
      }
      case STEP_CLOSE_ATOP: {
        let closed = stack[depth];
        depth -= 1u;
        stack[depth] = blend_atop(closed, stack[depth]);
      }
      default: {}
    }
  }
  if (pass_.last == 1u) {
    work[pass_.out_at + tile * TILE_TEXELS + texel] = blend_pack8(stack[0]);
  } else {
    for (var level = 0u; level <= depth; level++) {
      save(level, tile, texel, stack[level]);
    }
  }
}
