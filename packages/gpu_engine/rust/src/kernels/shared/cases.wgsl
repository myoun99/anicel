// The shared functions run on what a test hands in — the GPU half of
// `tests.rs`, appended to wide.wgsl and resample.wgsl there.
//
// `run_wide`: a case is six words — what to run, a and b as two words
// each, low first, and a count k — and comes back as four, lowest first.
// `run_window`: one job — the map's words, the source's size, the window's
// size and where it sits in the whole output — over the pixels handed in.

@group(0) @binding(0) var<storage, read> job: array<u32>;
@group(0) @binding(1) var<storage, read> pixels: array<u32>;
@group(0) @binding(2) var<storage, read_write> results: array<u32>;

const RUN_ADD: u32 = 0u;
const RUN_SUB: u32 = 1u;
const RUN_MUL_I32: u32 = 2u;
const RUN_MUL_U32: u32 = 3u;
const RUN_MUL: u32 = 4u;
const RUN_MUL128: u32 = 5u;
const RUN_SHR: u32 = 6u;
const RUN_SHL: u32 = 7u;
const RUN_ROUND: u32 = 8u;
const RUN_ROUND128: u32 = 9u;
const RUN_POW2_OVER: u32 = 10u;
const RUN_DIVR: u32 = 11u;
const RUN_LESS: u32 = 12u;
const RUN_FITS: u32 = 13u;
const RUN_SAMPLES: u32 = 14u;
const RUN_SUBSAMPLE: u32 = 15u;

const MAP_WORDS: u32 = 14u;

fn low(a: Wide) -> Wide128 {
  return Wide128(a, 0u, 0u);
}

fn flag(on: bool) -> u32 {
  return select(0u, 1u, on);
}

@compute @workgroup_size(64)
fn run_wide(@builtin(global_invocation_id) id: vec3<u32>) {
  let i = id.x;
  if (i * 4u >= arrayLength(&results)) {
    return;
  }
  let at = i * 6u;
  let run = job[at];
  let a = Wide(job[at + 1u], job[at + 2u]);
  let b = Wide(job[at + 3u], job[at + 4u]);
  let k = job[at + 5u];
  var out = Wide128(0u);
  switch (run) {
    case RUN_ADD: {
      out = low(wide_add(a, b));
    }
    case RUN_SUB: {
      out = low(wide_sub(a, b));
    }
    case RUN_MUL_I32: {
      out = low(wide_mul_i32(bitcast<i32>(a.x), bitcast<i32>(b.x)));
    }
    case RUN_MUL_U32: {
      out = low(wide_mul_u32(a.x, b.x));
    }
    case RUN_MUL: {
      out = low(wide_mul(a, b));
    }
    case RUN_MUL128: {
      out = wide_mul128(a, b);
    }
    case RUN_SHR: {
      out = low(wide_shr(a, k));
    }
    case RUN_SHL: {
      out = low(wide_shl(a, k));
    }
    case RUN_ROUND: {
      out = low(wide_round(a, k));
    }
    case RUN_ROUND128: {
      let p = wide128_round(wide_mul128(a, b), k);
      out = Wide128(p.xy, flag(wide128_fits(p)), 0u);
    }
    case RUN_POW2_OVER: {
      out = low(wide_pow2_over(k, a));
    }
    case RUN_DIVR: {
      out = Wide128(wide_divr(a, b, k), 0u, 0u, 0u);
    }
    case RUN_LESS: {
      out = Wide128(flag(wide_less(a, b)), flag(wide_below(a, b)), 0u, 0u);
    }
    case RUN_FITS: {
      out = Wide128(flag(wide_fits(a)), flag(resample_within(a)), 0u, 0u);
    }
    case RUN_SAMPLES: {
      out = Wide128(resample_samples(a.x, b.x), 0u, 0u, 0u);
    }
    case RUN_SUBSAMPLE: {
      out = Wide128(bitcast<u32>(resample_subsample(a.x, k)), 0u, 0u, 0u);
    }
    default: {
    }
  }
  results[i * 4u] = out.x;
  results[i * 4u + 1u] = out.y;
  results[i * 4u + 2u] = out.z;
  results[i * 4u + 3u] = out.w;
}

fn resample_texel(source: u32, x: i32, y: i32) -> u32 {
  let width = i32(job[MAP_WORDS]);
  let height = i32(job[MAP_WORDS + 1u]);
  if (x < 0 || y < 0 || x >= width || y >= height) {
    return 0u;
  }
  return pixels[u32(y * width + x)];
}

@compute @workgroup_size(8, 8, 1)
fn run_window(@builtin(global_invocation_id) id: vec3<u32>) {
  let columns = job[MAP_WORDS + 2u];
  let rows = job[MAP_WORDS + 3u];
  if (id.x >= columns || id.y >= rows) {
    return;
  }
  let map = resample_map(array<u32, 14>(
    job[0], job[1], job[2], job[3], job[4], job[5], job[6],
    job[7], job[8], job[9], job[10], job[11], job[12], job[13],
  ));
  let x = bitcast<i32>(job[MAP_WORDS + 4u]) + i32(id.x);
  let y = bitcast<i32>(job[MAP_WORDS + 5u]) + i32(id.y);
  results[id.y * columns + id.x] = resample(map, 0u, x, y);
}
