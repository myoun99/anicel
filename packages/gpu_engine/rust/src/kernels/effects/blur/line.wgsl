// A blur along a way — a directional blur's line, a radial blur's circle
// or ray (the app's directional_blur.frag, `LineBoxPass`) — by the integer
// spec gpu-int-spec-canvas 1b (4/4): every pixel of the plate the mean of
// `taps` taps, the i-th at C + M_i·(at − C) + o_i — `at` the pixel's
// centre, M_i the tap's turn and scale (Q.20) and o_i its shift along the
// way (Q.16), both worked out by the CPU. A tap is the four pixels it falls
// between, weighed by Q.8 fractions that sum to 2^16 (the bilinear filter
// the app asks for); a pixel past the plate is nothing, and so is a tap
// landing past it (decal). The taps are summed exactly and divided once.
//
// Needs shared/wide.wgsl and held.wgsl before it.

// One pass: where its taps begin in `taps` and how many, the centre C
// (Q.16), the plate's pixels, [left, right) × [top, bottom), and the rows
// of it this pass puts, [put_top, put_bottom) — a band's (line.rs's
// `puts`).
struct LinePass {
  taps_at: u32,
  taps: u32,
  centre_x: i32,
  centre_y: i32,
  left: i32,
  top: i32,
  right: i32,
  bottom: i32,
  put_top: i32,
  put_bottom: i32,
}

@group(0) @binding(3) var<uniform> line_: LinePass;
// Six words a tap: M_i's a, b, c, d (Q.20) — x' = a·dx + b·dy,
// y' = c·dx + d·dy — then o_i's x and y (Q.16).
@group(0) @binding(4) var<storage, read> taps: array<u32>;

fn line_word(at: u32) -> i32 {
  return bitcast<i32>(taps[at]);
}

// A tap along one axis, Q.16: the centre, the map's row over the pixel's
// way from it (rounded from Q.36 once), and the shift.
fn line_axis(centre: i32, m: i32, n: i32, dx: Wide, dy: Wide, shift: i32) -> Wide {
  let turned = wide_round(wide_add(wide_mul(wide(m), dx), wide_mul(wide(n), dy)), 20u);
  return wide_add(wide_add(wide(centre), turned), wide(shift));
}

// Whether `p` (Q.16) lies on the plate from `low` to `high` (pixels),
// either end on it.
fn line_on_plate(p: Wide, low: i32, high: i32) -> bool {
  return !wide_less(p, wide(low << 16u)) && !wide_less(wide(high << 16u), p);
}

// The pixel at (x, y) — nothing past the plate.
fn line_texel(x: i32, y: i32) -> vec4<u32> {
  if (x < line_.left || x >= line_.right || y < line_.top || y >= line_.bottom) {
    return vec4<u32>(0u);
  }
  return held_read(x, y);
}

// A tap at (px, py), Q.16 on the plate: the four pixels it falls between,
// each weighed by how near — 2^16 in all, so a channel's sum stays a u32.
fn line_tap(px: i32, py: i32) -> vec4<u32> {
  let u = px - 32768;
  let v = py - 32768;
  let x = u >> 16u;
  let y = v >> 16u;
  let fx = u32(((u & 0xffff) + 128) >> 8u);
  let fy = u32(((v & 0xffff) + 128) >> 8u);
  return line_texel(x, y) * ((256u - fx) * (256u - fy))
    + line_texel(x + 1, y) * (fx * (256u - fy))
    + line_texel(x, y + 1) * ((256u - fx) * fy)
    + line_texel(x + 1, y + 1) * (fx * fy);
}

@compute @workgroup_size(8, 8, 1)
fn line_blur(@builtin(global_invocation_id) id: vec3<u32>) {
  let x = line_.left + i32(id.x);
  let y = line_.put_top + i32(id.y);
  // Only the band's rows. Past them the band after puts its own, so no test
  // of this machine tells `put_bottom` from the plate's bottom (mutant b19,
  // 11-07) — but a pass between two others puts a plane only as tall as its
  // rows, and a write past a buffer lands where the device likes: dropped
  // on DX12, on its last word where Metal clamps the index.
  if (x >= line_.right || y >= line_.put_bottom) {
    return;
  }
  let dx = wide_sub(wide(x * 65536 + 32768), wide(line_.centre_x));
  let dy = wide_sub(wide(y * 65536 + 32768), wide(line_.centre_y));
  var sum = array<Wide, 4>(Wide(0u, 0u), Wide(0u, 0u), Wide(0u, 0u), Wide(0u, 0u));
  for (var i = 0u; i < line_.taps; i++) {
    let at = line_.taps_at + i * 6u;
    let px = line_axis(
      line_.centre_x, line_word(at), line_word(at + 1u), dx, dy, line_word(at + 4u),
    );
    let py = line_axis(
      line_.centre_y, line_word(at + 2u), line_word(at + 3u), dx, dy, line_word(at + 5u),
    );
    if (line_on_plate(px, line_.left, line_.right)
        && line_on_plate(py, line_.top, line_.bottom)) {
      let tap = line_tap(bitcast<i32>(px.x), bitcast<i32>(py.x));
      for (var c = 0u; c < 4u; c++) {
        sum[c] = wide_add(sum[c], Wide(tap[c], 0u));
      }
    }
  }
  let whole = Wide(line_.taps << 16u, 0u);
  held_write(x, y, vec4<u32>(
    wide_divr(sum[0], whole, 16u),
    wide_divr(sum[1], whole, 16u),
    wide_divr(sum[2], whole, 16u),
    wide_divr(sum[3], whole, 16u),
  ));
}
