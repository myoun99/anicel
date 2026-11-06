// The colour matrix run on cases a test hands in — the GPU half of
// `matrix_tests.rs`, appended to matrix.wgsl there. A case is two words:
// where its matrix starts in `matrices`, and the straight RGBA8 word.

@group(0) @binding(0) var<storage, read> matrices: array<u32>;
@group(0) @binding(1) var<storage, read> cases: array<u32>;
@group(0) @binding(2) var<storage, read_write> results: array<u32>;

fn matrix_word(at: u32) -> u32 {
  return matrices[at];
}

@compute @workgroup_size(64)
fn run_matrices(@builtin(global_invocation_id) id: vec3<u32>) {
  let i = id.x;
  if (i >= arrayLength(&results)) {
    return;
  }
  results[i] = matrix_rgba8(cases[i * 2u], cases[i * 2u + 1u]);
}
