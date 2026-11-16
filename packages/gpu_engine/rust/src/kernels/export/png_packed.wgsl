// A PNG whose bytes lie packed — `PIXEL_BYTES` a pixel, row after row with
// nothing between: three, the over-the-ground pass's (over_ground.wgsl);
// four, a picture's straight RGBA as the app hands it (an animated PNG's
// frame, `gpu_engine_export_png_straight`). One read for both, the count
// set where the pass is compiled.

override PIXEL_BYTES: u32 = 3u;

@group(0) @binding(1) var<storage, read> source: array<u32>;

fn row_byte(y: u32, i: u32) -> u32 {
  let at = y * params.width * PIXEL_BYTES + i;
  return (source[at / 4u] >> (at % 4u * 8u)) & 0xffu;
}
