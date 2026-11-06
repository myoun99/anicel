// A camera lens blur's iris, row by row — the app's iris_table.frag, by
// the integer spec gpu-int-spec-canvas 1b (4/4): for each shape (a level's
// outline, then its core) and each row about a pixel, the columns whose
// centres it covers; then each level's head — its reach and the centres
// its outline and its core cover. The gather reads a row's sums by these.
//
// The iris is a regular polygon, rounded: the polygon drawn smaller, the
// strip outward of each edge and the disc about each corner (iris.rs has
// the shape). A row is P(t) = dy·E + t·D in the iris's own space scaled by
// A·U — unturned and unsqueezed, so no division by the squeeze —, and a
// piece's columns are where it holds P(t), each bound worked out exactly:
// a half-plane's by one floor division, a disc's by an integer square
// root. A centre within 2^-10 pixel of a bound is on it (the app's
// kOnTheEdge). The row's columns are those of every piece it crosses,
// joined: the iris is convex, so they are one run.
//
// Needs shared/wide.wgsl before it.

// The words of a shape in `iris_shapes`: its reach, which pieces it has
// (1 the polygon, 2 the strips and discs), the polygon's and the strips'
// outer bound and the strips' half width (Q.30 px · A·U, two words each),
// the discs' radius (Q.16 px · A·U), then a corner's centre for each of
// the most sides, ten (Q.16 px · A·U, x then y).
const IRIS_SHAPE_WORDS: u32 = 29u;
const IRIS_POLYGON: u32 = 1u;
const IRIS_ROUNDED: u32 = 2u;
// 2^-10 pixel, the app's kOnTheEdge as a power of two.
const IRIS_EDGE_BITS: u32 = 10u;

// The table: its rows either way of a pixel and all of them, its shapes,
// its sides; A·U (Q.30) and 1 / |D| (Q.28); E, D / |D| and the
// perpendicular to it (Q.30).
struct IrisPass {
  reach: u32,
  rows: u32,
  shapes: u32,
  sides: u32,
  squeeze: u32,
  inverse: u32,
  e_x: i32,
  e_y: i32,
  along_x: i32,
  along_y: i32,
  across_x: i32,
  across_y: i32,
}

@group(0) @binding(0) var<uniform> iris: IrisPass;
// A side's normal and tangent against E and D: n·E, n·D, t·E, t·D (Q.30).
@group(0) @binding(1) var<storage, read> iris_sides: array<i32>;
@group(0) @binding(2) var<storage, read> iris_shapes: array<u32>;
// Each shape's rows, left and right column, row after row; then each
// level's head, four words.
@group(0) @binding(3) var<storage, read_write> iris_table: array<u32>;

const IRIS_NONE = vec2<i32>(1, 0);

// The farthest column a row's run reaches either way: the iris lies within
// its radius, and a centre within 2^-10 of it may be on it.
fn iris_most() -> i32 {
  return i32(iris.reach) + 1;
}

// ⌊(room · 2^10 + r) / (r · 2^10)⌋ for r > 0: the last column t ≤ room / r
// holds, a centre within 2^-10 of it on it — held to -iris_most() - 1 up
// to iris_most(), past which no row's run lies, so under 2^14. ⚠️One short
// of the most on the left: a bound that leaves every column past the most
// to the right must leave the run empty, as a left of the most + 1 does
// (11-05: a strip all past the most came out its one column).
fn iris_bound(room: Wide, r: i32) -> i32 {
  let rate = Wide(u32(r), 0u);
  let whole = wide_shl(rate, IRIS_EDGE_BITS);
  let lifted = wide_add(wide_shl(room, IRIS_EDGE_BITS), rate);
  let most = iris_most();
  let reach = wide_mul(whole, Wide(u32(most), 0u));
  if (!wide_negative(lifted)) {
    if (!wide_below(lifted, reach)) {
      return most;
    }
    return i32(wide_div_floor(lifted, whole, 14u));
  }
  let below = wide_neg(lifted);
  if (wide_below(reach, below)) {
    return -most - 1;
  }
  // ⌊−x / w⌋ = −⌈x / w⌉.
  return -i32(wide_div_floor(wide_add(below, wide_sub(whole, Wide(1u, 0u))), whole, 14u));
}

// `run` where n·P(t) ≤ bound: n·E is `slope`, n·D `rate`, the bound Q.30.
fn iris_cut(run: vec2<i32>, dy: i32, slope: i32, rate: i32, bound: Wide) -> vec2<i32> {
  let room = wide_sub(bound, wide_mul_i32(dy, slope));
  if (rate > 0) {
    return vec2<i32>(run.x, min(run.y, iris_bound(room, rate)));
  }
  if (rate < 0) {
    return vec2<i32>(max(run.x, -iris_bound(room, -rate)), run.y);
  }
  // Along the edge: kept where the row lies within 2^-10 of it — of p,
  // which room holds A·U times.
  if (wide_negative(wide_add(wide_shl(room, IRIS_EDGE_BITS), Wide(iris.squeeze, 0u)))) {
    return IRIS_NONE;
  }
  return run;
}

fn iris_shape_wide(at: u32) -> Wide {
  return Wide(iris_shapes[at], iris_shapes[at + 1u]);
}

// Side k's n·E, n·D, t·E and t·D, `sign` the way they face.
fn iris_side(k: u32, word: u32, sign: i32) -> i32 {
  return sign * iris_sides[k * 4u + word];
}

