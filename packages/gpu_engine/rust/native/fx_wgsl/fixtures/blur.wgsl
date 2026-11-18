// A box blur whose radius is value 0, a number in Q.16 pixels, each
// channel on its own and rounded half up.
fn radius() -> i32 {
  return clamp(anicel_value(0, 0) >> 16u, 0, 64);
}

@compute @workgroup_size(16, 16)
fn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {
  let here = anicel_here();
  let r = radius();
  var sum = vec4<u32>(0u);
  for (var dy = -r; dy <= r; dy++) {
    for (var dx = -r; dx <= r; dx++) {
      sum += unpack4xU8(anicel_in(here.x + dx, here.y + dy));
    }
  }
  let n = u32((2 * r + 1) * (2 * r + 1));
  anicel_out(pack4xU8((sum + vec4<u32>(n / 2u)) / n));
}

fn anicel_reach() -> u32 {
  return u32(radius());
}
