// A selection's hard mask by its pixels' centres, by gpu-int-spec-canvas
// 1b S1 — the app's CanvasSelectionRegion.maskFor: each polygon by the
// even-odd rule, the polygons of one act as their union, the steps folded
// one after another by the mode table, a nested selection as one operand;
// 255 in, 0 out.
//
// A polygon is laid a row at a time. Each edge the row's scanline crosses
// toggles one bit: the first column whose centre the crossing is not right
// of (`region_first_right`). A pixel is in when an odd number of crossings
// lie right of its centre — containsPoint's `x < crossing`, which maskFor's
// `(x − 0.5).ceil()` keeps — so its parity is the XOR of the toggles past
// it, which a scan from the row's right end gives (`region_scan`). The
// crossing is placed exactly, in integers: vertices Q.8 within ±2^15
// pixels, a row's scanline through its pixels' centres,
// Y = (2·row + 1)·128.
//
// A bit plane holds a bit a pixel, the leftmost the low bit of the row's
// first word, `stride` words a row with room for one bit past the box —
// where a crossing right of every centre toggles. The mask comes out as a
// byte plane, as mask.wgsl lays one.
//
// ⚠️A row past the box's last is past the plane, where DX12 reads 0 and
// drops a write — so the tests here cannot see the box's guards on rows
// there; Metal clamps the index instead.
//
// Needs shared/wide.wgsl before it.

// The box in canvas pixels; a bit plane's words a row; the polygon a
// toggle pass lays, as its first vertex and their count; and how a fold
// combines its planes.
struct Region {
  left: i32,
  top: i32,
  width: u32,
  height: u32,
  stride: u32,
  first: u32,
  count: u32,
  op: u32,
}

@group(0) @binding(0) var<uniform> region: Region;
@group(0) @binding(1) var<storage, read> vertices: array<vec2<i32>>;
@group(0) @binding(2) var<storage, read_write> toggles: array<atomic<u32>>;
@group(0) @binding(3) var<storage, read_write> into: array<u32>;
@group(0) @binding(4) var<storage, read> operand: array<u32>;
@group(0) @binding(5) var<storage, read_write> bytes_out: array<u32>;

// The mode table — SelectionCombineMode._fold, a bit a pixel.
const REGION_REPLACE: u32 = 0u;
const REGION_ADD: u32 = 1u;
const REGION_SUBTRACT: u32 = 2u;

// The first column of the box whose centre the edge (a, b) does not cross
// the scanline at `y` right of: every column left of it has the crossing
// right of its centre. 0 when none has, the box's width when all have.
// Rising by D = high.y − low.y > 0, the edge crosses at
// X = low.x + (high.x − low.x)·(y − low.y) / D, and column c's centre
// (2·(left + c) + 1)·128 is not left of X iff 256·D·c ≥ n, with
// n = X·D − (256·left + 128)·D — so the column is ⌈n / 256D⌉, the spec's
// inequality solved for c.
fn region_first_right(a: vec2<i32>, b: vec2<i32>, y: i32) -> u32 {
  let low = select(b, a, a.y < b.y);
  let high = select(a, b, a.y < b.y);
  let rise = high.y - low.y;
  let crossing = wide_add(wide_mul_i32(low.x, rise), wide_mul_i32(high.x - low.x, y - low.y));
  let n = wide_sub(crossing, wide_mul_i32(256 * region.left + 128, rise));
  if (wide_negative(n)) {
    return 0u;
  }
  // Every column is left of a crossing past width·256D — and of one past
  // (width − 1)·256D as well, so which of the two the check reads is free.
  // Short of it the column is at most the width, 2^16: 17 bits.
  let column = 256u * u32(rise);
  if (wide_less(wide_mul_u32(column, region.width), n)) {
    return region.width;
  }
  return wide_div_floor(wide_add(n, Wide(column - 1u, 0u)), Wide(column, 0u), 17u);
}

// A thread an edge of the polygon and a row of the box: the edge's toggle
// on the row, where its scanline crosses it — half-open, so a vertex on the
// scanline toggles once (edgeStraddles). Edge i runs to vertex i − 1, the
// last closing the ring.
@compute @workgroup_size(8, 8, 1)
fn region_toggle(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= region.count || id.y >= region.height) {
    return;
  }
  let a = vertices[region.first + id.x];
  let b = vertices[region.first + select(id.x, region.count, id.x == 0u) - 1u];
  let y = (2 * (region.top + i32(id.y)) + 1) * 128;
  if ((a.y > y) == (b.y > y)) {
    return;
  }
  let at = region_first_right(a, b, y);
  atomicXor(&toggles[id.y * region.stride + at / 32u], 1u << (at % 32u));
}

// A thread a row: each pixel's parity — the XOR of the toggles past it —
// joined to the row of `into` (the union of an act's polygons), taking the
// toggles back to nothing for the next polygon.
@compute @workgroup_size(64, 1, 1)
fn region_scan(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= region.height) {
    return;
  }
  // Every bit set when the words right of this one hold an odd number.
  var carry = 0u;
  for (var word = region.stride; word > 0u; word--) {
    let at = id.x * region.stride + word - 1u;
    // Bit i: the XOR of this word's toggles at i and past it.
    var past = atomicExchange(&toggles[at], 0u);
    past ^= past >> 1u;
    past ^= past >> 2u;
    past ^= past >> 4u;
    past ^= past >> 8u;
    past ^= past >> 16u;
    into[at] |= (past >> 1u) ^ carry;
    carry ^= 0u - (past & 1u);
  }
}

fn region_put_words(id: vec3<u32>) -> bool {
  return id.x < region.stride && id.y < region.height;
}

// A thread a word of a bit plane: nothing selected yet.
@compute @workgroup_size(8, 8, 1)
fn region_clear(@builtin(global_invocation_id) id: vec3<u32>) {
  if (region_put_words(id)) {
    into[id.y * region.stride + id.x] = 0u;
  }
}

// A thread a word of a bit plane: `operand` folded into `into` by `op`.
@compute @workgroup_size(8, 8, 1)
fn region_fold(@builtin(global_invocation_id) id: vec3<u32>) {
  if (!region_put_words(id)) {
    return;
  }
  let at = id.y * region.stride + id.x;
  let inside = into[at];
  let hit = operand[at];
  switch (region.op) {
    case REGION_REPLACE: {
      into[at] = hit;
    }
    case REGION_ADD: {
      into[at] = inside | hit;
    }
    case REGION_SUBTRACT: {
      into[at] = inside & ~hit;
    }
    default: {
      into[at] = inside & hit;
    }
  }
}

// A thread a word of the mask: four of `operand`'s pixels as bytes. A
// thread stops at the box's last column for its work alone: what it put
// past it would land in the row's padding, which no pass reads.
@compute @workgroup_size(8, 8, 1)
fn region_bytes(@builtin(global_invocation_id) id: vec3<u32>) {
  let words = (region.width + 3u) / 4u;
  if (id.x >= words || id.y >= region.height) {
    return;
  }
  var word = 0u;
  for (var k = 0u; k < 4u; k++) {
    let column = id.x * 4u + k;
    if (column >= region.width) {
      break;
    }
    let bit = (operand[id.y * region.stride + column / 32u] >> (column % 32u)) & 1u;
    word = word | (((0u - bit) & 0xffu) << (k * 8u));
  }
  bytes_out[id.y * words + id.x] = word;
}
