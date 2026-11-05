// A stroke's dabs piled on its 16-bit plane — 3단계's dab kernel
// (gpu-canonical-store ⑥, 1a (3/3 보탬)). A thread holds one pixel of a
// stroke tile and walks the dabs that reach the tile in the stroke's order:
// a dab reads what the ones before it left, so the order is the law. The
// pixel is read once, piled in registers, and written back with its bytes.
//
// Integers only, every intermediate inside u32 or i32, as blend.wgsl. A dab
// comes as integers — mod.rs turns the app's numbers into them, the one
// place a float becomes one —: its centre in 1/256 px, its tables on the
// 16-bit scale. How a dab lays what it lays is the blend family's: over is
// blend_composite's normal, the one over the engine has, and erase is
// blend_erase.
//
// Needs shared/isqrt.wgsl, blend/blend.wgsl and shared/tile.wgsl before it.

// The plan: the stroke tiles, TILE_WORDS each; the lists of the dabs that
// reach each, a dab's record's place a word; the records, DAB_WORDS each;
// the tables, an entry a word. Every place is a word of the plan.
@group(0) @binding(0) var<storage, read> plan: array<u32>;
// The stroke tiles' planes, a slot TILE_TEXELS pixels, two words a pixel:
// red and green, then blue and alpha, the low half first.
@group(0) @binding(1) var<storage, read_write> planes: array<u32>;
// Their bytes, the planes' view (blend_pack8), a word a pixel.
@group(0) @binding(2) var<storage, read_write> view: array<u32>;

// A stroke tile: its column and row on the canvas's grid, its slot, and
// where its list starts and how long it is.
const TILE_COLUMN: u32 = 0u;
const TILE_ROW: u32 = 1u;
const TILE_SLOT: u32 = 2u;
const TILE_FIRST: u32 = 3u;
const TILE_COUNT: u32 = 4u;
const TILE_WORDS: u32 = 5u;

// A dab's record. The centre is in 1/256 px; the region, the pixels it may
// touch, [left, right) by [top, bottom). The colour is its three bytes,
// red lowest; norm, opacity and flow are on the 16-bit scale, the contrast
// in 1/256. A table's place is NO_TABLE where it has none.
const DAB_CX: u32 = 0u;
const DAB_CY: u32 = 1u;
const DAB_LEFT: u32 = 2u;
const DAB_TOP: u32 = 3u;
const DAB_RIGHT: u32 = 4u;
const DAB_BOTTOM: u32 = 5u;
const DAB_FLAGS: u32 = 6u;
const DAB_COLOUR: u32 = 7u;
const DAB_NORM: u32 = 8u;
const DAB_OPACITY: u32 = 9u;
const DAB_FLOW: u32 = 10u;
const DAB_CONTRAST: u32 = 11u;
const DAB_EVENING: u32 = 12u;
// A round tip's: the shift its distances are taken at (1a 보탬 기하), its
// reach and inner radius at that shift — the inner one signed, under 0
// where it has none —, the tables' entries per unit of a distance in
// Q(DAB_POINT), the entries a row holds where the tables are square (0
// where they run along the radius), and the two tables.
const DAB_SHIFT: u32 = 13u;
const DAB_REACH: u32 = 14u;
const DAB_INNER: u32 = 15u;
const DAB_SCALE: u32 = 16u;
const DAB_POINT: u32 = 17u;
const DAB_ROW: u32 = 18u;
const DAB_COVERAGE: u32 = 19u;
const DAB_PILE: u32 = 20u;

// The C engine's flags (QA_DAB_FLAG_*), the ones this kernel reads.
const DAB_ERASE: u32 = 1u;
const DAB_ROUND: u32 = 2u;
const DAB_THRESHOLD: u32 = 32u;
const DAB_EDGE_HELD: u32 = 128u;

const NO_TABLE: u32 = 0xffffffffu;

// low to high by f15/32768, rounded — every table read's last step. Signed:
// a table may fall. |high - low|·32767 stays under 2^31.
fn dab_lerp(low: u32, high: u32, f15: u32) -> u32 {
  let rise = (i32(high) - i32(low)) * i32(f15);
  return u32(i32(low) + ((rise + 16384) >> 15u));
}

