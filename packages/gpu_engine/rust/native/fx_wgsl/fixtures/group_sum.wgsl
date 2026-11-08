// Every pixel of a group of 8 × 8 answers the sum of the group's red
// channels: a tree's sum in two steps a round — read the own cell and the
// one half a tree away, a barrier, then write the own cell, a barrier.
var<workgroup> sums: array<u32, 64>;

@compute @workgroup_size(8, 8)
fn anicel_render(@builtin(global_invocation_id) at: vec3<u32>, @builtin(local_invocation_index) i: u32) {
  let here = anicel_here();
  sums[i] = anicel_in(here.x, here.y) & 0xffu;
  workgroupBarrier();
  for (var half = 32u; half > 0u; half = half >> 1u) {
    let mine = sums[i] + sums[min(i + half, 63u)];
    workgroupBarrier();
    if (i < half) {
      sums[i] = mine;
    }
    workgroupBarrier();
  }
  anicel_out(sums[0]);
}

fn anicel_reach() -> u32 {
  return 0u;
}
