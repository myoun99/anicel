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

// The plan: its head; the textures, kept from pile to pile; then the
// pile's own — the stroke tiles, TILE_WORDS each; the lists of the dabs
// that reach each, a dab's record's place a word; the records, DAB_WORDS
// each; the tables, an entry a word. Every place is a word of the plan.
@group(0) @binding(0) var<storage, read> plan: array<u32>;
// The stroke tiles' planes, a slot TILE_TEXELS pixels, two words a pixel:
// red and green, then blue and alpha, the low half first.
@group(0) @binding(1) var<storage, read_write> planes: array<u32>;
// Their bytes, the planes' view (blend_pack8, dab_shown), a word a pixel.
@group(0) @binding(2) var<storage, read_write> view: array<u32>;
// The second tip's plane, alpha alone, a word a pixel as the view — where
// the stroke has a second tip; a word of nothing where it has none.
@group(0) @binding(3) var<storage, read_write> levels: array<u32>;

// The head: where the tiles start; the stroke's paper — its texture's
// place, NO_TABLE for none; its side; a pixel's step across it in 1/65536
// texel; and 1 where its height cuts (高さ) —; and the view of its second
// tip — the mode, NO_TABLE for none, and the density.
const HEAD_TILES: u32 = 0u;
const HEAD_PAPER: u32 = 1u;
const HEAD_PAPER_SIDE: u32 = 2u;
const HEAD_PAPER_STEP: u32 = 3u;
const HEAD_PAPER_HEIGHT: u32 = 4u;
const HEAD_SECOND: u32 = 5u;
const HEAD_SECOND_DENSITY: u32 = 6u;

// A stroke tile: its column and row on the canvas's grid, its slot, where
// its list starts and how long it is, and where on the paper its first
// column and row lie, in 1/65536 texel.
const TILE_COLUMN: u32 = 0u;
const TILE_ROW: u32 = 1u;
const TILE_SLOT: u32 = 2u;
const TILE_FIRST: u32 = 3u;
const TILE_COUNT: u32 = 4u;
const TILE_PAPER_ACROSS: u32 = 5u;
const TILE_PAPER_DOWN: u32 = 6u;
const TILE_WORDS: u32 = 7u;

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
// A round tip's or a bitmap tip's, distances in units of the shift they
// are taken at (1a 보탬 기하): the shift; the guard, at or past which along
// either axis nothing is laid; the turn's cosine and sine in Q15 and the
// roundness's inverse in Q16; the most the major axis and the minor —
// before it is stretched — reach, the major's being a round tip's reach
// and a bitmap's radius.
const DAB_SHIFT: u32 = 13u;
const DAB_GUARD: u32 = 14u;
const DAB_COS: u32 = 15u;
const DAB_SIN: u32 = 16u;
const DAB_INVERSE: u32 = 17u;
const DAB_MAJOR: u32 = 18u;
const DAB_MINOR: u32 = 19u;
// A round tip's: its inner radius — signed, under 0 where it has none —,
// the tables' entries per unit of a distance in Q(DAB_POINT), the entries a
// row holds where the tables are square (0 where they run along the
// radius), and the two tables.
const DAB_INNER: u32 = 20u;
const DAB_SCALE: u32 = 21u;
const DAB_POINT: u32 = 22u;
const DAB_ROW: u32 = 23u;
const DAB_COVERAGE: u32 = 24u;
const DAB_PILE: u32 = 25u;
// A bitmap tip's: its texels, a side's worth a row, NO_TABLE for any other
// dab, and its side.
const DAB_TIP: u32 = 26u;
const DAB_SIDE: u32 = 27u;
// How much of the paper it takes, on the 16-bit scale — NO_TABLE where it
// takes none.
const DAB_DENSITY: u32 = 28u;

// The C engine's flags (QA_DAB_FLAG_*), the ones this kernel reads.
const DAB_ERASE: u32 = 1u;
const DAB_ROUND: u32 = 2u;
const DAB_THRESHOLD: u32 = 32u;
const DAB_EDGE_HELD: u32 = 128u;
const DAB_SECOND: u32 = 256u;