// The table at entry `index` and f15/32768 of the way to the next.
fn dab_between(index: u32, f15: u32) -> u32 {
  return dab_lerp(plan[index], plan[index + 1u], f15);
}

// d rounded to `shift` fewer bits, a half going up.
fn dab_shrunk(d: i32, shift: u32) -> i32 {
  if (shift == 0u) {
    return d;
  }
  return (d + (1 << (shift - 1u))) >> shift;
}

// Where a distance lands in the dab's tables: the entry, and the next 15
// bits of the way to the one after, cut. The distance is under 2^15 and the
// scale under 2^17, so their product stays in u32.
fn dab_entry(at: u32, distance: u32) -> vec2<u32> {
  let position = distance * plan[at + DAB_SCALE];
  let point = plan[at + DAB_POINT];
  var f15: u32;
  if (point >= 15u) {
    f15 = position >> (point - 15u);
  } else {
    f15 = position << (15u - point);
  }
  return vec2<u32>(position >> point, f15 & 0x7fffu);
}

// A square table at (across, down): along the row, then down.
fn dab_square(table: u32, row: u32, across: vec2<u32>, down: vec2<u32>) -> u32 {
  let above = table + down.x * row + across.x;
  return dab_lerp(
    dab_between(above, across.y),
    dab_between(above + row, across.y),
    down.y,
  );
}

// What a round tip lays at (dx, dy) and what of it piles — the pile read
// only where the tip holds an edge (DAB_EDGE_HELD), and 0 elsewhere, as
// the C engine leaves it.
fn dab_round(at: u32, flags: u32, dx: i32, dy: i32) -> vec2<u32> {
  let reach = plan[at + DAB_REACH];
  let held = (flags & DAB_EDGE_HELD) != 0u;
  let row = plan[at + DAB_ROW];
  if (row != 0u) {
    // A small circle, read by its square's whole area at (|dx|, |dy|).
    let across = u32(abs(dx));
    let down = u32(abs(dy));
    if (across >= reach || down >= reach) {
      return vec2<u32>(0u);
    }
    let i = dab_entry(at, across);
    let j = dab_entry(at, down);
    var pile = 0u;
    if (held) {
      pile = dab_square(plan[at + DAB_PILE], row, i, j);
    }
    return vec2<u32>(dab_square(plan[at + DAB_COVERAGE], row, i, j), pile);
  }
  // round(√n) >= reach exactly when n + reach > reach², so a pixel past
  // the reach takes no root. |dx|, |dy| <= 2^15, so n <= 2^31.
  let n = u32(dx * dx) + u32(dy * dy);
  if (n + reach > reach * reach) {
    return vec2<u32>(0u);
  }
  let distance = isqrt_round(n);
  if (i32(distance) <= bitcast<i32>(plan[at + DAB_INNER])) {
    return vec2<u32>(W_ONE, W_ONE);
  }
  let entry = dab_entry(at, distance);
  var pile = 0u;
  if (held) {
    pile = dab_between(plan[at + DAB_PILE] + entry.x, entry.y);
  }
  return vec2<u32>(dab_between(plan[at + DAB_COVERAGE] + entry.x, entry.y), pile);
}

// The brush's edge on a coverage (qa_dab_edge): a cut at half, or a
// contrast about half — 256, a contrast of 1, gives the coverage back.
fn dab_edge(at: u32, flags: u32, cover: u32) -> u32 {
  if ((flags & DAB_THRESHOLD) != 0u) {
    return select(0u, W_ONE, cover >= 32768u);
  }
  let spread = (i32(cover) - 32768) * i32(plan[at + DAB_CONTRAST]);
  return u32(clamp(((spread + 128) >> 8u) + 32768, 0, i32(W_ONE)));
}

// What a dab would lay whole, through its share (qa_dab_even): the table's
// 1025 entries span 0..=1, and a 1026th repeats the last, so `whole` at 1
// reads its pair like any other.
fn dab_even(at: u32, whole: u32) -> u32 {
  let table = plan[at + DAB_EVENING];
  if (table == NO_TABLE) {
    return whole;
  }
  let scaled = whole * 1024u;
  let index = scaled / W_ONE;
  let f15 = ((scaled - index * W_ONE) * 32768u) / W_ONE;
  return dab_between(table + index, f15);
}

