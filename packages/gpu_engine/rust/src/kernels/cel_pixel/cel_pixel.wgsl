// V1, the cel pixel pass (gpu-census V1 — C's `qa_cel_pixel_pass_tile`,
// the app's `overwriteCelPixels`): the 색 편집 verbs over a cel's stored
// tiles, read from the pool's pages as they are stored — a colour under an
// alpha of 0 included, which 픽셀 비우기 leaves there on purpose
// (`CelPixelChannel.alpha`).
//
// A pixel takes part where its coverage is not 0 and, with a selector, the
// selector's key names its colour other than as the verb keeps; without
// one, where it has ink or the verb takes empty pixels too. A pixel taking
// part takes the incoming bytes on its channel's bytes — 0 where 2치화's cut
// is above its own byte —, blended by its coverage going forward, assigned
// as they are on an undo. What it held before goes out as runs, in walk
// order: consecutive pixels taking part whose channel bytes are equal share
// one. A run never crosses a tile — the app's recipe builder joins them, as
// C's pass.
//
// A tile is a workgroup and a row a lane, which walks it as C's loop does.
// The lanes' rows are joined by lane 0, in order, into where each row's
// pixels and runs start. The count entry puts each tile's pixels taking
// part and runs; the apply entry, given where every tile's start among all
// of them (cel_pixel/mod.rs adds them up between the two), puts the tile's
// new pixels and its runs.
//
// Needs effects/key.wgsl, shared/tile.wgsl and shared/pages.wgsl (with its
// bindings) before it; defines key.wgsl's `key_word`.

struct CelPass {
  // In `given`, after this pass's tiles, CEL_TILE_WORDS each: the
  // selector's key run (key.wgsl's layout); the incoming bytes, four a
  // word, low first; where each of the pass's tiles' pixels and runs start
  // among the walk's, two words a tile (the apply entry's); the mask's rows
  // the pass's tiles lie on (mask.wgsl's layout).
  tables_at: u32,
  incoming_at: u32,
  starts_at: u32,
  mask_at: u32,
  // The walk index of the pass's first tile — the first of the new pixels
  // bound —, of the pixel the incoming bytes start at, and the word the
  // runs bound start at among all the walk's.
  first: u32,
  touched_first: u32,
  runs_base: u32,
  // The channel: its bytes, where byte i sits in a pixel's word (base + i ·
  // stride), and whether a pixel with no ink takes part.
  bytes: u32,
  base: u32,
  stride: u32,
  takes_empty: u32,
  // 0, or 1 with the selector's key run at `tables_at`.
  selects: u32,
  keeps_matches: u32,
  // 1: an undo — the incoming bytes are a recipe, the pixel of global walk
  // index i reading its entry at i · step, and nothing blends.
  is_undo: u32,
  step: u32,
  threshold: u32,
  // 1: going forward, the runs are put.
  puts_runs: u32,
  // 0, every pixel covered whole; or 1 under the mask: its box's pixels
  // across, the rows of it the pass is given, and a row's words.
  masked: u32,
  mask_width: u32,
  mask_height: u32,
  mask_stride: u32,
}

// A walked tile: the binding of its page, its slot, its index in the walk,
// and where its top-left pixel is in the mask's box — a word's two's
// complement each way.
const CEL_TILE_WORDS: u32 = 5u;
// No value: a value is three bytes at most.
const CEL_NONE: u32 = 0xffffffffu;

@group(0) @binding(0) var<uniform> pass_: CelPass;
@group(0) @binding(1) var<storage, read> given: array<u32>;
// The walked tiles' new pixels, tile after tile in walk order.
@group(0) @binding(2) var<storage, read_write> tiles_out: array<u32>;
// The count entry's two counts a walked tile; the apply entry's runs — a
// value and the rank in its tile of its first pixel.
@group(0) @binding(3) var<storage, read_write> put: array<u32>;

fn key_word(at: u32) -> u32 {
  return given[at];
}

