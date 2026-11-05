// A camera lens blur's row sums — the app's row_sum.frag, by the integer
// spec gpu-int-spec-canvas 1b (4/4): every pixel of the picture the sum of
// its row up to it, each pixel read through the light (light.wgsl), so the
// iris takes any span of a row in two reads. Exact: an integer sum is the
// same however it is gathered, so this gathers by runs where the app
// strides by taps.
//
// Two dispatches. The first sums each run of SUMS_RUN pixels from its own
// start and keeps the run's total; the second adds to every run the totals
// of the runs before it. A run's sum is a word — 64 pixels under 2^23
// each —, a row's two: four channels of two words a pixel, low first.
//
// The picture is held.wgsl's target plane — eight words a pixel.
//
// Needs shared/wide.wgsl, held.wgsl and light.wgsl before it.

const SUMS_RUN: u32 = 64u;

// The light, then the picture's rows and its runs a row.
struct SumsPass {
  light: Light,
  rows: u32,
  runs: u32,
}

@group(0) @binding(3) var<uniform> sums_: SumsPass;
// Each run's total, a row's runs after another's — four words each.
@group(0) @binding(4) var<storage, read_write> totals: array<u32>;

// A run's first pixel and the pixel past its last, along its row.
fn sums_run(run: u32) -> vec2<i32> {
  let first = held.target_x0 + i32(run * SUMS_RUN);
  return vec2<i32>(first, min(first + i32(SUMS_RUN), held.target_x0 + i32(held.target_width)));
}

fn sums_word(x: i32, y: i32) -> u32 {
  return held_plane_word(x, y, held.target_x0, held.target_y0, held.target_width, 8u);
}

@compute @workgroup_size(8, 8, 1)
fn sums_runs(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= sums_.runs || id.y >= sums_.rows) {
    return;
  }
  let y = held.target_y0 + i32(id.y);
  let run = sums_run(id.x);
  var sum = vec4<u32>(0u);
  for (var x = run.x; x < run.y; x++) {
    sum += light_read(pixels_in[held_tile_word(x, y)], sums_.light);
    let at = sums_word(x, y);
    for (var c = 0u; c < 4u; c++) {
      pixels_out[at + c * 2u] = sum[c];
      pixels_out[at + c * 2u + 1u] = 0u;
    }
  }
  let total = (id.y * sums_.runs + id.x) * 4u;
  for (var c = 0u; c < 4u; c++) {
    totals[total + c] = sum[c];
  }
}

@compute @workgroup_size(8, 8, 1)
fn sums_carry(@builtin(global_invocation_id) id: vec3<u32>) {
  // The first run has nothing before it.
  if (id.x >= sums_.runs || id.y >= sums_.rows || id.x == 0u) {
    return;
  }
  var carry = array<Wide, 4>(Wide(0u, 0u), Wide(0u, 0u), Wide(0u, 0u), Wide(0u, 0u));
  for (var before = 0u; before < id.x; before++) {
    let total = (id.y * sums_.runs + before) * 4u;
    for (var c = 0u; c < 4u; c++) {
      carry[c] = wide_add(carry[c], Wide(totals[total + c], 0u));
    }
  }
  let y = held.target_y0 + i32(id.y);
  let run = sums_run(id.x);
  for (var x = run.x; x < run.y; x++) {
    let at = sums_word(x, y);
    for (var c = 0u; c < 4u; c++) {
      let sum = wide_add(carry[c], Wide(pixels_out[at + c * 2u], 0u));
      pixels_out[at + c * 2u] = sum.x;
      pixels_out[at + c * 2u + 1u] = sum.y;
    }
  }
}
