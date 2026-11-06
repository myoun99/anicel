// A fill's colour stamp (`_colorStampDab`, R15-⑥; gpu-canonical-store
// stage 5): its finished mask in its colour, as the tiles of the row a
// stroke lands by — straight RGBA8, a pixel the mask covers at all its
// colour under the mask's byte for an alpha, one it covers none nothing,
// as the app's stamp holds them. The stamp blends nothing itself: the
// executor lays its row on the cel at the fill's opacity, in its mode and
// under the selection, as it lays a stroke (R28), and R10's stamp
// composite is that laying (gpu-canonical-store 1a 3/3 보탬).
//
// Needs shared/tile.wgsl and kernels/mask's byte.wgsl before it; defines
// byte.wgsl's `mask_word`.

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
  // The colour, red in the low byte; what lies above blue is not read.
  colour: u32,
  unused_0: u32,
  unused_1: u32,
}

@group(0) @binding(0) var<uniform> stamp: Stamp;
@group(0) @binding(1) var<storage, read> mask: array<u32>;
@group(0) @binding(2) var<storage, read_write> page: array<u32>;

fn mask_word(at: u32) -> u32 {
  return mask[at];
}

// A workgroup puts a 16 × 16 of a tile's pixels, 64 of them a tile, a
// tile a workgroup deep.
@compute @workgroup_size(16, 16, 1)
fn flood_stamp(@builtin(global_invocation_id) id: vec3<u32>) {
  let tile = stamp.first + id.z;
  let x = (stamp.column + i32(tile % stamp.columns)) * i32(TILE_SIDE) + i32(id.x);
  let y = (stamp.row + i32(tile / stamp.columns)) * i32(TILE_SIDE) + i32(id.y);
  // A pixel past the box's left or top wraps past its width or height.
  let plane = MaskPlane(0u, stamp.width, stamp.height, stamp.stride);
  let byte = mask_byte_of(plane, u32(x - stamp.left), u32(y - stamp.top));
  page[id.z * TILE_TEXELS + tile_texel(id.x, id.y)] =
    select(0u, (stamp.colour & 0xffffffu) | (byte << 24u), byte != 0u);
}