const NO_TABLE: u32 = 0xffffffffu;
// What dab_source gives where a dab lays nothing: no alpha is as high.
const NOTHING: u32 = 0xffffffffu;

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
// scale under 2^17, so their product stays in u32; the point is 15 or more
// (mod.rs refuses a table finer than that).
fn dab_entry(at: u32, distance: u32) -> vec2<u32> {
  let position = distance * plan[at + DAB_SCALE];
  let point = plan[at + DAB_POINT];
  return vec2<u32>(position >> point, (position >> (point - 15u)) & 0x7fffu);
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

// (dx, dy) in the tip's own frame: turned, its minor axis stretched to the
// major — or nothing past the tip, as qa_dab_blend_tile culls it: either
// axis past the major's reach. The minor is first held to its own reach,
// which keeps the stretch's product in u32. |dx|, |dy| are under the guard,
// under 2^15, so each product of the turn stays under 2^30. A circle turns
// by nothing and stretches by 1 (cos 32768, sin 0, inverse 65536), and
// comes out as it went in, to the bit.
fn dab_turned(at: u32, dx: i32, dy: i32) -> vec3<i32> {
  let cos = bitcast<i32>(plan[at + DAB_COS]);
  let sin = bitcast<i32>(plan[at + DAB_SIN]);
  let u = (dx * cos - dy * sin + 16384) >> 15u;
  let v = (dx * sin + dy * cos + 16384) >> 15u;
  let major = plan[at + DAB_MAJOR];
  if (u32(abs(u)) > major || u32(abs(v)) > plan[at + DAB_MINOR]) {
    return vec3<i32>(0, 0, 0);
  }
  let stretched = (u32(abs(v)) * plan[at + DAB_INVERSE] + 32768u) >> 16u;
  if (stretched > major) {
    return vec3<i32>(0, 0, 0);
  }
  return vec3<i32>(u, select(i32(stretched), -i32(stretched), v < 0), 1);
}

// Where u lands on a bitmap tip of `side` texels over [-radius, radius]:
// one past its texel — t = 2(u + radius)·side − 2·radius over 4·radius
// texels (1a 보탬), a texel on so that it is never under 0 —, and the next
// 15 bits of the way to the one after, cut. 4·radius is under 2^17 and the
// side at most 16384, so t and the remainder's shift stay in u32.
fn dab_texel(u: i32, radius: u32, side: u32) -> vec2<u32> {
  let span = 4u * radius;
  let t = 2u * u32(u + i32(radius)) * side + 2u * radius;
  return vec2<u32>(t / span, ((t % span) << 15u) / span);
}

// The tip's texel one past (column, row) — 0 off the tip, as the C engine
// reads one.
fn dab_tip_texel(tip: u32, side: u32, column: u32, row: u32) -> u32 {
  if (column == 0u || row == 0u || column > side || row > side) {
    return 0u;
  }
  return plan[tip + (row - 1u) * side + column - 1u];
}

// What a bitmap tip lays at (u, v), between its four nearest texels: along
// the row, then down (qa_sample_tip_scalar).
fn dab_tip(at: u32, tip: u32, u: i32, v: i32) -> u32 {
  let radius = plan[at + DAB_MAJOR];
  let side = plan[at + DAB_SIDE];
  let x = dab_texel(u, radius, side);
  let y = dab_texel(v, radius, side);
  let top = dab_lerp(
    dab_tip_texel(tip, side, x.x, y.x),
    dab_tip_texel(tip, side, x.x + 1u, y.x),
    x.y,
  );
  let bottom = dab_lerp(
    dab_tip_texel(tip, side, x.x, y.x + 1u),
    dab_tip_texel(tip, side, x.x + 1u, y.x + 1u),
    x.y,
  );
  return dab_lerp(top, bottom, y.y);
}

// Pixel `local` of a tile on the paper, along one axis: the texel before
// its centre, and the next 15 bits of the way to the one after, cut. The
// tile's first pixel lies at `phase`; each pixel on is a step further —
// c(x) = ((2x + 1)·step >> 1) mod side·2^16 (mod.rs's paper_at). The step
// is taken a texel and a fraction apart, the texels wrapped by the side,
// so every term stays in u32: the phase, the texels and the texel added
// to keep half a texel back above 0 each under side·2^16 ≤ 2^30, the
// fraction's product under 2^23. What a whole number of sides more adds
// the side wraps away when read.
fn dab_paper_along(phase: u32, local: u32, side: u32) -> vec2<u32> {
  let step = plan[HEAD_PAPER_STEP];
  let texels = (local * (step >> 16u)) % side;
  let at = phase + (texels << 16u) + local * (step & 0xffffu);
  let before = at + (side << 16u) - 32768u;
  return vec2<u32>((before >> 16u) % side, (before & 0xffffu) >> 1u);
}

// What the paper stands at pixel (lx, ly) of the tile at `tile`: between
// its four nearest texels, along the row, then down, wrapping as it tiles
// the canvas (sampleBrushTipMaskTiledCoverageLattice). Every dab on the
// pixel meets the same paper, so it is read once, before the walk.
fn dab_paper(tile: u32, lx: u32, ly: u32) -> u32 {
  let paper = plan[HEAD_PAPER];
  let side = plan[HEAD_PAPER_SIDE];
  let x = dab_paper_along(plan[tile + TILE_PAPER_ACROSS], lx, side);
  let y = dab_paper_along(plan[tile + TILE_PAPER_DOWN], ly, side);
  let next = (x.x + 1u) % side;
  let row = paper + y.x * side;
  let below = paper + ((y.x + 1u) % side) * side;
  return dab_lerp(
    dab_lerp(plan[row + x.x], plan[row + next], x.y),
    dab_lerp(plan[below + x.x], plan[below + next], x.y),
    y.y,
  );
}

// What a round tip lays at (u, v) and what of it piles — the pile read
// only where the tip holds an edge (DAB_EDGE_HELD), and 0 elsewhere, as
// the C engine leaves it.
fn dab_round(at: u32, flags: u32, u: i32, v: i32) -> vec2<u32> {
  let reach = plan[at + DAB_MAJOR];
  let across = u32(abs(u));
  let down = u32(abs(v));
  let held = (flags & DAB_EDGE_HELD) != 0u;
  let row = plan[at + DAB_ROW];
  if (row != 0u) {
    // A small circle, read by its square's whole area at (|dx|, |dy|).
    let i = dab_entry(at, across);
    let j = dab_entry(at, down);
    var pile = 0u;
    if (held) {
      pile = dab_square(plan[at + DAB_PILE], row, i, j);
    }
    return vec2<u32>(dab_square(plan[at + DAB_COVERAGE], row, i, j), pile);
  }
  // round(√n) >= reach exactly when n + reach > reach², so a pixel past
  // the reach takes no root.
  let n = across * across + down * down;
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

// Whether the dab erases: a second tip's dab piles over, never erases
// (qa_dab_blend_tile).
fn dab_erases(flags: u32) -> bool {
  return (flags & (DAB_ERASE | DAB_SECOND)) == DAB_ERASE;
}

// What the dab whose record is at `at` lays at the pixel (x, y) over a
// stroke standing `under` high there: its source alpha, or NOTHING.
fn dab_source(at: u32, x: i32, y: i32, under: u32, paper: u32) -> u32 {
  if (x < bitcast<i32>(plan[at + DAB_LEFT]) || x >= bitcast<i32>(plan[at + DAB_RIGHT])
      || y < bitcast<i32>(plan[at + DAB_TOP]) || y >= bitcast<i32>(plan[at + DAB_BOTTOM])) {
    return NOTHING;
  }
  let flags = plan[at + DAB_FLAGS];
  // A square dab covers its region whole.
  var cover = W_ONE;
  var pile = 0u;
  let tip = plan[at + DAB_TIP];
  if ((flags & DAB_ROUND) != 0u || tip != NO_TABLE) {
    // The pixel's centre from the dab's, in 1/256 px, then shifted.
    let shift = plan[at + DAB_SHIFT];
    let dx = dab_shrunk(x * 256 + 128 - bitcast<i32>(plan[at + DAB_CX]), shift);
    let dy = dab_shrunk(y * 256 + 128 - bitcast<i32>(plan[at + DAB_CY]), shift);
    // Nothing at or past the guard along either axis — and so nothing
    // below overflows, however far the region runs.
    let guard = plan[at + DAB_GUARD];
    if (u32(abs(dx)) >= guard || u32(abs(dy)) >= guard) {
      return NOTHING;
    }
    let turned = dab_turned(at, dx, dy);
    if (turned.z == 0) {
      return NOTHING;
    }
    if (tip != NO_TABLE) {
      cover = dab_tip(at, tip, turned.x, turned.y);
    } else {
      let laid = dab_round(at, flags, turned.x, turned.y);
      cover = laid.x;
      pile = laid.y;
    }
    if (cover == 0u) {
      return NOTHING;
    }
  }
  cover = dab_edge(at, flags, cover);
  if (cover == 0u) {
    return NOTHING;
  }
  // 🚨THE EDGE DOES NOT PILE (qa_dab_blend_tile's `ceiling`): the share of
  // the dab's opacity the stroke may come up to here.
  var ceiling = W_ONE;
  if ((flags & DAB_EDGE_HELD) != 0u && pile > cover) {
    ceiling = blend_div(cover, pile);
  }
  // The paper, after the edge and its ceiling (qa_dab_blend_spans): it
  // takes from what the dab covers, not from how high the stroke may come.
  let density = plan[at + DAB_DENSITY];
  if (plan[HEAD_PAPER] != NO_TABLE && density != NO_TABLE) {
    if (plan[HEAD_PAPER_HEIGHT] != 0u) {
      // 高さ: touched where the paper stands above the dab's floor, fully
      // a quarter above it (paperHeightBand).
      let touched = (i32(paper) + i32(blend_mul(density, cover)) - 65535) * 4;
      cover = u32(clamp(touched, 0, 65535));
    } else {
      cover = blend_mul(cover, W_ONE - density + blend_mul(density, paper));
    }
  }
  let opacity = plan[at + DAB_OPACITY];
  let effective = blend_mul(opacity, cover);
  if (effective == 0u) {
    return NOTHING;
  }
  let norm = plan[at + DAB_NORM];
  let flow = plan[at + DAB_FLOW];
  if (dab_erases(flags) || (opacity == W_ONE && ceiling == W_ONE)) {
    return dab_even(at, blend_mul(blend_mul(norm, effective), flow));
  }
  // 🚨A DAB'S OPACITY IS THE LEVEL IT SETTLES AT (qa_dab_source_alpha): it
  // raises the stroke towards it, never past.
  let settle = blend_mul(opacity, ceiling);
  if (under >= settle) {
    return NOTHING;
  }
  var share = W_ONE;
  if (cover < ceiling) {
    share = blend_div(cover, ceiling);
  }
  let whole = dab_even(at, blend_mul(blend_mul(norm, share), flow));
  return blend_mul(whole, blend_div(settle - under, W_ONE - under));
}

// The first tip's dab whose record is at `at` laid on `under`, the pixel at
// (x, y).
fn dab_lay(at: u32, x: i32, y: i32, under: vec4<u32>, paper: u32) -> vec4<u32> {
  let source = dab_source(at, x, y, under.w, paper);
  if (source == NOTHING) {
    return under;
  }
  if (dab_erases(plan[at + DAB_FLAGS])) {
    return blend_erase(source, under);
  }
  let colour = plan[at + DAB_COLOUR];
  let laid = vec4<u32>(colour & 0xffu, (colour >> 8u) & 0xffu, (colour >> 16u) & 0xffu, 0u) * 257u;
  return blend_composite(BLEND_NORMAL, vec4<u32>(laid.xyz, source), under);
}

// What a stroke with a second tip shows where its first plane stands
// `first` high and its second `level` (qa_dual_view_rows, which has the
// law): the second blended over the first by the stroke's mode at its
// density — the second the source, the first the destination. Where the
// first tip laid nothing, nothing shows.
fn dab_shown(first: u32, level: u32) -> u32 {
  if (first == 0u) {
    return 0u;
  }
  let mode = plan[HEAD_SECOND];
  let density = plan[HEAD_SECOND_DENSITY];
  if (mode == BLEND_MULTIPLY) {
    // ⛔MULTIPLY KEEPS ITS OWN LINE (qa_dual_view_rows): a·((1 − d) + d·s),
    // the default written plainly — the general form is the same number
    // and not the same rounding.
    return blend_mul(first, W_ONE - density + blend_mul(density, level));
  }
  // Never past W_ONE, which the C engine's double could round to: as
  // blend_mul only rises with what it multiplies, the two terms come to
  // at most W_ONE − density and density.
  return blend_mul(first, W_ONE - density) + blend_mul(density, blend_channel(mode, level, first));
}

@compute @workgroup_size(8, 8)
fn walk(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_id) local: vec3<u32>,
) {
  let tile = plan[HEAD_TILES] + group.z * TILE_WORDS;
  let lx = group.x * 8u + local.x;
  let ly = group.y * 8u + local.y;
  let x = bitcast<i32>(plan[tile + TILE_COLUMN]) * i32(TILE_SIDE) + i32(lx);
  let y = bitcast<i32>(plan[tile + TILE_ROW]) * i32(TILE_SIDE) + i32(ly);
  let texel = plan[tile + TILE_SLOT] * TILE_TEXELS + tile_texel(lx, ly);
  var pixel = blend_unpack16(vec2<u32>(planes[texel * 2u], planes[texel * 2u + 1u]));
  var paper = 0u;
  if (plan[HEAD_PAPER] != NO_TABLE) {
    paper = dab_paper(tile, lx, ly);
  }
  let shown = plan[HEAD_SECOND] != NO_TABLE;
  var level = 0u;
  if (shown) {
    level = levels[texel];
  }
  let first = plan[tile + TILE_FIRST];
  let count = plan[tile + TILE_COUNT];
  for (var k = 0u; k < count; k = k + 1u) {
    let at = plan[first + k];
    if ((plan[at + DAB_FLAGS] & DAB_SECOND) == 0u) {
      pixel = dab_lay(at, x, y, pixel, paper);
      continue;
    }
    // A second tip's dab piles its plane as any dab piles its alpha. On a
    // stroke with no second plane it lays nothing (qa_dab_blend_tile).
    let source = dab_source(at, x, y, level, paper);
    if (source != NOTHING) {
      level = blend_alpha_over(source, level);
    }
  }
  let pair = blend_pack16(pixel);
  planes[texel * 2u] = pair.x;
  planes[texel * 2u + 1u] = pair.y;
  if (shown) {
    levels[texel] = level;
    view[texel] = blend_pack8(vec4<u32>(pixel.xyz, dab_shown(pixel.w, level)));
  } else {
    view[texel] = blend_pack8(pixel);
  }
}
