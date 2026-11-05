// R3, a mesh warp's first pass (gpu-int-spec-canvas 1b R3): which triangle
// paints each pixel of the output. The app's transformStampDabMesh gives a
// pixel to the FIRST triangle in the grid's order — row, column, then
// (TL, TR, BL) before (TR, BR, BL) — whose destination holds its centre
// (its `covered` table). Here a dispatch a triangle, a thread a pixel of
// its box, and atomicMin keeps the least order: the first, whichever order
// the threads ran in. A pixel no triangle holds keeps MESH_NONE.
//
// Points Q.8 within ±2^15 pixels; a pixel's centre ((2x+1)·128, (2y+1)·128).
// A centre is in when n1, n2 and n0 = den − n1 − n2 each have den's sign or
// are 0 — the app's −1e-9 slack made exact, so a centre on an edge two
// triangles share is in both and the order gives it.
//
// Needs shared/wide.wgsl before it.

// The output's top-left pixel and width; the triangle's order and its box
// within the output, top-left and size; d0 and the edges to d1 and d2, Q.8;
// den = e1 × e2, Q.16, low word first.
struct Triangle {
  left: i32,
  top: i32,
  width: u32,
  order: u32,
  box_left: i32,
  box_top: i32,
  box_width: u32,
  box_height: u32,
  d0x: i32,
  d0y: i32,
  e1x: i32,
  e1y: i32,
  e2x: i32,
  e2y: i32,
  den_low: u32,
  den_high: u32,
}

@group(0) @binding(0) var<uniform> triangle: Triangle;
@group(0) @binding(1) var<storage, read_write> owners: array<atomic<u32>>;

const MESH_NONE: u32 = 0xffffffffu;

// Whether `n` has the sign of den or is 0 — n against den's side.
fn mesh_on_side(n: Wide, den: Wide) -> bool {
  return !wide_negative(select(n, wide_neg(n), wide_negative(den)));
}

// Whether the pixel at canvas (x, y) has its centre in the triangle.
fn mesh_holds(x: i32, y: i32) -> bool {
  let qx = (2 * x + 1) * 128 - triangle.d0x;
  let qy = (2 * y + 1) * 128 - triangle.d0y;
  let n1 = wide_sub(wide_mul_i32(qx, triangle.e2y), wide_mul_i32(triangle.e2x, qy));
  let n2 = wide_sub(wide_mul_i32(triangle.e1x, qy), wide_mul_i32(qx, triangle.e1y));
  let den = Wide(triangle.den_low, triangle.den_high);
  let n0 = wide_sub(wide_sub(den, n1), n2);
  return mesh_on_side(n0, den) && mesh_on_side(n1, den) && mesh_on_side(n2, den);
}

// A thread a pixel of the output (the box is the whole of it): no triangle
// yet.
@compute @workgroup_size(8, 8, 1)
fn mesh_clear(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x < triangle.box_width && id.y < triangle.box_height) {
    atomicStore(&owners[id.y * triangle.width + id.x], MESH_NONE);
  }
}

// A thread a pixel of the triangle's box: the triangle's order, where it
// holds the centre and no earlier one does. The guard is not the device's
// to keep: past the box's right a pixel the output cut off would land on
// the next row, and past its bottom past the plane, which DX12 drops but
// Metal would clamp onto the last word.
@compute @workgroup_size(8, 8, 1)
fn mesh_own(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= triangle.box_width || id.y >= triangle.box_height) {
    return;
  }
  let x = triangle.box_left + i32(id.x);
  let y = triangle.box_top + i32(id.y);
  if (mesh_holds(x, y)) {
    let at = u32(y - triangle.top) * triangle.width + u32(x - triangle.left);
    atomicMin(&owners[at], triangle.order);
  }
}
