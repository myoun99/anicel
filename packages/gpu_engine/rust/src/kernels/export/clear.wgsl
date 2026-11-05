// Which pixels of a GIF are its clear colour (gpu-export-path ①c): one bit
// a pixel, set where its alpha is under the cut — under half covered, as
// the app lays it (`_gifPictureOf`, video_export_service.dart). Its colours
// come from the over-the-ground pass with the same cut (over_ground.wgsl);
// together they cross to the CPU as 3 bytes and a bit a pixel, not 4.
//
// Pixel i is bit i % 32 of word i / 32, counted row after row with nothing
// between, as the colours are.
//
// Needs tile.wgsl and frame.wgsl before it.

struct Params {
  // The frame's tiles a row.
  columns: u32,
  // The picture.
  width: u32,
  height: u32,
  // Words of 32 pixels a row of invocations asks for: the width's, so
  // neither side of the dispatch outgrows the picture's.
  row_words: u32,
  // A pixel whose alpha is under it is clear.
  cut: u32,
  pad0: u32,
  pad1: u32,
  pad2: u32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read> frame: array<u32>;
@group(0) @binding(2) var<storage, read_write> clear_bits: array<u32>;

// One invocation, one word: 32 pixels in a run, which may cross from one
// row into the next. Past the picture's last pixel the bits are 0.
@compute @workgroup_size(64)
fn clear_pass(@builtin(global_invocation_id) id: vec3<u32>) {
  // Past a row's words: the next row's own invocations write them.
  if (id.x >= params.row_words) {
    return;
  }
  let word = id.y * params.row_words + id.x;
  let first = word * 32u;
  let pixels = params.width * params.height;
  // Past the buffer, as over_ground.wgsl has why.
  if (first >= pixels) {
    return;
  }
  var bits = 0u;
  for (var bit = 0u; bit < 32u; bit += 1u) {
    let index = first + bit;
    if (index < pixels) {
      let alpha = frame[frame_word(params.columns, index % params.width, index / params.width)] >> 24u;
      if (alpha < params.cut) {
        bits |= 1u << bit;
      }
    }
  }
  clear_bits[word] = bits;
}
