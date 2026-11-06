// R4 들어올리기 and C 잘라내기's read (gpu-census R4 · C): what a
// selection takes off a cel — the app's `gatherMaskedSurfacePixels`, one
// read for the move's lift and the cut piece (「⛔ONE LIFT」) — laid in the
// mask's box row after row as straight RGBA8. A pixel the mask leaves out,
// or with no ink, stays 0; the rest keep their colour and their alpha.
//
// 🚨A pixel the mask covers at all travels WHOLE (the app's
// `takeWholePixels`): the mask says which pixels move, not how much of
// each — a lift that scaled its alpha left a ghost of the drawing along
// the selection's edge (유저 2026-08-27). The feather is the exception:
// its softness was asked for, so there the alpha is scaled by the
// coverage, rounded as the premultiply rounds.
//
// A tile is a workgroup and a row a lane, as the verbs walk (walk.wgsl).
// A pass binds the box's rows its tiles lie on, from a word a binding may
// start at; a pixel taken sets the flag the app reads as `liftedAnything`.
//
// Needs shared/premultiply.wgsl and walk.wgsl (with what it needs) before
// it.

struct Lift {
  // The pass's rows of the mask in `given`: where they start, the box's
  // pixels across, the rows given, a row's words.
  mask_at: u32,
  mask_width: u32,
  mask_height: u32,
  mask_stride: u32,
  // The box's row the pass's rows start at, and the word of the box's
  // pixels the bound ones start at.
  first_row: u32,
  lifted_base: u32,
  // 1: a pixel the mask covers at all travels whole.
  whole: u32,
}

@group(0) @binding(0) var<uniform> lift: Lift;
// The box's pixels, row after row: the pass's rows of them.
@group(0) @binding(2) var<storage, read_write> lifted: array<u32>;
// 1 once a pixel is taken.
@group(0) @binding(3) var<storage, read_write> lifted_any: atomic<u32>;

@compute @workgroup_size(128, 1, 1)
fn lift_gather(@builtin(workgroup_id) group: vec3<u32>, @builtin(local_invocation_index) y: u32) {
  let tile = group.x;
  let mask = MaskPlane(lift.mask_at, lift.mask_width, lift.mask_height, lift.mask_stride);
  let row = (lift.first_row + walk_tile(tile, 4u) + y) * lift.mask_width;
  var took = false;
  for (var x = 0u; x < TILE_SIDE; x++) {
    let coverage = walk_coverage(mask, tile, x, y);
    let texel = walk_texel(tile, x, y);
    let alpha = texel >> 24u;
    if (coverage == 0u || alpha == 0u) {
      continue;
    }
    let kept = select(div255_round(alpha * coverage), alpha, lift.whole != 0u);
    lifted[row + walk_tile(tile, 3u) + x - lift.lifted_base] = (texel & 0xffffffu) | (kept << 24u);
    took = true;
  }
  if (took) {
    atomicOr(&lifted_any, 1u);
  }
}
