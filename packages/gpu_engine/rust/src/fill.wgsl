// Stage 0's one compute pass: every texel is an integer function of
// (x, y, seed), so every device must write the same bytes.
//
// Integer ops only (gpu-engine-skeleton, user Q2 "same result on every
// device"): WGSL fixes u32 multiplication to wrap modulo 2^32 (§6.2.3)
// and shifts to take their amount modulo 32 (§8.10), while float ops may
// be fused or reassociated (§Reassociation and Fusion) with no switch in
// WGSL or wgpu to stop it. `pattern.rs` is the CPU side of the same
// formula, kept as the oracle the bytes are checked against.

struct Params {
  seed: u32,
  width: u32,
  height: u32,
  pad: u32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var canvas: texture_storage_2d<__FORMAT__, write>;

// lowbias32, from Chris Wellons' hash prospector.
fn mix32(v: u32) -> u32 {
  var h = v;
  h ^= h >> 16u;
  h *= 0x7feb352du;
  h ^= h >> 15u;
  h *= 0x846ca68bu;
  h ^= h >> 16u;
  return h;
}

@compute @workgroup_size(8, 8)
fn fill(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= params.width || id.y >= params.height) {
    return;
  }
  let packed = (mix32(id.x ^ mix32(id.y ^ mix32(params.seed))) & 0x00ffffffu)
      | 0xff000000u;
  // The one float step, and why it cannot move a byte: unpack gives k/255
  // for each byte k, and storing to an 8-bit unorm texel rounds f * 255 to
  // the nearest integer. The few-ULP error a backend may add to k/255 is
  // about 1e-5 of a step, so the stored byte is k on every device.
  textureStore(canvas, vec2<u32>(id.xy), unpack4x8unorm(packed));
}
