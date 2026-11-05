// A coverage mask's finishing passes, by gpu-int-spec-canvas 1b S2: a
// generation of the 4-neighbour grow or shrink (S2a — the app's
// mask_morphology.dart), the boundary soften (S2c — softenMaskBoundary),
// and the feather (S2b): the 3-4 chamfer distance (chamferDistance34)
// relaxed a generation at a time, then the ramp over it.
//
// A mask is a plane of bytes over its box, `width` × `height`, four to a
// word with the leftmost in the low byte, each row `stride` words — the
// app's Uint8List row after row. A distance plane holds two 16-bit
// distances to a word the same way, a row `(width + 1) / 2` words. Past
// the box there is nothing: a byte reads 0 there and a distance is no
// neighbour, as at the edge of the app's buffer. Every pass reads one
// plane and puts another, so a pixel never reads what its neighbour put
// in the same pass.
//
// ⚠️A row past the box's last is past the plane, where DX12 reads 0 and
// drops a write — so the tests here cannot see the box's guards on rows
// there; Metal clamps the index instead.
//
// Needs shared/wide.wgsl before it.

// The box, and the feather's ramp: 3 chamfer units a pixel, Q.8.
struct Mask {
  width: u32,
  height: u32,
  stride: u32,
  ramp: u32,
}

// The farthest distance — chamferDistance34's `infinity`.
const MASK_FAR: u32 = 60000u;
// The distance the box's edge lies at: a pixel on it ramps as if the one
// past it were out (`_featherMask`'s border, the selection's). ⏳The fill's
// finish (stage 5) starts its distances at another byte with no edge, and
// softens without the selection's clamp — they come as words of their own.
const MASK_EDGE: u32 = 3u;

@group(0) @binding(0) var<uniform> mask: Mask;
@group(0) @binding(1) var<storage, read> bytes_in: array<u32>;
@group(0) @binding(2) var<storage, read_write> bytes_out: array<u32>;
@group(0) @binding(3) var<storage, read> distances_in: array<u32>;
@group(0) @binding(4) var<storage, read_write> distances_out: array<u32>;

// Whether (x, y) is in the box — a negative wraps past either side.
fn mask_inside(x: i32, y: i32) -> bool {
  return u32(x) < mask.width && u32(y) < mask.height;
}

// The byte at (x, y); 0 past the box.
fn mask_byte(x: i32, y: i32) -> u32 {
  if (!mask_inside(x, y)) {
    return 0u;
  }
  let word = bytes_in[u32(y) * mask.stride + u32(x) / 4u];
  return (word >> (u32(x) % 4u * 8u)) & 0xffu;
}

// The distance at (x, y), inside the box.
fn mask_distance(x: i32, y: i32) -> u32 {
  let word = distances_in[u32(y) * ((mask.width + 1u) / 2u) + u32(x) / 2u];
  return (word >> (u32(x) % 2u * 16u)) & 0xffffu;
}

// The four side neighbours of (x, y): left, right, up, down.
fn mask_sides(x: i32, y: i32) -> vec4<u32> {
  return vec4<u32>(mask_byte(x - 1, y), mask_byte(x + 1, y), mask_byte(x, y - 1), mask_byte(x, y + 1));
}

// A grow's generation: a pixel in keeps its byte; one out that touches one
// in on a side comes in whole.
fn mask_grown(x: i32, y: i32) -> u32 {
  let centre = mask_byte(x, y);
  if (centre != 0u) {
    return centre;
  }
  return select(0u, 255u, any(mask_sides(x, y) != vec4<u32>(0u)));
}

// A shrink's generation: a pixel touching one out on a side — past the
// box is out — goes out; the rest keep their byte, and one out its 0.
fn mask_shrunk(x: i32, y: i32) -> u32 {
  return select(mask_byte(x, y), 0u, any(mask_sides(x, y) == vec4<u32>(0u)));
}

// The boundary soften: (3 · centre + sides) / 7, rounded — 7 being odd, a
// sum is never a half over it, so + 3 rounds it as the app's double
// rounding does. A pixel whose four sides are its own sums to its own byte
// (the app skips it). ⚠️INSIDE THE OUTLINE ONLY (유저 2026-08-27,
// softenMaskBoundary's head): it never rises past the pixel's own byte, so
// a selection lifts no ring of its neighbour's art.
fn mask_softened(x: i32, y: i32) -> u32 {
  let centre = mask_byte(x, y);
  let sides = mask_sides(x, y);
  let around = sides.x + sides.y + sides.z + sides.w;
  return min((3u * centre + around + 3u) / 7u, centre);
}

// The feather's alpha at (x, y): nothing out; in, its distance over the
// ramp, rounded — or whole at the ramp and past it, which spares the
// division a ramp of 0 (a feather under half a Q.8 step); at the ramp the
// division would be 255 as well.
fn mask_feathered(x: i32, y: i32) -> u32 {
  if (mask_byte(x, y) == 0u) {
    return 0u;
  }
  let distance = mask_distance(x, y);
  if (distance * 256u >= mask.ramp) {
    return 255u;
  }
  return wide_divr(Wide(distance * 65280u, 0u), Wide(mask.ramp, 0u), 8u);
}

// A thread puts a word: four bytes, or two distances. Each entry below
// calls only the function its pass reads by, so its pipeline binds only
// the planes that pass reads and puts (a WGSL entry binds whatever its
// calls reach).

