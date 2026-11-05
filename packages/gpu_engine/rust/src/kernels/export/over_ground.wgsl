// A frame as the writers that keep no alpha take it — JPG, a PNG of three
// channels, BMP · TGA · TIFF · WebP without alpha — each pixel laid over
// the format's background, three bytes a pixel, row after row with nothing
// between: 3 bytes a pixel cross to the CPU instead of 4
// (gpu-export-path ①b).
//
// The law is the app's (`_overGround`, lib/src/ui/export/
// still_image_encoders.dart): a premultiplied channel p over the ground's
// g is p + g·(255 − a) / 255, the division flooring. The app reads p from
// Flutter's premultiplied bytes; the frame here is straight, so p is the
// engine's own premultiply first (qa_engine.c `qa_premultiply_pixel`,
// SkMulDiv255Round): t = c·a + 128, p = (t + (t >> 8)) >> 8, round(c·a /
// 255). An opaque pixel is its own colour — p = c and nothing of the
// ground —, as the app's branch for it says. Integers only: a float step
// may be fused or reassociated on one device and not another (fill.wgsl).
// p <= a and g·(255 − a) / 255 <= 255 − a, so the sum is a byte.
//
// Needs tile.wgsl and frame.wgsl before it.

struct Params {
  // The frame's tiles a row.
  columns: u32,
  // The picture.
  width: u32,
  height: u32,
  // Groups of four pixels a row of invocations asks for: the width's, so
  // neither side of the dispatch outgrows the picture's.
  row_groups: u32,
  // The background: red in the low byte, as the frame's words.
  ground: u32,
  pad0: u32,
  pad1: u32,
  pad2: u32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read> frame: array<u32>;
@group(0) @binding(2) var<storage, read_write> rgb: array<u32>;

fn byte_of(word: u32, shift: u32) -> u32 {
  return (word >> shift) & 0xffu;
}

// round(c·a / 255) for bytes.
fn premultiplied(c: u32, a: u32) -> u32 {
  let t = c * a + 128u;
  return (t + (t >> 8u)) >> 8u;
}

fn laid(word: u32, shift: u32) -> u32 {
  let alpha = word >> 24u;
  return premultiplied(byte_of(word, shift), alpha)
    + byte_of(params.ground, shift) * (255u - alpha) / 255u;
}

// The picture's pixel `index`, counted row after row, over the ground; 0
// past its last — the bytes that fill out the last word, which no writer
// reads.
fn pixel(index: u32) -> vec3<u32> {
  if (index >= params.width * params.height) {
    return vec3<u32>(0u);
  }
  let word = frame[frame_word(params.columns, index % params.width, index / params.width)];
  return vec3<u32>(laid(word, 0u), laid(word, 8u), laid(word, 16u));
}

// One invocation, four pixels in a run — the three words their twelve
// bytes fill. A run may cross from one row into the next, as the bytes do.
@compute @workgroup_size(64)
fn over_ground_pass(@builtin(global_invocation_id) id: vec3<u32>) {
  // Past a row's runs: the next row's own invocations write those words,
  // so going on would only write them twice.
  if (id.x >= params.row_groups) {
    return;
  }
  let run = id.y * params.row_groups + id.x;
  let first = run * 4u;
  // A run past the picture's last has its words past the buffer, and a
  // store out of bounds may land anywhere in it (WGSL, invalid memory
  // references): this device drops it, another may write the last word.
  if (first >= params.width * params.height) {
    return;
  }
  let a = pixel(first);
  let b = pixel(first + 1u);
  let c = pixel(first + 2u);
  let d = pixel(first + 3u);
  let at = run * 3u;
  rgb[at] = a.r | (a.g << 8u) | (a.b << 16u) | (b.r << 24u);
  rgb[at + 1u] = b.g | (b.b << 8u) | (c.r << 16u) | (c.g << 24u);
  rgb[at + 2u] = c.b | (d.r << 8u) | (d.g << 16u) | (d.b << 24u);
}
