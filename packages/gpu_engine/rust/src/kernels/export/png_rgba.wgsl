// A PNG of four channels takes the frame as it is: straight RGBA, red the
// low byte of a pixel's word — a row's bytes in the PNG's own order.
// Needs tile.wgsl and frame.wgsl before it.

const PIXEL_BYTES: u32 = 4u;

fn row_byte(y: u32, i: u32) -> u32 {
  return (source[frame_word(params.columns, i / 4u, y)] >> (i % 4u * 8u)) & 0xffu;
}
