// A frame as the writers that keep its alpha take it — ffmpeg's `rgba`, a
// PDF's picture beside its soft mask, a still of four channels — each
// pixel straight, red first, four bytes a pixel, row after row with
// nothing between (gpu-export-path ①⑶). The law is the frame's own
// straight read (`frame_straight`, frame.wgsl and frame_shown.wgsl) — the
// one a PNG's rows of four channels take theirs by (png_rgba.wgsl).
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
@group(0) @binding(2) var<storage, read_write> rgba: array<u32>;

// One invocation, one pixel.
@compute @workgroup_size(64)
fn straight_pass(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= params.width || id.y >= params.height) {
    return;
  }
  rgba[id.y * params.width + id.x] = frame_straight(id.x, id.y);
}
