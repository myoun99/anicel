// fx Gaussian Blur, a way a pass (gaussian.rs, 🗣️유저 gpu-canonical-store-
// Q2): each pixel it puts the sum of its way's weights over the pixels
// `reach` either side of it and itself, on held.wgsl's premultiplied 16-bit
// scale, rounded half up once. The weights sum to 65536, so a sum of
// 65535s is 65535·65536 at most and, with the half, stays inside a u32 —
// and every sum on the way to it is less.
//
// Needs held.wgsl before it.

// How a read past the picture is taken: as nothing; as the nearest pixel
// inside.
const GAUSSIAN_EDGE_NOTHING: u32 = 1u;

// One pass: along the rows (down 0) or the columns (down 1), how far its
// weights reach, the pixels it puts — [first, end) along, lines
// [line_first, line_end) across —, how it reads past [edge_first, edge_end)
// along and [cross_first, cross_end) across, and where its weights begin
// (gaussian.rs's `Pass::words`).
struct GaussianPass {
  down: u32,
  reach: u32,
  first: i32,
  end: i32,
  line_first: i32,
  line_end: i32,
  edge: u32,
  edge_first: i32,
  edge_end: i32,
  cross_first: i32,
  cross_end: i32,
  weights: u32,
}

@group(0) @binding(3) var<uniform> gaussian_: GaussianPass;
// Each way's weights, its middle's first: the rows' then the columns'.
@group(0) @binding(4) var<storage, read> gaussian_weights: array<u32>;

// The pixel the pass reads at `p` along `line`: past the picture, nothing
// or the nearest pixel inside.
fn gaussian_tap(line: i32, p: i32) -> vec4<u32> {
  var at = p;
  var across = line;
  if (p < gaussian_.edge_first || p >= gaussian_.edge_end
      || line < gaussian_.cross_first || line >= gaussian_.cross_end) {
    if (gaussian_.edge == GAUSSIAN_EDGE_NOTHING) {
      return vec4<u32>(0u);
    }
    at = clamp(p, gaussian_.edge_first, gaussian_.edge_end - 1);
    across = clamp(line, gaussian_.cross_first, gaussian_.cross_end - 1);
  }
  if (gaussian_.down == 1u) {
    return held_read(across, at);
  }
  return held_read(at, across);
}

// 🚨★★WHAT A WORKGROUP READS IT READS ONCE, INTO A WINDOW IT SHARES
// (gaussian-shared-rows, 2026-11-08): a thread a pixel reading its own
// 2·reach + 1 taps from the tiles read each pixel that many times, and the
// pass grew with the reach — Blurriness 50 was 17.32 ms on the Surface's
// Arc 140V (2048 × 1152 both ways), past a frame for one picture alone.
// Now a workgroup's lines of pixels, and the reach past them either side,
// are read into the window once, a stretch of it at a time, and each
// thread sums its taps from there. The sum is of integers, so the order it
// is taken in changes no byte (the ledger's `effects/blur` holds that).
//
// ⛔THE WINDOW IS 16 KiB, THE LEAST A DEVICE GIVES (WebGPU's default for
// `max_compute_workgroup_storage_size`, what the engine asks for): 2048
// pixels of two words. A reach past what one stretch holds takes more
// stretches through the same lines, not a device asked for more (관제
// 11-08 10:22).
//
// ⚠️IT IS NOT ZEROED FIRST (gaussian.rs builds it unzeroed — zeroing 16 KiB
// a workgroup cost more than the window saved at a small reach): a thread
// reads only words of the stretch its workgroup put before the barrier.
const GAUSSIAN_THREADS: u32 = 256u;
const GAUSSIAN_WINDOW: u32 = 2048u;
var<workgroup> gaussian_window: array<vec2<u32>, GAUSSIAN_WINDOW>;

// How many lines a workgroup takes — the rest of its threads go along
// them: the rows' one line, 256 pixels along it; the columns' eight, side
// by side, 32 down them. Gaussian.rs's `Pass::dispatch` counts the groups
// by these.
fn gaussian_lines(down: bool) -> u32 {
  return select(1u, 8u, down);
}

// A thread a pixel: the threads beside each other take the lines beside
// each other, then the next pixels along — so the reads into the window
// go along a row of the tiles either way. Every thread goes round every
// stretch, put or not: a barrier waits for all of them.
@compute @workgroup_size(256, 1, 1)
fn gaussian_blur(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_index) thread: u32,
) {
  let down = gaussian_.down == 1u;
  let lines = gaussian_lines(down);
  let along = GAUSSIAN_THREADS / lines;
  let stretch = i32(GAUSSIAN_WINDOW / lines);
  let reach = i32(gaussian_.reach);
  let first = gaussian_.first + i32(select(group.x, group.y, down) * along);
  let line_first = gaussian_.line_first + i32(select(group.y, group.x, down) * lines);
  let line = line_first + i32(thread % lines);
  let p = first + i32(thread / lines);

  // What the workgroup's taps cover: [first − reach, first + along + reach).
  let start = first - reach;
  let span = i32(along) + 2 * reach;
  let middle = gaussian_.weights;
  var sum = vec4<u32>(0u);
  for (var at = start; at < start + span; at += stretch) {
    let held = min(stretch, start + span - at);
    for (var k = thread; k < u32(held) * lines; k += GAUSSIAN_THREADS) {
      let tap = gaussian_tap(line_first + i32(k % lines), at + i32(k / lines));
      gaussian_window[k] = blend_pack16(tap);
    }
    workgroupBarrier();
    // By the tap's distance, not its place: the threads of a stretch held
    // whole all read the same weight at once.
    let low = max(-reach, at - p);
    let high = min(reach, at + held - 1 - p);
    for (var d = low; d <= high; d++) {
      let weight = gaussian_weights[middle + u32(abs(d))];
      let tap = gaussian_window[u32(p + d - at) * lines + thread % lines];
      sum += weight * blend_unpack16(tap);
    }
    workgroupBarrier();
  }

  if (p >= gaussian_.end || line >= gaussian_.line_end) {
    return;
  }
  let pixel = (sum + vec4<u32>(32768u)) >> vec4<u32>(16u);
  if (down) {
    held_write(line, p, pixel);
  } else {
    held_write(p, line, pixel);
  }
}
