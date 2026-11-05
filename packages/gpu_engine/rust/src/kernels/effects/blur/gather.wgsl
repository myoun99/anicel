// A camera lens blur's iris gathered out of its row sums — the app's
// iris_gather.frag, by gpu-int-spec-canvas 1b (4/4): every pixel of the
// picture the mean of the pixels about it whose centres its iris covers,
// each row of it two reads of that row's sums (sums.wgsl), its rows out of
// the iris's table (iris_table.wgsl) at the level the pixel reads — the
// first, or the one a blur map names. The fringe pushes a share of the
// core's light out to the edge; past the picture there is nothing, or —
// AE's Repeat Edge Pixels — the paper's edge pixels, and what is drawn is
// cut to the paper. What is gathered is stored through the light
// (light.wgsl), as the sums read it.
//
// Needs shared/wide.wgsl, shared/premultiply.wgsl, light.wgsl and held.wgsl
// (held: the tiles in and out).

// The gather's own words: the light; the picture its sums lie over and
// the paper, [left, top, right, bottom); whether the paper repeats its
// edge; the fringe's share (Q.16, to 1); the table's reach, rows and
// levels; and what of a blur map's pixel names its level (MAP_*).
struct Gather {
  light: Light,
  picture_left: i32,
  picture_top: i32,
  picture_right: i32,
  picture_bottom: i32,
  paper_left: i32,
  paper_top: i32,
  paper_right: i32,
  paper_bottom: i32,
  repeats: u32,
  fringe: u32,
  reach: u32,
  rows: u32,
  levels: u32,
  channel: u32,
}

// A map's channel: one of its premultiplied bytes, red to alpha, or its luma.
const MAP_LUMA: u32 = 4u;

@group(0) @binding(3) var<uniform> gather: Gather;
@group(0) @binding(4) var<storage, read> gather_sums: array<u32>;
@group(0) @binding(5) var<storage, read> gather_table: array<u32>;
@group(0) @binding(6) var<storage, read> gather_map: array<u32>;

// The sum of row y of the picture up to column x, each channel.
fn gather_sum(x: i32, y: i32) -> array<Wide, 4> {
  let width = u32(gather.picture_right - gather.picture_left);
  let at = held_plane_word(x, y, gather.picture_left, gather.picture_top, width, 8u);
  return array<Wide, 4>(
    Wide(gather_sums[at], gather_sums[at + 1u]),
    Wide(gather_sums[at + 2u], gather_sums[at + 3u]),
    Wide(gather_sums[at + 4u], gather_sums[at + 5u]),
    Wide(gather_sums[at + 6u], gather_sums[at + 7u]),
  );
}

// Row y's pixels from column a to b that lie in `first` … `last`, summed:
// two reads of its sums.
fn gather_between(a: i32, b: i32, first: i32, last: i32, y: i32) -> array<Wide, 4> {
  var sum = array<Wide, 4>();
  let left = max(a, first);
  let right = min(b, last);
  if (left > right) {
    return sum;
  }
  sum = gather_sum(right, y);
  if (left > gather.picture_left) {
    let before = gather_sum(left - 1, y);
    for (var c = 0u; c < 4u; c++) {
      sum[c] = wide_sub(sum[c], before[c]);
    }
  }
  return sum;
}

// Adds `count` of the pixel at (x, y), as the light reads it, to `sum`.
fn gather_add_pixel(sum: ptr<function, array<Wide, 4>>, x: i32, y: i32, count: i32) {
  let pixel = light_read(pixels_in[held_tile_word(x, y)], gather.light);
  for (var c = 0u; c < 4u; c++) {
    (*sum)[c] = wide_add((*sum)[c], wide_mul_u32(pixel[c], u32(count)));
  }
}

// Row y's pixels from column a to b summed, as the edge has it: nothing
// past the paper — the picture, where none repeats — or its edge pixels
// again.
fn gather_row(a: i32, b: i32, y: i32) -> array<Wide, 4> {
  let first = gather.paper_left;
  let last = gather.paper_right - 1;
  var sum = gather_between(a, b, first, last, y);
  if (gather.repeats == 0u) {
    return sum;
  }
  // How far the row reaches past each edge — none or less where it ends
  // short of it (a count of none would add nothing: `>= 0` is one guard).
  let before = min(b, first - 1) - a + 1;
  if (before > 0) {
    gather_add_pixel(&sum, first, y, before);
  }
  let after = b - max(a, last + 1) + 1;
  if (after > 0) {
    gather_add_pixel(&sum, last, y, after);
  }
  return sum;
}

