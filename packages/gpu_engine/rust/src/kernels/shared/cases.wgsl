// The shared functions run on what a test hands in — the GPU half of
// `tests.rs`, appended there to wide.wgsl, resample.wgsl and
// premultiply.wgsl.
//
// `run_wide`: a case is six words — what to run, a and b as two words
// each, low first, and a count k — and comes back as four, lowest first.
// `run_premultiply`: each of the pixels handed in, premultiplied.
// `run_divide`: a case is eight words — n as four and d as two, low first,
// the quotient's bits, and 1 where it rounds — and comes back as the
// quotient's two.

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
const RUN_WALK: u32 = 16u;
const RUN_DIV_FLOOR: u32 = 17u;
const RUN_ISQRT: u32 = 18u;

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
    case RUN_DIV_FLOOR: {
      out = Wide128(wide_div_floor(a, b, k), 0u, 0u, 0u);
    }
    case RUN_ISQRT: {
      out = Wide128(wide_isqrt(a), 0u, 0u, 0u);
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
    // Subsample a.x of k, walked to from the first (resample_next_offset).
    case RUN_WALK: {
      var offsets = resample_offsets(k);
      var offset = 0i;
      for (var s = 0u; s <= a.x; s = s + 1u) {
        offset = resample_next_offset(&offsets);
      }
      out = Wide128(bitcast<u32>(offset), 0u, 0u, 0u);
    }
    default: {
    }
  }
  results[i * 4u] = out.x;
  results[i * 4u + 1u] = out.y;
  results[i * 4u + 2u] = out.z;
  results[i * 4u + 3u] = out.w;
}

// No case here reads a source: R1 over a picture runs on the warp's pass
// (kernels/warp), the one that reads a box — this only lets resample.wgsl
// compile beside the cases.
fn resample_texel(source: u32, x: i32, y: i32) -> u32 {
  return 0u;
}

@compute @workgroup_size(64)
fn run_divide(@builtin(global_invocation_id) id: vec3<u32>) {
  let i = id.x;
  if (i * 2u >= arrayLength(&results)) {
    return;
  }
  let at = i * 8u;
  let n = Wide128(job[at], job[at + 1u], job[at + 2u], job[at + 3u]);
  let d = Wide(job[at + 4u], job[at + 5u]);
  var quotient = wide128_div(n, d, job[at + 6u]);
  if (job[at + 7u] == 1u) {
    quotient = wide128_divr(n, d, job[at + 6u]);
  }
  results[i * 2u] = quotient.x;
  results[i * 2u + 1u] = quotient.y;
}

@compute @workgroup_size(64)
fn run_premultiply(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x < arrayLength(&pixels)) {
    results[id.x] = premultiply8(pixels[id.x]);
  }
}
