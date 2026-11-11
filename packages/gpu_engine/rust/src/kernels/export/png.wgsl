// A PNG's rows under their filters (gpu-export-path ①e): each row led by
// the byte of the filter that leaves it smallest, then the row under it —
// the bytes a writer deflates as they are, so the CPU's filter pass goes.
//
// The law is the app's (`PngImageData`, lib/src/services/media/
// png_writing.dart). Byte x of a row, with a the byte a pixel to its left,
// b the byte above it and c the byte above a — each 0 off the picture —,
// is under filter 0 to 4 x minus 0, a, b, (a + b) >> 1 or Paeth(a, b, c),
// mod 256. A row's cost under a filter is the sum of its bytes read as
// signed — f under 128, 256 − f from it —, and the least wins, a tie to the
// lower filter. The app stops trying once a filter costs 0, which nothing
// after it can beat: all five here give the same choice.
//
// A row is a workgroup's: its filters read only it and the row above as it
// was, so rows go apart. The costs add in workgroup atomics — integer sums,
// the same in any order. Each row's out starts on a word of its own, filled
// out with zeros: no two groups write one word, and a row costs at most
// three bytes more.
//
// Needs, before it, its source's `PIXEL_BYTES` and `row_byte`
// (png_rgba.wgsl or png_rgb.wgsl).

struct Params {
  // The frame's step from one row to the next (frame.wgsl,
  // frame_shown.wgsl).
  stride: u32,
  // The picture.
  width: u32,
  height: u32,
  // Words a row of the out takes: its filter's byte and its own.
  row_words: u32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(2) var<storage, read_write> rows: array<u32>;

const FILTERS: u32 = 5u;
const GROUP: u32 = 64u;

var<workgroup> costs: array<atomic<u32>, 5>;

// A byte and the three its filters predict it from.
struct Around {
  x: u32,
  a: u32,
  b: u32,
  c: u32,
}

// Byte `i` of row `y`, and around it.
fn around(y: u32, i: u32) -> Around {
  var near = Around(row_byte(y, i), 0u, 0u, 0u);
  if (i >= PIXEL_BYTES) {
    near.a = row_byte(y, i - PIXEL_BYTES);
  }
  // The top row has nothing above it: row y − 1 would wrap past the
  // source, and a load out of bounds may give any word of it (WGSL, invalid
  // memory references). This device gives 0, so no test here sees it go.
  if (y > 0u) {
    near.b = row_byte(y - 1u, i);
    if (i >= PIXEL_BYTES) {
      near.c = row_byte(y - 1u, i - PIXEL_BYTES);
    }
  }
  return near;
}

// The Paeth predictor: of a, b and c, the one nearest a + b − c, a tie to
// the earlier (`pngPaeth`). Spelled as the law is: pa = pb with pa <= pc
// only when a = b, so `pa < pb` would answer the same — `<=` stays, read
// beside the law.
fn paeth(a: u32, b: u32, c: u32) -> u32 {
  let p = i32(a) + i32(b) - i32(c);
  let pa = abs(p - i32(a));
  let pb = abs(p - i32(b));
  let pc = abs(p - i32(c));
  if (pa <= pb && pa <= pc) {
    return a;
  }
  return select(c, b, pb <= pc);
}

// The byte `near` is about, under filter `kind`.
fn under(kind: u32, near: Around) -> u32 {
  var predicted = 0u;
  switch kind {
    case 1u: { predicted = near.a; }
    case 2u: { predicted = near.b; }
    case 3u: { predicted = (near.a + near.b) >> 1u; }
    case 4u: { predicted = paeth(near.a, near.b, near.c); }
    default: {}
  }
  return (near.x - predicted) & 0xffu;
}

// The filter whose cost is least, a tie to the lower.
fn cheapest() -> u32 {
  var best = 0u;
  var best_cost = atomicLoad(&costs[0]);
  for (var kind = 1u; kind < FILTERS; kind += 1u) {
    let cost = atomicLoad(&costs[kind]);
    if (cost < best_cost) {
      best = kind;
      best_cost = cost;
    }
  }
  return best;
}

@compute @workgroup_size(64)
fn png_filter_pass(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_index) lane: u32,
) {
  let y = group.y;
  let stride = params.width * PIXEL_BYTES;
  var sums = array<u32, 5>(0u, 0u, 0u, 0u, 0u);
  for (var i = lane; i < stride; i += GROUP) {
    let near = around(y, i);
    for (var kind = 0u; kind < FILTERS; kind += 1u) {
      let f = under(kind, near);
      sums[kind] += select(256u - f, f, f < 128u);
    }
  }
  for (var kind = 0u; kind < FILTERS; kind += 1u) {
    atomicAdd(&costs[kind], sums[kind]);
  }
  workgroupBarrier();
  let best = cheapest();
  // Byte 0 of a row's out is its filter, byte k its byte k − 1 under it.
  for (var w = lane; w < params.row_words; w += GROUP) {
    var word = 0u;
    for (var k = 0u; k < 4u; k += 1u) {
      let at = w * 4u + k;
      var byte = 0u;
      if (at == 0u) {
        byte = best;
      } else if (at <= stride) {
        byte = under(best, around(y, at - 1u));
      }
      word |= byte << (k * 8u);
    }
    rows[y * params.row_words + w] = word;
  }
}
