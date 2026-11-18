// A three-wide blur along each group's row of sixteen pixels, every pixel
// read from the input once and shared: written to the invocation's own
// cell, then a barrier, then the neighbours' cells read. At a group's ends
// the pixel stands in for the neighbour it lacks.
var<workgroup> row: array<u32, 16>;

@compute @workgroup_size(16, 1)
fn anicel_render(@builtin(global_invocation_id) at: vec3<u32>, @builtin(local_invocation_index) i: u32) {
  let here = anicel_here();
  row[i] = anicel_in(here.x, here.y);
  workgroupBarrier();
  let left = unpack4xU8(row[max(i, 1u) - 1u]);
  let right = unpack4xU8(row[min(i + 1u, 15u)]);
  let sum = left + unpack4xU8(row[i]) + right;
  anicel_out(pack4xU8((sum + vec4<u32>(1u)) / 3u));
}

fn anicel_reach() -> u32 {
  return 0u;
}
