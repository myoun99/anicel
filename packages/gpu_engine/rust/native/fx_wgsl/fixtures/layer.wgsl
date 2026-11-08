// Shows the layer value 0 names wherever the input is transparent.
@compute @workgroup_size(8, 8)
fn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {
  let here = anicel_here();
  let own = anicel_in(here.x, here.y);
  let behind = anicel_row(anicel_value(0, 0), here.x, here.y);
  anicel_out(select(own, behind, (own >> 24u) == 0u));
}

fn anicel_reach() -> u32 {
  return 0u;
}