// Each row's pixels taking part, its first and last value, and the runs
// starting in it after its first; once joined, where its pixels and runs
// start in the tile and the value before it.
var<workgroup> row_touched: array<u32, 128>;
var<workgroup> row_first: array<u32, 128>;
var<workgroup> row_last: array<u32, 128>;
var<workgroup> row_starts: array<u32, 128>;
var<workgroup> row_rank: array<u32, 128>;
var<workgroup> row_run: array<u32, 128>;
var<workgroup> row_before: array<u32, 128>;
var<workgroup> tile_counts: vec2<u32>;

fn cel_tile(tile: u32, word: u32) -> u32 {
  return given[tile * CEL_TILE_WORDS + word];
}

// Pixel (x, y) of the tile, as stored.
fn cel_texel(tile: u32, x: u32, y: u32) -> u32 {
  return page_word(cel_tile(tile, 0u), cel_tile(tile, 1u) * TILE_TEXELS + y * TILE_SIDE + x);
}

// The coverage over pixel (x, y) of the tile: the mask's byte there, 0
// past its box — a pixel before it wraps past either side.
//
// ⚠️The mask's rows end what a pass is given, so a row past them is past
// the buffer, where DX12 reads 0 — the tests cannot see the guard on rows
// there, nor that `mask_height` is the pass's rows and not the box's
// (mutants c03 · w07, 11-06; mask.wgsl's head has the same); a device that
// clamps (Metal) would read the last word. A column past the box is within
// its row's last word, which the tests fill with 255.
fn cel_coverage(tile: u32, x: u32, y: u32) -> u32 {
  if (pass_.masked == 0u) {
    return 255u;
  }
  let mx = cel_tile(tile, 3u) + x;
  let my = cel_tile(tile, 4u) + y;
  if (mx >= pass_.mask_width || my >= pass_.mask_height) {
    return 0u;
  }
  let word = given[pass_.mask_at + my * pass_.mask_stride + mx / 4u];
  return (word >> (mx % 4u * 8u)) & 0xffu;
}

// Where channel byte `i` sits in a pixel's word, in bits.
fn cel_shift(i: u32) -> u32 {
  return (pass_.base + i * pass_.stride) * 8u;
}

// The channel's bytes of `texel`, byte i in bits 8i.
fn cel_value(texel: u32) -> u32 {
  var value = 0u;
  for (var i = 0u; i < pass_.bytes; i++) {
    value |= ((texel >> cel_shift(i)) & 0xffu) << (8u * i);
  }
  return value;
}

// `celPixelParticipates`: whether `texel` under `coverage` takes part.
fn cel_takes_part(texel: u32, coverage: u32) -> bool {
  if (coverage == 0u) {
    return false;
  }
  if (pass_.selects != 0u) {
    let rgb = vec3<u32>(texel & 0xffu, (texel >> 8u) & 0xffu, (texel >> 16u) & 0xffu);
    // The run's one key: named or not, against what the verb keeps.
    let named = (key_naming(pass_.tables_at, rgb) & 1u) != 0u;
    return named != (pass_.keeps_matches != 0u);
  }
  return pass_.takes_empty != 0u || (texel >> 24u) != 0u;
}

// The incoming byte `at`.
fn cel_incoming(at: u32) -> u32 {
  return (given[pass_.incoming_at + at / 4u] >> ((at % 4u) * 8u)) & 0xffu;
}

// `older + (incoming - older) * coverage / 255`, the integer mul-div-255:
// C's `qa_cel_pixel_blend`, the app's `_blend`.
fn cel_blend(older: u32, incoming: u32, coverage: u32) -> u32 {
  let scaled = incoming * coverage + older * (255u - coverage) + 128u;
  return (scaled + (scaled >> 8u)) >> 8u;
}

