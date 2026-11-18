// Three box passes of a way in one dispatch (gpu-canonical-store 01:13,
// 01:15 (b)): a workgroup takes a strip of the way — a run along some of its
// lines — and works the three passes over it in its own memory, so no pass
// waits on another workgroup's. Each pass puts as far past the strip as it
// puts past the way's last, so the strip reads past what it puts as far as
// the way's first pass reads past the way's last. The blur brush's strips
// go by it (kernels/dab/blur_three.wgsl); how a way is cut is boxes.rs's
// `strips`.
//
// Needs blend/blend.wgsl and box.wgsl before it, and from what includes it:
//   blur_load(first: BoxPass, line: i32, p: i32) -> vec4<u32> — the pixel
//     the way's first pass reads at `p` along `line`;
//   blur_store(last: BoxPass, line: i32, p: i32, pixel: vec4<u32>) — puts
//     the way's last pass's pixel there.

// The pixels a strip holds, in each half of its room: a pass reads one half
// and puts the other. Two halves of 1024 are the 16KB every device gives a
// workgroup (boxes.rs's ROOM).
const BLUR_ROOM: u32 = 1024u;
const BLUR_LANES: u32 = 256u;
var<workgroup> blur_room: array<vec2<u32>, 2048>;

// The strip: its lines from `blur_line0`, each `blur_span` pixels from
// `blur_span0`; the half a pass reads and the half it puts.
var<private> blur_line0: i32;
var<private> blur_span0: i32;
var<private> blur_span: u32;
var<private> blur_from: u32;
var<private> blur_to: u32;

// Where the strip's pixel `p` along `line` is in a half.
fn blur_at(line: i32, p: i32) -> u32 {
  return u32(line - blur_line0) * blur_span + u32(p - blur_span0);
}

fn blur_tap(line: i32, p: i32) -> vec4<u32> {
  return blend_unpack16(blur_room[blur_from + blur_at(line, p)]);
}

fn blur_put(line: i32, p: i32, mean: vec4<u32>) {
  blur_room[blur_to + blur_at(line, p)] = blend_pack16(mean);
}

// The way of `passes`, the strip `strip` along and `band` across: `run`
// pixels along `lines` lines a workgroup. The lanes take runs of a line
// between them, pass by pass.
fn blur_way(passes: array<BoxPass, 3>, strip: u32, band: u32, run: u32, lines: u32, lane: u32) {
  let first = passes[0];
  let last = passes[2];
  let put0 = last.first + i32(strip * run);
  // The last strip stops at the way's end. Past it, its puts would land on
  // the next line's first pixels, racing the workgroup that puts them —
  // which lands last on every device here, so no test tells this `min` from
  // its absence (mutant w18, 11-06).
  let put1 = min(put0 + i32(run), last.end);
  blur_line0 = first.line_first + i32(band * lines);
  let count = u32(min(blur_line0 + i32(lines), first.line_end) - blur_line0);
  let r = i32(first.radius);
  blur_span0 = put0 - (last.first - first.first) - r;
  blur_span = u32(put1 + (first.end - last.end) + r - blur_span0);
  for (var i = lane; i < count * blur_span; i += BLUR_LANES) {
    let line = blur_line0 + i32(i / blur_span);
    blur_room[i] = blend_pack16(blur_load(first, line, blur_span0 + i32(i % blur_span)));
  }
  workgroupBarrier();
  for (var k = 0u; k < 3u; k++) {
    let pass_ = passes[k];
    let start = put0 - (last.first - pass_.first);
    let stop = put1 + (pass_.end - last.end);
    let along = u32(stop - start);
    let each = max(1u, (count * along + BLUR_LANES - 1u) / BLUR_LANES);
    let runs = (along + each - 1u) / each;
    blur_from = select(BLUR_ROOM, 0u, k != 1u);
    blur_to = BLUR_ROOM - blur_from;
    for (var t = lane; t < count * runs; t += BLUR_LANES) {
      let s = start + i32((t % runs) * each);
      blur_slide(blur_line0 + i32(t / runs), s, min(s + i32(each), stop), pass_.radius);
    }
    workgroupBarrier();
  }
  let puts = u32(put1 - put0);
  for (var i = lane; i < count * puts; i += BLUR_LANES) {
    let line = blur_line0 + i32(i / puts);
    let p = put0 + i32(i % puts);
    blur_store(last, line, p, blend_unpack16(blur_room[BLUR_ROOM + blur_at(line, p)]));
  }
}
