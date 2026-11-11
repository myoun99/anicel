// The row composite (gpu-canonical-store 2단계 ②③, round E1): one thread
// holds one output pixel and walks the plan's steps bottom to top, a stack
// of buffers in its registers — rows, folders and clipping groups, every
// one composited by the blend family on the 16-bit scale, with no rounding
// between rows. The pixel is rounded to a byte once, at the end.
//
// A walk the pages cannot all be bound for, or nested deeper than the
// registers hold, is cut into passes (mod.rs); between them the stack goes
// to `work` as it is, 16 bits a channel, so where the cuts fall changes no
// value. A pass holds the levels from its base up; the ones under it wait
// in `work`.
//
// The last pass puts each pixel by `put` — to_tiles.wgsl's, into output
// tiles, or to_surface.wgsl's, onto a surface — and only those inside the
// output's pixels as they are.
//
// Needs shared/isqrt.wgsl, blend/blend.wgsl, shared/wide.wgsl,
// shared/resample.wgsl, shared/tile.wgsl, effects/key.wgsl,
// effects/matrix.wgsl, shared/premultiply.wgsl and mask/byte.wgsl before
// it; defines byte.wgsl's `mask_word`.

const NO_TILE: u32 = 0xffffffffu;
// The stack levels a pass holds: as many as its plan's passes reach
// (mod.rs `Compiled`), as a pass pays for the levels compiled into it
// whether it reaches them or not.
const DEPTH: u32 = __DEPTH__u;
const STEP_WORDS: u32 = 14u;
// A row's matrix place where it runs none (mod.rs's NO_MATRIX).
const NO_MATRIX: u32 = 0xffffffffu;

const STEP_ROW: u32 = 0u;
const STEP_OPEN: u32 = 1u;
const STEP_OPEN_OPAQUE: u32 = 2u;
const STEP_CLOSE: u32 = 3u;
const STEP_CLOSE_ATOP: u32 = 4u;
const STEP_SOLID: u32 = 5u;
const STEP_MARK: u32 = 6u;

// One pass: the steps it runs, the stack depth it takes, the output tiles
// it covers and the words each takes in the plan, where its table of pages
// is — which binding holds each page
// of the pool (shared/pages.rs's NO_PAGE where it binds none) — the lowest stack
// level it holds, the output's pixels, [left, right) × [top, bottom), and
// the rows of the plan's mask its output tiles lie on: where in `work`
// they start, its box's pixels across, the rows there, a row's words, and
// the canvas pixel the first of them starts at.
struct Pass {
  step_begin: u32,
  step_end: u32,
  depth_in: u32,
  first: u32,
  last: u32,
  tiles_at: u32,
  tile_words: u32,
  tile_count: u32,
  out_at: u32,
  pages_at: u32,
  base: u32,
  left: i32,
  top: i32,
  right: i32,
  bottom: i32,
  mask_at: u32,
  mask_width: u32,
  mask_height: u32,
  mask_stride: u32,
  mask_left: i32,
  mask_top: i32,
}

@group(0) @binding(0) var<uniform> pass_: Pass;
// Steps (STEP_WORDS each), then the rows' tile maps, their key chains and
// colour matrices,
// their R1 maps, each pass's table of pages, and the output tiles.
@group(0) @binding(1) var<storage, read> plan: array<u32>;
// The stack between passes, two words a level, then the output tiles,
// then the pass's rows of the mask.
@group(0) @binding(2) var<storage, read_write> work: array<u32>;
// The pages, and page_word, come before this (shared/pages.wgsl).
//__OUTPUT__

// byte.wgsl's host: the pass's rows of the mask are in `work`.
fn mask_word(at: u32) -> u32 {
  return work[at];
}

// key.wgsl's host: a chain's runs are in the plan.
fn key_word(at: u32) -> u32 {
  return plan[at];
}

// matrix.wgsl's host: a row's matrix is in the plan.
fn matrix_word(at: u32) -> u32 {
  return plan[at];
}

