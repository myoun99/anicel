// Inverts each pixel's colour and keeps its alpha.
@compute @workgroup_size(16, 16)
fn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {
  let here = anicel_here();
  let pixel = unpack4xU8(anicel_in(here.x, here.y));
  anicel_out(pack4xU8(vec4<u32>(255u - pixel.x, 255u - pixel.y, 255u - pixel.z, pixel.w)));
}

fn anicel_reach() -> u32 {
  return 0u;
}