// The dab whose record is at `at` laid on `under`, the pixel at (x, y).
fn dab_lay(at: u32, x: i32, y: i32, under: vec4<u32>) -> vec4<u32> {
  if (x < bitcast<i32>(plan[at + DAB_LEFT]) || x >= bitcast<i32>(plan[at + DAB_RIGHT])
      || y < bitcast<i32>(plan[at + DAB_TOP]) || y >= bitcast<i32>(plan[at + DAB_BOTTOM])) {
    return under;
  }
  let flags = plan[at + DAB_FLAGS];
  // A square dab covers its region whole.
  var cover = W_ONE;
  var pile = 0u;
  if ((flags & DAB_ROUND) != 0u) {
    // The pixel's centre from the dab's, in 1/256 px, then shifted.
    let shift = plan[at + DAB_SHIFT];
    let dx = dab_shrunk(x * 256 + 128 - bitcast<i32>(plan[at + DAB_CX]), shift);
    let dy = dab_shrunk(y * 256 + 128 - bitcast<i32>(plan[at + DAB_CY]), shift);
    let laid = dab_round(at, flags, dx, dy);
    cover = laid.x;
    pile = laid.y;
    if (cover == 0u) {
      return under;
    }
  }
  cover = dab_edge(at, flags, cover);
  if (cover == 0u) {
    return under;
  }
  // 🚨THE EDGE DOES NOT PILE (qa_dab_blend_tile's `ceiling`): the share of
  // the dab's opacity the stroke may come up to here.
  var ceiling = W_ONE;
  if ((flags & DAB_EDGE_HELD) != 0u && pile > cover) {
    ceiling = blend_div(cover, pile);
  }
  let opacity = plan[at + DAB_OPACITY];
  let effective = blend_mul(opacity, cover);
  if (effective == 0u) {
    return under;
  }
  let norm = plan[at + DAB_NORM];
  let flow = plan[at + DAB_FLOW];
  let erase = (flags & DAB_ERASE) != 0u;
  var source: u32;
  if (erase || (opacity == W_ONE && ceiling == W_ONE)) {
    source = dab_even(at, blend_mul(blend_mul(norm, effective), flow));
  } else {
    // 🚨A DAB'S OPACITY IS THE LEVEL IT SETTLES AT (qa_dab_source_alpha):
    // it raises the stroke towards it, never past.
    let settle = blend_mul(opacity, ceiling);
    if (under.w >= settle) {
      return under;
    }
    var share = W_ONE;
    if (cover < ceiling) {
      share = blend_div(cover, ceiling);
    }
    let whole = dab_even(at, blend_mul(blend_mul(norm, share), flow));
    source = blend_mul(whole, blend_div(settle - under.w, W_ONE - under.w));
  }
  if (erase) {
    return blend_erase(source, under);
  }
  let colour = plan[at + DAB_COLOUR];
  let laid = vec4<u32>(colour & 0xffu, (colour >> 8u) & 0xffu, (colour >> 16u) & 0xffu, 0u) * 257u;
  return blend_composite(BLEND_NORMAL, vec4<u32>(laid.xyz, source), under);
}

@compute @workgroup_size(8, 8)
fn walk(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_id) local: vec3<u32>,
) {
  let tile = group.z * TILE_WORDS;
  let lx = group.x * 8u + local.x;
  let ly = group.y * 8u + local.y;
  let x = bitcast<i32>(plan[tile + TILE_COLUMN]) * i32(TILE_SIDE) + i32(lx);
  let y = bitcast<i32>(plan[tile + TILE_ROW]) * i32(TILE_SIDE) + i32(ly);
  let texel = plan[tile + TILE_SLOT] * TILE_TEXELS + tile_texel(lx, ly);
  let low = planes[texel * 2u];
  let high = planes[texel * 2u + 1u];
  var pixel = vec4<u32>(low & 0xffffu, low >> 16u, high & 0xffffu, high >> 16u);
  let first = plan[tile + TILE_FIRST];
  let count = plan[tile + TILE_COUNT];
  for (var k = 0u; k < count; k = k + 1u) {
    pixel = dab_lay(plan[first + k], x, y, pixel);
  }
  planes[texel * 2u] = pixel.x | (pixel.y << 16u);
  planes[texel * 2u + 1u] = pixel.z | (pixel.w << 16u);
  view[texel] = blend_pack8(pixel);
}
