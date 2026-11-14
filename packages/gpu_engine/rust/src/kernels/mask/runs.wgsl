// A selection's hard mask as its runs: region.wgsl's bit plane read for
// where each row's selected pixels start and end, and not a byte a pixel
// of its box — what the app's CPU readers of a selection ask (its ants,
// the area a shape fills, a cut from the viewer's picture).
//
// A run starts at a column whose bit is set where the column left of it
// is clear (the first column's left is clear), and ends at the first
// column past it whose bit is clear: each is a transition, a bit unlike
// the one left of it. The plane has room for a bit past the box that is
// never set, so every run ends inside its row.
//
// Three passes: each row counts its transitions (`runs_count`), one
// workgroup lays the rows' counts end to end (`runs_offsets`), and each
// row puts its transitions' columns from where its count starts
// (`runs_put`) — row r's are runs[offsets[r] .. offsets[r + 1]], a start
// and an end in turn, counted from the box's left.

// The plane's rows and words a row, and the runs' room.
struct Runs {
  height: u32,
  stride: u32,
  room: u32,
  pad: u32,
}

@group(0) @binding(0) var<uniform> runs_of: Runs;
@group(0) @binding(1) var<storage, read> plane: array<u32>;
@group(0) @binding(2) var<storage, read_write> offsets: array<u32>;
@group(0) @binding(3) var<storage, read_write> runs: array<u32>;

// The transitions of row `row`'s word `word`: bit i set where column
// 32·word + i is unlike the column left of it.
fn runs_transitions(row: u32, word: u32) -> u32 {
  let at = row * runs_of.stride + word;
  let bits = plane[at];
  var left = 0u;
  if (word > 0u) {
    left = plane[at - 1u] >> 31u;
  }
  return bits ^ ((bits << 1u) | left);
}

// A thread a row: its transitions' count, where the next row's start.
@compute @workgroup_size(64, 1, 1)
fn runs_count(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= runs_of.height) {
    return;
  }
  var count = 0u;
  for (var word = 0u; word < runs_of.stride; word++) {
    count += countOneBits(runs_transitions(id.x, word));
  }
  offsets[id.x + 1u] = count;
}

const RUNS_SCAN: u32 = 256u;

var<workgroup> runs_partial: array<u32, RUNS_SCAN>;

// One workgroup: the counts laid end to end — each entry the sum of those
// before it, the first row starting at 0. A thread sums its own stretch of
// rows, the threads' sums are laid end to end among them, and each thread
// lays its stretch from where its sums start.
@compute @workgroup_size(256, 1, 1)
fn runs_offsets(@builtin(local_invocation_id) id: vec3<u32>) {
  let entries = runs_of.height + 1u;
  let stretch = (entries + RUNS_SCAN - 1u) / RUNS_SCAN;
  let first = min(id.x * stretch, entries);
  let last = min(first + stretch, entries);
  var sum = 0u;
  for (var at = max(first, 1u); at < last; at++) {
    sum += offsets[at];
  }
  runs_partial[id.x] = sum;
  workgroupBarrier();
  for (var step = 1u; step < RUNS_SCAN; step <<= 1u) {
    var before = 0u;
    if (id.x >= step) {
      before = runs_partial[id.x - step];
    }
    workgroupBarrier();
    runs_partial[id.x] += before;
    workgroupBarrier();
  }
  var running = 0u;
  if (id.x > 0u) {
    running = runs_partial[id.x - 1u];
  }
  for (var at = first; at < last; at++) {
    if (at > 0u) {
      running += offsets[at];
    }
    offsets[at] = running;
  }
}

// A thread a row: its transitions' columns, left to right, from where its
// count starts — none past the room, which the engine sized to hold every
// crossing a row can have.
@compute @workgroup_size(64, 1, 1)
fn runs_put(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= runs_of.height) {
    return;
  }
  var at = offsets[id.x];
  for (var word = 0u; word < runs_of.stride; word++) {
    var transitions = runs_transitions(id.x, word);
    while (transitions != 0u) {
      if (at < runs_of.room) {
        runs[at] = word * 32u + firstTrailingBit(transitions);
      }
      at += 1u;
      transitions &= transitions - 1u;
    }
  }
}