// The keys of the row of step `at` over its stored `word`: each run of its
// chain in order, every one against the word's own alpha.
fn row_keyed(at: u32, word: u32) -> u32 {
  let chain = plan[at + 11u];
  let original = word >> 24u;
  var keyed = word;
  for (var run = 0u; run < plan[chain]; run++) {
    keyed = key_rgba8(plan[chain + 1u + run], keyed, original);
  }
  return keyed;
}

// R1's source: the stored word of the row of step `at` at its own (x, y),
// keyed — nothing where it has no tile, where the tile's page is outside
// the step's, or where this pass binds no such page. At `at | MASK_SOURCE`
// it is the plan's mask as a picture instead: its byte at (x, y) the
// word's alpha, nothing past the box (step_cover).
//
// A step: kind, mode, opacity, the first and last page it lays tiles from,
// map_at, the map's first tile column and row, its columns and rows, where
// its R1 map is, where its key chain's list is, whether the plan's mask
// covers it, and where its colour matrix is. A close: kind, mode, opacity,
// then nothing up to the last word: where the matrix it closes through is.
fn resample_texel(at: u32, x: i32, y: i32) -> u32 {
  if (composite_with_mask && (at & MASK_SOURCE) != 0u) {
    let mask = MaskPlane(pass_.mask_at, pass_.mask_width, pass_.mask_height, pass_.mask_stride);
    return mask_byte_of(mask, u32(x - pass_.mask_left), u32(y - pass_.mask_top)) << 24u;
  }
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
  let index = (entry & 0xffffu) * TILE_TEXELS + tile_texel(u32(x), u32(y));
  return row_keyed(at, page_word(k, index));
}

// What the row of step `at` shows at canvas pixel (x, y), straight on the
// 16-bit scale. ⭐THE ONE PLACE A ROW IS SAMPLED: R1 (gpu-int-spec-canvas)
// for every pose, a whole-pixel move being its copy — then the row's
// colour matrix, where it runs one, on what R1 lays: the app folds a
// row's colour effects into its paint's filter, which runs on what is
// drawn (resolveCompositeEffectPaint; 캔버스 베이스 11-06 07:48).
fn row_sample(at: u32, x: i32, y: i32) -> vec4<u32> {
  var word = resample(step_map(at), at, x, y);
  let matrix = plan[at + 13u];
  if (matrix != NO_MATRIX) {
    word = matrix_rgba8(matrix, word);
  }
  return blend_unpack8(word);
}

// The map of step `at` — a row's, or a range mark's.
fn step_map(at: u32) -> ResampleMap {
  let m = plan[at + 10u];
  return resample_map(array<u32, RESAMPLE_MAP_WORDS>(
    plan[m], plan[m + 1u], plan[m + 2u], plan[m + 3u], plan[m + 4u], plan[m + 5u], plan[m + 6u],
    plan[m + 7u], plan[m + 8u], plan[m + 9u], plan[m + 10u], plan[m + 11u], plan[m + 12u],
    plan[m + 13u], plan[m + 14u], plan[m + 15u],
  ));
}

// resample_texel's source for the plan's mask, above step `at`'s own: no
// binding holds 2^31 words of plan.
const MASK_SOURCE: u32 = 0x80000000u;

// Whether a pass meets a step under the plan's mask, fixed when its
// pipeline is made as R1's modes are (mod.rs's Compiled): a pass with none
// has the mask's source and the mark compiled out. No byte changes — a
// pass meets only the steps it was compiled for — but time: holding them,
// a pass for sixteen turned Pick rows and no mask took 34.0 ms over 1024²
// where it takes 32.6, as before they were (RTX 4080, DX12, 2026-11-06).
// No test here can see it.
override composite_with_mask: bool = true;