// `texel`, taking part under `coverage`, as the pass leaves it — `index`
// its global walk index.
fn cel_written(texel: u32, coverage: u32, index: u32) -> u32 {
  var out = texel;
  for (var i = 0u; i < pass_.bytes; i++) {
    let shift = cel_shift(i);
    let older = (texel >> shift) & 0xffu;
    let nth = (index - pass_.touched_first) * pass_.step + i;
    let source = cel_incoming(select(i, nth, pass_.is_undo != 0u));
    // No byte is under a cut of 0 — C's `threshold > 0 &&` before the same
    // test says nothing more.
    let wanted = select(source, 0u, older < pass_.threshold);
    let whole = pass_.is_undo != 0u || coverage == 255u;
    let byte = select(cel_blend(older, wanted, coverage), wanted, whole);
    out = (out & ~(0xffu << shift)) | (byte << shift);
  }
  return out;
}

// Lane `y`'s row of the tile, summed; then lane 0 joins the rows.
fn cel_rows(tile: u32, y: u32) {
  var touched = 0u;
  var first = CEL_NONE;
  var last = CEL_NONE;
  var starts = 0u;
  for (var x = 0u; x < TILE_SIDE; x++) {
    let texel = cel_texel(tile, x, y);
    if (!cel_takes_part(texel, cel_coverage(tile, x, y))) {
      continue;
    }
    let value = cel_value(texel);
    if (first == CEL_NONE) {
      first = value;
    } else if (value != last) {
      starts += 1u;
    }
    last = value;
    touched += 1u;
  }
  row_touched[y] = touched;
  row_first[y] = first;
  row_last[y] = last;
  row_starts[y] = starts;
  workgroupBarrier();
  if (y == 0u) {
    var rank = 0u;
    var runs = 0u;
    var before = CEL_NONE;
    for (var row = 0u; row < TILE_SIDE; row++) {
      row_rank[row] = rank;
      row_run[row] = runs;
      row_before[row] = before;
      if (row_touched[row] > 0u) {
        runs += row_starts[row] + u32(row_first[row] != before);
        before = row_last[row];
        rank += row_touched[row];
      }
    }
    tile_counts = vec2<u32>(rank, runs);
  }
  workgroupBarrier();
}

@compute @workgroup_size(128, 1, 1)
fn cel_count(@builtin(workgroup_id) group: vec3<u32>, @builtin(local_invocation_index) y: u32) {
  let tile = group.x;
  cel_rows(tile, y);
  if (y == 0u) {
    let at = cel_tile(tile, 2u) * 2u;
    put[at] = tile_counts.x;
    put[at + 1u] = tile_counts.y;
  }
}

@compute @workgroup_size(128, 1, 1)
fn cel_apply(@builtin(workgroup_id) group: vec3<u32>, @builtin(local_invocation_index) y: u32) {
  let tile = group.x;
  cel_rows(tile, y);
  let index = cel_tile(tile, 2u);
  let local = index - pass_.first;
  let row = local * TILE_TEXELS + y * TILE_SIDE;
  let start = given[pass_.starts_at + local * 2u];
  var rank = row_rank[y];
  var run = (given[pass_.starts_at + local * 2u + 1u] + row_run[y]) * 2u - pass_.runs_base;
  var last = row_before[y];
  for (var x = 0u; x < TILE_SIDE; x++) {
    let texel = cel_texel(tile, x, y);
    let coverage = cel_coverage(tile, x, y);
    if (!cel_takes_part(texel, coverage)) {
      tiles_out[row + x] = texel;
      continue;
    }
    let value = cel_value(texel);
    // An undo binds four words where the runs go, which nothing reads: past
    // them a write is the device's to drop (DX12) or clamp (Metal) onto
    // them, so no test tells this guard from its absence — it keeps the
    // writes off.
    if (value != last && pass_.puts_runs != 0u) {
      put[run] = value;
      put[run + 1u] = rank;
      run += 2u;
    }
    last = value;
    tiles_out[row + x] = cel_written(texel, coverage, start + rank);
    rank += 1u;
  }
}
