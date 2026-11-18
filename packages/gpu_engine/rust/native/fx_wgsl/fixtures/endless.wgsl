// Never ends, in its render and in its reach: the host's count cuts both.
@compute @workgroup_size(16, 16)
fn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {
  var spin = 0u;
  loop {
    spin = spin + 1u;
  }
  anicel_out(spin);
}

fn anicel_reach() -> u32 {
  var spin = 0u;
  while true {
    spin += 1u;
  }
  return spin;
}
