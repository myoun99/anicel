// Whether every pixel of a picture is opaque (gpu-export-path ①d): the pdf
// package splits a picture handed to it with alpha into its RGB and a soft
// mask, so an opaque one can go as three bytes a pixel and no mask — and
// only those three cross to the CPU.
//
// The AND of every alpha, which is 255 when each is 255 and less when one
// is not. One workgroup a tile: its invocations AND a share each into the
// group's word, the group's word into the answer — AND gives the same
// whatever order a device takes them in.
//
// Needs tile.wgsl and its picture's reads (frame.wgsl or
// frame_shown.wgsl) before it.

struct Params {
  // The frame's step from one row to the next (frame.wgsl,
  // frame_shown.wgsl).
  stride: u32,
  // The picture.
  width: u32,
  height: u32,
  pad0: u32,
}

@group(0) @binding(0) var<uniform> params: Params;
// 255 before the pass.
@group(0) @binding(2) var<storage, read_write> opaque: atomic<u32>;

var<workgroup> held: atomic<u32>;

@compute @workgroup_size(64)
fn opaque_pass(
  @builtin(workgroup_id) tile: vec3<u32>,
  @builtin(local_invocation_index) local: u32,
) {
  if (local == 0u) {
    atomicStore(&held, 255u);
  }
  workgroupBarrier();
  var alpha = 255u;
  for (var texel = local; texel < TILE_TEXELS; texel += 64u) {
    let x = tile.x * TILE_SIDE + texel % TILE_SIDE;
    let y = tile.y * TILE_SIDE + texel / TILE_SIDE;
    // Past the picture a tile holds what no page shows.
    if (x < params.width && y < params.height) {
      alpha &= frame_alpha(x, y);
    }
  }
  atomicAnd(&held, alpha);
  workgroupBarrier();
  if (local == 0u) {
    atomicAnd(&opaque, atomicLoad(&held));
  }
}