// The level pixel (x, y) reads: the first, or its blur map's value through
// the channel — of the map's pixel premultiplied, as the app's texture
// holds it.
fn gather_level(x: i32, y: i32) -> u32 {
  if (gather.levels == 1u) {
    return 0u;
  }
  let word = premultiply8(gather_map[held_tile_word(x, y)]);
  let bytes = vec4<u32>(word & 0xffu, (word >> 8u) & 0xffu, (word >> 16u) & 0xffu, word >> 24u);
  if (gather.channel == MAP_LUMA) {
    return light_luma(bytes.xyz);
  }
  return bytes[gather.channel];
}

// Level `level`'s outline (k 0) or core (k 1) on table row `row`: its left
// and right column about the pixel.
fn gather_run(level: u32, k: u32, row: u32) -> vec2<i32> {
  let at = ((level * 2u + k) * gather.rows + row) * 2u;
  return vec2<i32>(bitcast<i32>(gather_table[at]), bitcast<i32>(gather_table[at + 1u]));
}

@compute @workgroup_size(8, 8, 1)
fn iris_gather(@builtin(global_invocation_id) id: vec3<u32>) {
  let x = gather.picture_left + i32(id.x);
  let y = gather.picture_top + i32(id.y);
  // Only the paper is drawn — the picture, where none repeats: the tiles
  // out hold nothing past it already.
  let on_paper = x >= gather.paper_left && x < gather.paper_right
    && y >= gather.paper_top && y < gather.paper_bottom;
  if (!on_paper) {
    return;
  }
  let level = gather_level(x, y);
  let head = gather.levels * 2u * gather.rows * 2u + level * 4u;
  // The level's own reach, and the core only where a fringe pushes from it
  // — for the work alone: past its reach a level's runs are empty, and
  // what is not pushed the core does not weigh (gather mutants g20 and
  // g21, 11-05: no value tells either from the table's whole reach).
  let reach = i32(gather_table[head]);
  let fringed = gather.fringe > 0u;
  let on_outline = gather_table[head + 1u];
  let on_core = gather_table[head + 2u];
  var outline = array<Wide, 4>();
  var core = array<Wide, 4>();
  for (var dy = -reach; dy <= reach; dy++) {
    var row_y = y + dy;
    if (gather.repeats == 1u) {
      row_y = clamp(row_y, gather.paper_top, gather.paper_bottom - 1);
    } else if (row_y < gather.picture_top || row_y >= gather.picture_bottom) {
      continue;
    }
    let row = u32(dy + i32(gather.reach));
    let run = gather_run(level, 0u, row);
    let sum = gather_row(x + run.x, x + run.y, row_y);
    for (var c = 0u; c < 4u; c++) {
      outline[c] = wide_add(outline[c], sum[c]);
    }
    if (fringed) {
      let run = gather_run(level, 1u, row);
      let sum = gather_row(x + run.x, x + run.y, row_y);
      for (var c = 0u; c < 4u; c++) {
        core[c] = wide_add(core[c], sum[c]);
      }
    }
  }
  // The outline's pixels weigh 2^16, the core's 2^16 less the share
  // pushed — where the edge holds a pixel the core does not.
  let pushed = select(0u, gather.fringe, on_outline > on_core);
  let weight = wide_sub(wide_mul_u32(on_outline, 65536u), wide_mul_u32(on_core, pushed));
  let at = held_tile_word(x, y);
  var mean: vec4<u32>;
  if (wide_less(Wide(0u, 0u), weight)) {
    for (var c = 0u; c < 4u; c++) {
      let kept = wide128_add(
        wide_mul128(outline[c], Wide(65536u, 0u)),
        wide128_neg(wide_mul128(core[c], Wide(pushed, 0u))),
      );
      // A mean of pixels, so no channel past the brightest: under 2^23.
      mean[c] = wide128_divr(kept, weight, 23u).x;
    }
  } else {
    // An iris that covers no centre — a blur map's in focus — is the pixel.
    mean = light_read(pixels_in[at], gather.light);
  }
  pixels_out[at] = light_stored(mean, gather.light);
}
