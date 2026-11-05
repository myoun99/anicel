// How the timeline's kernels lay a colour: straight `rgba` at the 16-bit
// alpha `alpha` — its own alpha already times whatever covers the pixel —
// over `under`, by the blend family's normal composite (관제 16:2x).
//
// Needs blend/blend.wgsl before it.
fn laid(under: vec4<u32>, rgba: u32, alpha: u32) -> vec4<u32> {
  let colour = blend_unpack8(rgba);
  return blend_composite(BLEND_NORMAL, vec4<u32>(colour.xyz, alpha), under);
}
