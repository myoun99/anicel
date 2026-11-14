// A frame as a movie encoder takes it: NV12 — 4:2:0 BT.601 studio range,
// the app's colour law for movies (video's `colour::from_rgba`,
// packages/gpu_engine/rust/native/video/src/colour.rs) — converted before
// the readback, so 1.5 bytes a pixel cross to the CPU instead of 4
// (gpu-export-path ①a).
//
// The law's numbers, all of them:
//   Y  = ((66R + 129G + 25B + 128) >> 8) + 16
//   Cb = ((-38R - 74G + 112B + 128) >> 8) + 128
//   Cr = ((112R - 94G - 18B + 128) >> 8) + 128
// a 2x2 block's chroma from its top-left pixel, and white past the picture
// — the encoder's even size. WGSL's `>>` on an i32 is arithmetic (§8.10),
// as the law's Rust `>>` on an i32 is, so a negative sum floors alike.
// Integers only: a float step may be fused or reassociated on one device
// and not another (fill.wgsl).
//
// The picture's alpha is not read, as the law reads none.
//
// Needs tile.wgsl and its picture's reads (frame.wgsl or
// frame_shown.wgsl) before it.

struct Params {
  // The frame's step from one row to the next (frame.wgsl,
  // frame_shown.wgsl).
  stride: u32,
  // The picture.
  src_width: u32,
  src_height: u32,
  // The encoder's frame: even sides, at least the picture's.
  width: u32,
  height: u32,
  // Bytes from one Y row to the next — and one CbCr row to the next: a
  // multiple of 4, at least the width.
  y_stride: u32,
  pad0: u32,
  pad1: u32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(2) var<storage, read_write> nv12: array<u32>;

// Pixel (x, y)'s red, green and blue; white past the picture — the
// encoder's padding to even sides, and a row's stride past that too
// (⚠️mine: the law leaves the stride's bytes to the caller, and no encoder
// reads them).
fn rgb_at(x: u32, y: u32) -> vec3<i32> {
  if (x >= params.src_width || y >= params.src_height) {
    return vec3<i32>(255);
  }
  let word = frame_straight(x, y);
  return vec3<i32>(
    i32(word & 0xffu),
    i32((word >> 8u) & 0xffu),
    i32((word >> 16u) & 0xffu),
  );
}

fn luma(c: vec3<i32>) -> u32 {
  return u32(((66 * c.r + 129 * c.g + 25 * c.b + 128) >> 8u) + 16);
}

fn blue_difference(c: vec3<i32>) -> u32 {
  return u32(((-38 * c.r - 74 * c.g + 112 * c.b + 128) >> 8u) + 128);
}

fn red_difference(c: vec3<i32>) -> u32 {
  return u32(((112 * c.r - 94 * c.g - 18 * c.b + 128) >> 8u) + 128);
}

// One invocation, 4 x 2 pixels: two words of Y — the block's two rows —
// and the one word of CbCr their two 2 x 2 blocks share.
@compute @workgroup_size(16, 8)
fn nv12_pass(@builtin(global_invocation_id) id: vec3<u32>) {
  let x = id.x * 4u;
  let y = id.y * 2u;
  if (x >= params.y_stride || y >= params.height) {
    return;
  }
  let row = params.y_stride / 4u;
  var top = 0u;
  var bottom = 0u;
  for (var k = 0u; k < 4u; k += 1u) {
    top |= luma(rgb_at(x + k, y)) << (8u * k);
    bottom |= luma(rgb_at(x + k, y + 1u)) << (8u * k);
  }
  nv12[y * row + id.x] = top;
  nv12[(y + 1u) * row + id.x] = bottom;
  let left = rgb_at(x, y);
  let right = rgb_at(x + 2u, y);
  nv12[(params.height + id.y) * row + id.x] = blue_difference(left)
    | (red_difference(left) << 8u)
    | (blue_difference(right) << 16u)
    | (red_difference(right) << 24u);
}
