// A PNG of three channels takes the over-the-ground pass's bytes
// (over_ground.wgsl): three a pixel, row after row with nothing between.

const PIXEL_BYTES: u32 = 3u;

@group(0) @binding(1) var<storage, read> source: array<u32>;

fn row_byte(y: u32, i: u32) -> u32 {
  let at = y * params.width * 3u + i;
  return (source[at / 4u] >> (at % 4u * 8u)) & 0xffu;
}
