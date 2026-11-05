// The key walk run on cases a test hands in — the GPU half of `tests.rs`,
// appended to key.wgsl there. A case is three words: where its run starts
// in `runs`, the straight RGBA8 word, and its alpha before the run.

@group(0) @binding(0) var<storage, read> runs: array<u32>;
@group(0) @binding(1) var<storage, read> cases: array<u32>;
@group(0) @binding(2) var<storage, read_write> results: array<u32>;

fn key_word(at: u32) -> u32 {
  return runs[at];
}

@compute @workgroup_size(64)
fn run_cases(@builtin(global_invocation_id) id: vec3<u32>) {
  let i = id.x;
  if (i >= arrayLength(&results)) {
    return;
  }
  let at = i * 3u;
  results[i] = key_rgba8(cases[at], cases[at + 1u], cases[at + 2u]);
}