// Pixel `k` of the word thread `id` puts, `per` to a word: its (x, y) —
// past the box's last column where the row's last word is not full. A
// thread stops there for its work alone: what it put would land in the
// row's padding, which no pass reads.
fn mask_pixel(id: vec3<u32>, k: u32, per: u32) -> vec2<i32> {
  return vec2<i32>(i32(id.x * per + k), i32(id.y));
}

fn mask_put_byte_words(id: vec3<u32>) -> bool {
  return id.x < mask.stride && id.y < mask.height;
}

const MASK_GROW: u32 = 0u;
const MASK_SHRINK: u32 = 1u;
const MASK_SOFTEN: u32 = 2u;

// A grow, shrink or soften's word.
fn mask_put_stencil(id: vec3<u32>, kind: u32) {
  if (!mask_put_byte_words(id)) {
    return;
  }
  var word = 0u;
  for (var k = 0u; k < 4u; k++) {
    let at = mask_pixel(id, k, 4u);
    if (u32(at.x) >= mask.width) {
      break;
    }
    var byte: u32;
    switch (kind) {
      case MASK_GROW: {
        byte = mask_grown(at.x, at.y);
      }
      case MASK_SHRINK: {
        byte = mask_shrunk(at.x, at.y);
      }
      default: {
        byte = mask_softened(at.x, at.y);
      }
    }
    word = word | (byte << (k * 8u));
  }
  bytes_out[id.y * mask.stride + id.x] = word;
}

@compute @workgroup_size(8, 8, 1)
fn mask_grow(@builtin(global_invocation_id) id: vec3<u32>) {
  mask_put_stencil(id, MASK_GROW);
}

@compute @workgroup_size(8, 8, 1)
fn mask_shrink(@builtin(global_invocation_id) id: vec3<u32>) {
  mask_put_stencil(id, MASK_SHRINK);
}

@compute @workgroup_size(8, 8, 1)
fn mask_soften(@builtin(global_invocation_id) id: vec3<u32>) {
  mask_put_stencil(id, MASK_SOFTEN);
}

@compute @workgroup_size(8, 8, 1)
fn mask_feather(@builtin(global_invocation_id) id: vec3<u32>) {
  if (!mask_put_byte_words(id)) {
    return;
  }
  var word = 0u;
  for (var k = 0u; k < 4u; k++) {
    let at = mask_pixel(id, k, 4u);
    if (u32(at.x) >= mask.width) {
      break;
    }
    word = word | (mask_feathered(at.x, at.y) << (k * 8u));
  }
  bytes_out[id.y * mask.stride + id.x] = word;
}

// A distance's start: 0 where the mask is out, the farthest elsewhere,
// and on the box's edge no farther than MASK_EDGE.
fn mask_seeded(x: i32, y: i32) -> u32 {
  var distance = select(MASK_FAR, 0u, mask_byte(x, y) == 0u);
  let edge = x == 0 || y == 0 || u32(x) + 1u == mask.width || u32(y) + 1u == mask.height;
  if (edge) {
    distance = min(distance, MASK_EDGE);
  }
  return distance;
}

// A generation of the chamfer: the least of the pixel's own distance and,
// over the 3 × 3 about it, each in the box 3 across a side or 4 across a
// corner on — the pixel itself among them, never nearer than its own, so
// a distance never grows past MASK_FAR. Run to its end it is the app's two
// passes, byte for byte (대조 ② closed 11-05: 6000 random masks).
// A distance past the box is no neighbour. The selection cannot see that —
// its edge starts at MASK_EDGE, no farther than a step from anything — but
// ⏳the fill's finish starts no edge.
fn mask_relaxed(x: i32, y: i32) -> u32 {
  var best = mask_distance(x, y);
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      if (mask_inside(x + dx, y + dy)) {
        let step = select(3u, 4u, dx != 0 && dy != 0);
        best = min(best, mask_distance(x + dx, y + dy) + step);
      }
    }
  }
  return best;
}

fn mask_put_distance_words(id: vec3<u32>) -> bool {
  return id.x < (mask.width + 1u) / 2u && id.y < mask.height;
}

fn mask_distance_word(id: vec3<u32>) -> u32 {
  return id.y * ((mask.width + 1u) / 2u) + id.x;
}

@compute @workgroup_size(8, 8, 1)
fn mask_seed(@builtin(global_invocation_id) id: vec3<u32>) {
  if (!mask_put_distance_words(id)) {
    return;
  }
  var word = 0u;
  for (var k = 0u; k < 2u; k++) {
    let at = mask_pixel(id, k, 2u);
    if (u32(at.x) >= mask.width) {
      break;
    }
    word = word | (mask_seeded(at.x, at.y) << (k * 16u));
  }
  distances_out[mask_distance_word(id)] = word;
}

@compute @workgroup_size(8, 8, 1)
fn mask_relax(@builtin(global_invocation_id) id: vec3<u32>) {
  if (!mask_put_distance_words(id)) {
    return;
  }
  var word = 0u;
  for (var k = 0u; k < 2u; k++) {
    let at = mask_pixel(id, k, 2u);
    if (u32(at.x) >= mask.width) {
      break;
    }
    word = word | (mask_relaxed(at.x, at.y) << (k * 16u));
  }
  distances_out[mask_distance_word(id)] = word;
}
