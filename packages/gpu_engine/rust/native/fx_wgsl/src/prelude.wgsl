// ── The host's part of every plugin (fx spec 2) ──────────────────────────
// Appended after the plugin's own source, so a refusal's line is the
// plugin's line. A plugin reaches the pictures, its values and the moment
// through the `anicel_` functions below and nothing else: the bindings and
// every `anicel_host_` name are the host's, and the check refuses a plugin
// that names one (check.rs).

// What the host hands one run. Places are canvas pixels, in the output's
// pixels; a picture is one u32 per pixel, the engine pool's straight RGBA8
// word. A value is four i32s: number and angle Q.16, a point Q.16 canvas
// pixels, a color 16 bits a channel, a checkbox 0 or 1, a menu its choice's
// place, a layer its plane's slot or -1 (design 1/3 and ③).
struct AnicelFrame {
  out_origin: vec2<i32>,
  out_size: vec2<i32>,
  in_origin: vec2<i32>,
  in_size: vec2<i32>,
  rows: i32,
  values: i32,
  frame: i32,
  time_q16: i32,
  rate_q16: i32,
  scale_q16: i32,
  fuel: u32,
  spare: u32,
}

@group(0) @binding(0) var<uniform> anicel_host_frame: AnicelFrame;
@group(0) @binding(1) var<storage, read> anicel_host_input: array<u32>;
@group(0) @binding(2) var<storage, read_write> anicel_host_output: array<u32>;
@group(0) @binding(3) var<storage, read> anicel_host_values: array<vec4<i32>>;
@group(0) @binding(4) var<storage, read> anicel_host_rows: array<u32>;
@group(0) @binding(5) var<storage, read_write> anicel_host_cut: atomic<u32>;

var<private> anicel_host_here: vec2<i32>;
var<private> anicel_host_fuel: u32;
// Whether any invocation of this group was cut: what a loop that waits at
// a barrier breaks on, so the group leaves it together (Q6 ⓐ).
var<workgroup> anicel_host_group_cut: atomic<u32>;

// The place of (x, y) in a plane at `origin` of `size`, or -1 outside it.
fn anicel_host_place(origin: vec2<i32>, size: vec2<i32>, x: i32, y: i32) -> i32 {
  let px = x - origin.x;
  let py = y - origin.y;
  if (px < 0 || py < 0 || px >= size.x || py >= size.y) {
    return -1;
  }
  return py * size.x + px;
}

// Called first in `anicel_render` (count.rs puts the call there).
fn anicel_host_enter(at: vec3<u32>) {
  anicel_host_here = anicel_host_frame.out_origin + vec2<i32>(at.xy);
  anicel_host_fuel = anicel_host_frame.fuel;
}

// Called at the top of every loop of the plugin's with what one turn costs
// (count.rs): spends it from this invocation's share, or marks the run cut
// and answers true — the loop breaks, and every loop after breaks on its
// first turn, so the invocation ends. Its group is marked cut too.
fn anicel_host_spend(cost: u32) -> bool {
  if (anicel_host_fuel < cost) {
    anicel_host_fuel = 0u;
    atomicMax(&anicel_host_cut, 1u);
    atomicMax(&anicel_host_group_cut, 1u);
    return true;
  }
  anicel_host_fuel = anicel_host_fuel - cost;
  return false;
}

// The charge of a loop of the render that waits at a barrier (count.rs):
// each invocation spends from its own share as above, and the whole group
// breaks once any of it was cut — read at a barrier, so alike in all.
fn anicel_host_spend_together(cost: u32) -> bool {
  _ = anicel_host_spend(cost);
  return workgroupUniformLoad(&anicel_host_group_cut) != 0u;
}

// The canvas place of the pixel this invocation writes.
fn anicel_here() -> vec2<i32> {
  return anicel_host_here;
}

// The input's pixel at canvas place (x, y); transparent outside the input,
// as spec 1's `Picture::at` answered None there.
fn anicel_in(x: i32, y: i32) -> u32 {
  let at = anicel_host_place(anicel_host_frame.in_origin, anicel_host_frame.in_size, x, y);
  if (at < 0) {
    return 0u;
  }
  return anicel_host_input[at];
}

// The pixel at canvas place (x, y) of the layer in `slot` (a layer value);
// transparent outside it and for a slot that names no layer.
fn anicel_row(slot: i32, x: i32, y: i32) -> u32 {
  if (slot < 0 || slot >= anicel_host_frame.rows) {
    return 0u;
  }
  let at = anicel_host_place(anicel_host_frame.in_origin, anicel_host_frame.in_size, x, y);
  if (at < 0) {
    return 0u;
  }
  let plane = anicel_host_frame.in_size.x * anicel_host_frame.in_size.y;
  return anicel_host_rows[slot * plane + at];
}

// Word `k` (0 to 3) of value `i`, in the order the plugin declares its
// parameters; 0 past either.
fn anicel_value(i: i32, k: i32) -> i32 {
  if (i < 0 || i >= anicel_host_frame.values || k < 0 || k > 3) {
    return 0;
  }
  return anicel_host_values[i][k];
}

// Writes this invocation's own pixel — the one place `anicel_here` names,
// so no two invocations write one pixel.
fn anicel_out(rgba: u32) {
  let at = anicel_host_place(
    anicel_host_frame.out_origin,
    anicel_host_frame.out_size,
    anicel_host_here.x,
    anicel_host_here.y,
  );
  if (at < 0) {
    return;
  }
  anicel_host_output[at] = rgba;
}

// The moment: the frame's number, its time in Q.16 seconds, the frame
// rate in Q.16 frames a second, and the canvas's scale in Q.16.
fn anicel_frame() -> i32 {
  return anicel_host_frame.frame;
}

fn anicel_time() -> i32 {
  return anicel_host_frame.time_q16;
}

fn anicel_rate() -> i32 {
  return anicel_host_frame.rate_q16;
}

fn anicel_scale() -> i32 {
  return anicel_host_frame.scale_q16;
}