// The columns of row dy within `radius` (Q.16 · A·U) of the corner whose
// centre (Q.16 · A·U) is (cx, cy): where the row's line comes within it,
// half a chord either side of its nearest point.
fn iris_disc(dy: i32, cx: i32, cy: i32, radius: u32) -> vec2<i32> {
  // The corner to the row's t = 0, Q.16: under 2^14 pixels each way.
  let away_x = wide_sub(wide_round(wide_mul_i32(dy, iris.e_x), 14u), wide(cx)).x;
  let away_y = wide_sub(wide_round(wide_mul_i32(dy, iris.e_y), 14u), wide(cy)).x;
  let off = wide_round(
    wide_add(
      wide_mul_i32(iris.across_x, bitcast<i32>(away_x)),
      wide_mul_i32(iris.across_y, bitcast<i32>(away_y)),
    ),
    30u,
  );
  let along = wide_round(
    wide_add(
      wide_mul_i32(iris.along_x, bitcast<i32>(away_x)),
      wide_mul_i32(iris.along_y, bitcast<i32>(away_y)),
    ),
    30u,
  );
  let off_by = wide_abs(off);
  if (wide_below(Wide(radius, 0u), off_by)) {
    return IRIS_NONE;
  }
  let half = wide_isqrt(wide_sub(wide_mul_u32(radius, radius), wide_mul_u32(off_by.x, off_by.x)));
  let inverse = Wide(iris.inverse, 0u);
  // The chord's ends along D / |D|, then along t (Q.44).
  let first = wide_mul(wide_sub(wide_neg(along), Wide(half, 0u)), inverse);
  let last = wide_mul(wide_add(wide_neg(along), Wide(half, 0u)), inverse);
  let edge = wide_shl(Wide(1u, 0u), 44u - IRIS_EDGE_BITS);
  let left = wide_neg(wide_shr(wide_sub(edge, first), 44u));
  let right = wide_shr(wide_add(last, edge), 44u);
  return vec2<i32>(bitcast<i32>(left.x), bitcast<i32>(right.x));
}

fn iris_joined(whole: vec2<i32>, piece: vec2<i32>) -> vec2<i32> {
  if (piece.x > piece.y) {
    return whole;
  }
  if (whole.x > whole.y) {
    return piece;
  }
  return vec2<i32>(min(whole.x, piece.x), max(whole.y, piece.y));
}

// The columns shape `shape`'s row dy covers.
fn iris_row(shape: u32, dy: i32) -> vec2<i32> {
  let at = shape * IRIS_SHAPE_WORDS;
  let pieces = iris_shapes[at + 1u];
  let polygon_at = iris_shape_wide(at + 2u);
  let outer = iris_shape_wide(at + 4u);
  let half_side = iris_shape_wide(at + 6u);
  let rounding = iris_shapes[at + 8u];
  let most = iris_most();
  var whole = IRIS_NONE;
  var polygon = vec2<i32>(-most, most);
  for (var k = 0u; k < iris.sides; k++) {
    polygon = iris_cut(polygon, dy, iris_side(k, 0u, 1), iris_side(k, 1u, 1), polygon_at);
    if ((pieces & IRIS_ROUNDED) != 0u) {
      var strip = vec2<i32>(-most, most);
      strip = iris_cut(strip, dy, iris_side(k, 0u, 1), iris_side(k, 1u, 1), outer);
      strip = iris_cut(strip, dy, iris_side(k, 0u, -1), iris_side(k, 1u, -1), wide_neg(polygon_at));
      strip = iris_cut(strip, dy, iris_side(k, 2u, 1), iris_side(k, 3u, 1), half_side);
      strip = iris_cut(strip, dy, iris_side(k, 2u, -1), iris_side(k, 3u, -1), half_side);
      whole = iris_joined(whole, strip);
      let corner = at + 9u + k * 2u;
      whole = iris_joined(
        whole,
        iris_disc(
          dy, bitcast<i32>(iris_shapes[corner]), bitcast<i32>(iris_shapes[corner + 1u]), rounding,
        ),
      );
    }
  }
  if ((pieces & IRIS_POLYGON) != 0u) {
    whole = iris_joined(whole, polygon);
  }
  if (whole.x > whole.y) {
    return IRIS_NONE;
  }
  return whole;
}

@compute @workgroup_size(8, 8, 1)
fn iris_rows(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= iris.rows || id.y >= iris.shapes) {
    return;
  }
  let dy = i32(id.x) - i32(iris.reach);
  var run = IRIS_NONE;
  // A row past its level's reach covers nothing.
  if (u32(abs(dy)) <= iris_shapes[id.y * IRIS_SHAPE_WORDS]) {
    run = iris_row(id.y, dy);
  }
  let at = (id.y * iris.rows + id.x) * 2u;
  iris_table[at] = bitcast<u32>(run.x);
  iris_table[at + 1u] = bitcast<u32>(run.y);
}

// Each level's head: its reach, and the centres its outline and its core
// cover — all their rows; its fourth word stays as wgpu made it, nothing.
@compute @workgroup_size(64, 1, 1)
fn iris_heads(@builtin(global_invocation_id) id: vec3<u32>) {
  let level = id.x;
  if (level * 2u >= iris.shapes) {
    return;
  }
  let head = iris.shapes * iris.rows * 2u + level * 4u;
  iris_table[head] = iris_shapes[level * 2u * IRIS_SHAPE_WORDS];
  for (var k = 0u; k < 2u; k++) {
    var covered = 0u;
    for (var row = 0u; row < iris.rows; row++) {
      let at = ((level * 2u + k) * iris.rows + row) * 2u;
      let run = vec2<i32>(bitcast<i32>(iris_table[at]), bitcast<i32>(iris_table[at + 1u]));
      covered += u32(max(0, run.y - run.x + 1));
    }
    iris_table[head + 1u + k] = covered;
  }
}
