// Each pixel answers how many pixels of its group of 8 × 8 fall in its
// alpha's quarter: the counts are atomics, added to by every invocation,
// and read only after a barrier.
var<workgroup> quarters: array<atomic<u32>, 4>;

@compute @workgroup_size(8, 8)
fn anicel_render(@builtin(global_invocation_id) at: vec3<u32>) {
  let here = anicel_here();
  let quarter = anicel_in(here.x, here.y) >> 30u;
  atomicAdd(&quarters[quarter], 1u);
  workgroupBarrier();
  anicel_out(atomicLoad(&quarters[quarter]));
}

fn anicel_reach() -> u32 {
  return 0u;
}
