// Halves the red channel through a float, which the integer law refuses.
@compute @workgroup_size(16, 16)
fn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {
  let here = anicel_here();
  let red = f32(anicel_in(here.x, here.y) & 0xffu) * 0.5;
  anicel_out(u32(red));
}

fn anicel_reach() -> u32 {
  return 0u;
}
