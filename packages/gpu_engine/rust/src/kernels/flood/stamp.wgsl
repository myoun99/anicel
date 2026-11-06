// A fill's colour stamp (`_colorStampDab`, R15-⑥; gpu-canonical-store
// stage 5): its finished mask in its colour, as the tiles of the row a
// stroke lands by — straight RGBA8, a pixel the mask covers at all its
// colour under the mask's byte for an alpha, one it covers none nothing,
// as the app's stamp holds them. The stamp blends nothing itself: the
// executor lays its row on the cel at the fill's opacity, in its mode and
// under the selection, as it lays a stroke (R28), and R10's stamp
// composite is that laying (gpu-canonical-store 1a 3/3 보탬).
//
// Under a gradient (I-160, `_gradientRgba`) a pixel is the stop its centre
// lies at instead, its alpha the stop's under the mask's byte.
//
// Needs shared/tile.wgsl, shared/wide.wgsl, shared/premultiply.wgsl and
// kernels/mask's byte.wgsl before it; defines byte.wgsl's `mask_word`.

struct Stamp {
  // The mask's box on the canvas: its left and top, its pixels across and
  // down, and the words a row of it (mask.wgsl's layout).
  left: i32,
  top: i32,
  width: u32,
  height: u32,
  stride: u32,
  // The canvas tile column and row of the stamp's first tile, and its
  // tiles across — the tiles of its box, row after row.
  column: i32,
  row: i32,
  columns: u32,
  // The stamp's tile this pass puts first, at the page's first slot.
  first: u32,
  // The colour, red in the low byte, its top byte 0.
  colour: u32,
  // The gradient's shape, and its `from` and `to − from` in 1/256 px.
  shape: u32,
  from_x: i32,
  from_y: i32,
  along_x: i32,
  along_y: i32,
  unused_0: u32,
}

@group(0) @binding(0) var<uniform> stamp: Stamp;
@group(0) @binding(1) var<storage, read> mask: array<u32>;
@group(0) @binding(2) var<storage, read_write> page: array<u32>;
// The gradient's stops, straight RGBA8 (`FillGradient.stops`).
@group(0) @binding(3) var<storage, read> stops: array<u32>;

const STAMP_LINE: u32 = 1u;
const STAMP_LAST_STOP: u32 = 1023u;

fn mask_word(at: u32) -> u32 {
  return mask[at];
}

// The canvas pixel thread `id` stamps, and the mask's byte there.
fn stamp_at(id: vec3<u32>) -> vec3<i32> {
  let tile = stamp.first + id.z;
  let x = (stamp.column + i32(tile % stamp.columns)) * i32(TILE_SIDE) + i32(id.x);
  let y = (stamp.row + i32(tile / stamp.columns)) * i32(TILE_SIDE) + i32(id.y);
  // A pixel past the box's left or top wraps past its width or height.
  let plane = MaskPlane(0u, stamp.width, stamp.height, stamp.stride);
  let byte = mask_byte_of(plane, u32(x - stamp.left), u32(y - stamp.top));
  return vec3<i32>(x, y, i32(byte));
}

fn stamp_put(id: vec3<u32>, word: u32) {
  page[id.z * TILE_TEXELS + tile_texel(id.x, id.y)] = word;
}

// A workgroup puts a 16 × 16 of a tile's pixels, 64 of them a tile, a
// tile a workgroup deep.
@compute @workgroup_size(16, 16, 1)
fn flood_stamp(@builtin(global_invocation_id) id: vec3<u32>) {
  let byte = u32(stamp_at(id).z);
  stamp_put(id, select(0u, stamp.colour | (byte << 24u), byte != 0u));
}

// The stop canvas pixel (x, y)'s centre lies at (`FillGradient.rowInto`):
// 0 at `from`, the last at `to` and past it, each the nearest — a half
// goes up, as the app's `+ 0.5` does. A line's is the centre's projection
// onto it, 0 behind `from`; a circle's its distance from `from` over the
// radius. A gradient of no length lays its first (I-160-Q5).
fn stamp_stop(x: i32, y: i32) -> u32 {
  let vx = x * 256 + 128 - stamp.from_x;
  let vy = y * 256 + 128 - stamp.from_y;
  let reach = wide_add(
    wide_mul_i32(stamp.along_x, stamp.along_x),
    wide_mul_i32(stamp.along_y, stamp.along_y),
  );
  if (all(reach == Wide(0u))) {
    return 0u;
  }
  if (stamp.shape == STAMP_LINE) {
    let dot = wide_add(wide_mul_i32(vx, stamp.along_x), wide_mul_i32(vy, stamp.along_y));
    if (wide_less(dot, Wide(1u, 0u))) {
      return 0u;
    }
    if (!wide_below(dot, reach)) {
      return STAMP_LAST_STOP;
    }
    return wide128_divr(wide_mul128(dot, Wide(STAMP_LAST_STOP, 0u)), reach, 10u).x;
  }
  let far = wide_add(wide_mul_i32(vx, vx), wide_mul_i32(vy, vy));
  if (!wide_below(far, reach)) {
    return STAMP_LAST_STOP;
  }
  // The nearest k to 1023·√(far / reach) is the one with (2k − 1)² ≤
  // 4·1023²·far / reach < (2k + 1)² — and, the squares being whole, with
  // the floor of the middle: k = ⌊(s + 1) / 2⌋, s its root's floor. The
  // floor is under 4·1023², 22 bits, as far < reach.
  let scale = 4u * STAMP_LAST_STOP * STAMP_LAST_STOP;
  let scaled = wide128_div(wide_mul128(far, Wide(scale, 0u)), reach, 22u);
  return (wide_isqrt(scaled) + 1u) / 2u;
}

// A pixel the mask covers keeps its stop's colour under any alpha, 0 too,
// as the app's stamp does.
@compute @workgroup_size(16, 16, 1)
fn flood_stamp_graded(@builtin(global_invocation_id) id: vec3<u32>) {
  let at = stamp_at(id);
  let stop = stops[stamp_stop(at.x, at.y)];
  let alpha = div255_round((stop >> 24u) * u32(at.z));
  stamp_put(id, select(0u, (stop & 0xffffffu) | (alpha << 24u), at.z != 0));
}
