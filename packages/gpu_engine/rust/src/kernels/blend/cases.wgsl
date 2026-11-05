// The blend family's functions run on cases a test hands in — the GPU half
// of `tests.rs`, appended to blend.wgsl there. A case is nine words: what to
// run, then src and dst as straight RGBA on the 16-bit scale. A mode id runs
// blend_composite; the ids from 100 run one function each, reading what
// they need from src.x, src.w and dst.x.

@group(0) @binding(0) var<storage, read> cases: array<u32>;
@group(0) @binding(1) var<storage, read_write> results: array<vec4<u32>>;

const RUN_ERASE: u32 = 100u;
const RUN_MUL: u32 = 101u;
const RUN_DIV: u32 = 102u;
const RUN_TO8: u32 = 103u;
const RUN_SQRT: u32 = 104u;

@compute @workgroup_size(64)
fn run_cases(@builtin(global_invocation_id) id: vec3<u32>) {
  let i = id.x;
  if (i >= arrayLength(&results)) {
    return;
  }
  let at = i * 9u;
  let run = cases[at];
  let src = vec4<u32>(cases[at + 1u], cases[at + 2u], cases[at + 3u], cases[at + 4u]);
  let dst = vec4<u32>(cases[at + 5u], cases[at + 6u], cases[at + 7u], cases[at + 8u]);
  var out = vec4<u32>(0u);
  switch (run) {
    case RUN_ERASE: {
      out = blend_erase(src.w, dst);
    }
    case RUN_MUL: {
      out.x = blend_mul(src.x, dst.x);
    }
    case RUN_DIV: {
      out.x = blend_div(src.x, dst.x);
    }
    case RUN_TO8: {
      out.x = blend_to8(src.x);
    }
    case RUN_SQRT: {
      out.x = blend_sqrt(src.x);
    }
    default: {
      out = blend_composite(run, src, dst);
    }
  }
  results[i] = out;
}