// The coverage step `at` is laid by at canvas pixel (x, y): the plan's mask
// read as the step's pixels are, through its own map by R1 in its mode.
// The mask is a plane in the step's own space — a posed row reads its
// selection in its own artwork, as the app cuts a dab by it there
// (piece_landing.dart `regionInArtworkSpace`, 09-25 a-marquee-on-a-posed-row)
// — and its edge is resampled as what lands under it will be, so what
// shows while a stroke is drawn is what landing it shows (「보이는 중이랑
// 결과랑」): exactly for a copy. A step under no mask takes 255 without a
// second R1 for every row, so it is laid at its opacity by the same
// multiply (R28, gpu-canonical-store 11-06 06:51).
fn step_cover(at: u32, x: i32, y: i32) -> u32 {
  if (!composite_with_mask || plan[at + 12u] == 0u) {
    return 255u;
  }
  return resample(step_map(at), at | MASK_SOURCE, x, y) >> 24u;
}

// A range mark's cell along one side (fill_range_mark.dart): floor((p −
// shift) / MARK_CELL), p being whole + (rest + 2^15) / 2^16 and the shift
// Q.16 — worked on whole pixels and their rest apart, so no product of a
// far pixel's position passes an i32.
const MARK_CELL: i32 = 8;
const MARK_WHITE: u32 = 0x80ffffffu;
const MARK_BLACK: u32 = 0x80000000u;

fn mark_cell(whole: i32, rest: i32, shift: i32) -> i32 {
  let n = whole - (shift >> 16u);
  let r = rest + 32768 - (shift & 0xffff);
  let k = (n & (MARK_CELL - 1)) * 65536 + r;
  let one = MARK_CELL * 65536;
  // MARK_CELL is 2^3.
  return (n >> 3u) + select(0, -1, k < 0) + select(0, 1, k >= one);
}

// The colour range mark `at` lays at canvas pixel (x, y): where the pixel's
// centre lands in the row's space by its map — p less a half on R1's Q.16,
// as whole pixels and the rest, exact for a copy however far it moves — in
// cells pushed the way the press moved: white where their column + row is
// even, black where odd, each at half alpha (「밑 색이 살짝 보임」). Asked
// only where the mark's cover is not 0, so where the centre lands.
fn mark_colour(at: u32, x: i32, y: i32) -> vec4<u32> {
  let map = step_map(at);
  var whole: vec2<i32>;
  var rest = vec2<i32>(0);
  if (map.mode == RESAMPLE_COPY) {
    let sx = wide_add(wide(x), wide_shr(map.c, 20u));
    let sy = wide_add(wide(y), wide_shr(map.f, 20u));
    whole = vec2<i32>(bitcast<i32>(sx.x), bitcast<i32>(sy.x));
  } else if (resample_with_locate()) {
    var point: ResamplePoint;
    _ = resample_locate(map, x, y, &point);
    let u = vec2<i32>(point.u, point.v);
    whole = u >> vec2<u32>(16u);
    rest = u & vec2<i32>(0xffff);
  }
  let column = mark_cell(whole.x, rest.x, bitcast<i32>(plan[at + 1u]));
  let row = mark_cell(whole.y, rest.y, bitcast<i32>(plan[at + 2u]));
  return blend_unpack8(select(MARK_BLACK, MARK_WHITE, ((column + row) & 1) == 0));
}

fn level_at(level: u32, tile: u32, texel: u32) -> u32 {
  return ((level * pass_.tile_count + tile) * TILE_TEXELS + texel) * 2u;
}

fn load(level: u32, tile: u32, texel: u32) -> vec4<u32> {
  let at = level_at(level, tile, texel);
  return blend_unpack16(vec2<u32>(work[at], work[at + 1u]));
}

fn save(level: u32, tile: u32, texel: u32, pixel: vec4<u32>) {
  let at = level_at(level, tile, texel);
  let pair = blend_pack16(pixel);
  work[at] = pair.x;
  work[at + 1u] = pair.y;
}

