// A sound's waveform tile (gpu-int-spec-timeline ②): each lane's |peak|
// envelope drawn as a band mirrored about the middle of the lane's share
// of the strip — WaveformPainter's band, one thread a pixel.
//
// Along the strip the envelope is the line through the bucket peaks, and a
// column shows the most of that line over the column's stretch: the two
// ends, drawn between their buckets, and every peak in between (the range
// table mod.rs builds). Where the column's ends stand in the buckets is
// worked out exactly by mod.rs — WGSL has no 64-bit integer — and handed
// over, an edge a column.
//
// Across, a row is covered by how much of it the band [middle − reach,
// middle + reach] overlaps, in q8, and the band laid by the normal
// composite (laid.wgsl), and the pixel stored premultiplied, as the grid's
// is (grid.wgsl has why). Integers only, as fill.wgsl has why.
//
// Needs blend/blend.wgsl, laid.wgsl and shared/premultiply.wgsl before it.

struct Params {
  width: u32,
  height: u32,
  // Nonzero: the strip runs down, x across.
  vertical: u32,
  lanes: u32,
  buckets: u32,
  // The range table's levels: level k holds the most of 2^k buckets.
  levels: u32,
  across_q8: u32,
  // A lane's full reach, q8, the clip's gain in it.
  scale_q8: u32,
  rgba: u32,
  // The tile's pixel before the band, as an RGBA word.
  background: u32,
  pad0: u32,
  pad1: u32,
}

@group(0) @binding(0) var<uniform> params: Params;
// The range table, two u16 a word: lane, then level, then bucket.
@group(0) @binding(1) var<storage, read> peaks: array<u32>;
// Where each column's edge stands: (bucket, how far on to the next, q16),
// held to the envelope's first and last bucket.
@group(0) @binding(2) var<storage, read> edges: array<vec2<u32>>;
@group(0) @binding(3) var tile: texture_storage_2d<__FORMAT__, write>;

// The most of `lane`'s 2^`level` buckets from bucket `i`, q16.
fn table(lane: u32, level: u32, i: u32) -> u32 {
  let at = (lane * params.levels + level) * params.buckets + i;
  return (peaks[at >> 1u] >> ((at & 1u) * 16u)) & 0xffffu;
}

// The most of `lane`'s buckets `low` to `high`, both in: two blocks of the
// largest level that fits, one from each end.
fn most(lane: u32, low: u32, high: u32) -> u32 {
  let level = firstLeadingBit(high - low + 1u);
  return max(table(lane, level, low), table(lane, level, high + 1u - (1u << level)));
}

// The envelope at `edge`: its bucket's peak drawn toward the next one's,
// rounded half up. The weights sum to 2^16, so the sum stays a u32.
fn at_edge(lane: u32, edge: vec2<u32>) -> u32 {
  let next = min(edge.x + 1u, params.buckets - 1u);
  let drawn = table(lane, 0u, edge.x) * (65536u - edge.y) + table(lane, 0u, next) * edge.y;
  return (drawn + 32768u) >> 16u;
}

// A q16 peak times a q8 scale below 2^24, rounded half up — the scale cut
// at its 12th bit so no product passes 32 bits.
fn scaled(peak: u32, scale: u32) -> u32 {
  let high = peak * (scale >> 12u);
  let low = peak * (scale & 0xfffu) + 32768u;
  return (high >> 4u) + ((((high & 15u) << 12u) + low) >> 16u);
}

@compute @workgroup_size(8, 8)
fn wave(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= params.width || id.y >= params.height) {
    return;
  }
  var pixel = blend_unpack8(params.background);
  let along = select(id.x, id.y, params.vertical != 0u);
  let across = select(id.y, id.x, params.vertical != 0u);
  let first = edges[along];
  let last = edges[along + 1u];
  // A column shows the envelope where its stretch, held to the envelope's,
  // is longer than nothing.
  let shown = first.x < last.x || (first.x == last.x && first.y < last.y);
  let middle = across * 256u + 128u;
  // A row past the strip has no lane: its lane would read past the table,
  // and WGSL lets such a read return anything in it — a band there on some
  // devices, though not on the one the tests run on.
  if (shown && middle < params.across_q8) {
    // The lane the row's middle falls in: no other lane's band reaches it,
    // each stopping a pixel inside its share.
    let lane = middle * params.lanes / params.across_q8;
    var peak = max(at_edge(lane, first), at_edge(lane, last));
    if (last.x > first.x) {
      peak = max(peak, most(lane, first.x + 1u, last.x));
    }
    let reach = i32(scaled(peak, params.scale_q8));
    let centre = i32(params.across_q8 * (2u * lane + 1u) / (2u * params.lanes));
    let top = i32(across * 256u);
    let cover = clamp(min(top + 256, centre + reach) - max(top, centre - reach), 0, 256);
    let rgba = params.rgba;
    pixel = laid(pixel, rgba, (u32(cover) * (rgba >> 24u) * 257u + 128u) >> 8u);
  }
  let packed = premultiply8(blend_pack8(pixel));
  // The one float step, as fill.wgsl's.
  textureStore(tile, id.xy, unpack4x8unorm(packed));
}