// A row or a buffer laid on the one under it at `opacity` under the
// coverage byte `cover` (blend_cover), in `mode` — an eraser's taking its
// alpha off what is under it, as a stroke of the eraser lands on its cel,
// and a plus adding itself to it, as a crossfade's second pass does.
fn laid(mode: u32, opacity: u32, cover: u32, src: vec4<u32>, dst: vec4<u32>) -> vec4<u32> {
  let alpha = blend_mul(src.w, blend_cover(opacity, cover));
  if (mode == BLEND_ERASE) {
    return blend_erase(alpha, dst);
  }
  if (mode == BLEND_PLUS) {
    return blend_plus(vec4<u32>(src.xyz, alpha), dst);
  }
  return blend_composite(mode, vec4<u32>(src.xyz, alpha), dst);
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
  let texel = tile_texel(lx, ly);
  let entry = pass_.tiles_at + tile * pass_.tile_words;
  let x = bitcast<i32>(plan[entry]) * i32(TILE_SIDE) + i32(lx);
  let y = bitcast<i32>(plan[entry + 1u]) * i32(TILE_SIDE) + i32(ly);

  // stack[i] is level base + i; `top` is the walk's depth less the base.
  var stack: array<vec4<u32>, DEPTH>;
  var top = pass_.depth_in - pass_.base;
  if (pass_.first == 1u) {
    stack[0] = vec4<u32>(0u);
  } else {
    for (var i = 0u; i <= top; i++) {
      stack[i] = load(pass_.base + i, tile, texel);
    }
  }
  for (var step = pass_.step_begin; step < pass_.step_end; step++) {
    let at = step * STEP_WORDS;
    switch (plan[at]) {
      // A row is sampled only on the output tiles where it reads a stored
      // tile (its bit there, mod.rs's lay); anywhere else it shows nothing.
      case STEP_ROW: {
        if (((plan[entry + 2u + step / 32u] >> (step % 32u)) & 1u) != 0u) {
          let shown = row_sample(at, x, y);
          if (shown.w != 0u) {
            let cover = step_cover(at, x, y);
            stack[top] = laid(plan[at + 1u], plan[at + 2u], cover, shown, stack[top]);
          }
        }
      }
      case STEP_OPEN: {
        top += 1u;
        stack[top] = vec4<u32>(0u);
      }
      // The clip's base under it, its alpha made whole: where the base is
      // not, its colour is nothing — black (drawOpaque).
      case STEP_OPEN_OPAQUE: {
        top += 1u;
        stack[top] = vec4<u32>(stack[top - 1u].xyz, W_ONE);
      }
      // A buffer through its matrix runs on its bytes, rounded as a stored
      // pixel is (mod.rs's Step::Close).
      case STEP_CLOSE: {
        var closed = stack[top];
        let matrix = plan[at + 13u];
        if (matrix != NO_MATRIX) {
          closed = blend_unpack8(matrix_rgba8(matrix, blend_pack8(closed)));
        }
        top -= 1u;
        stack[top] = laid(plan[at + 1u], plan[at + 2u], 255u, closed, stack[top]);
      }
      case STEP_CLOSE_ATOP: {
        let closed = stack[top];
        top -= 1u;
        stack[top] = blend_atop(closed, stack[top]);
      }
      // A colour over its rect, laid as a row of it is (mod.rs's
      // Step::Solid).
      case STEP_SOLID: {
        let x0 = bitcast<i32>(plan[at + 2u]);
        let y0 = bitcast<i32>(plan[at + 3u]);
        let x1 = bitcast<i32>(plan[at + 4u]);
        let y1 = bitcast<i32>(plan[at + 5u]);
        if (x >= x0 && x < x1 && y >= y0 && y < y1) {
          let colour = blend_unpack8(plan[at + 1u]);
          stack[top] = laid(BLEND_NORMAL, W_ONE, 255u, colour, stack[top]);
        }
      }
      // A range mark's checker under the range (mod.rs's Step::Mark).
      case STEP_MARK: {
        let cover = step_cover(at, x, y);
        if (composite_with_mask && cover != 0u) {
          stack[top] = laid(BLEND_NORMAL, W_ONE, cover, mark_colour(at, x, y), stack[top]);
        }
      }
      default: {}
    }
  }
  if (pass_.last == 1u) {
    let inside = x >= pass_.left && x < pass_.right && y >= pass_.top && y < pass_.bottom;
    put(tile, texel, x, y, inside, blend_pack8(stack[0]));
  } else {
    for (var i = 0u; i <= top; i++) {
      save(pass_.base + i, tile, texel, stack[i]);
    }
  }
}
