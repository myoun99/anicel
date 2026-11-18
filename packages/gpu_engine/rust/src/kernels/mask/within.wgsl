// A mask cut by another: each pixel of a mask's box whole where it holds
// any of the pixel and the other mask does too, and nothing elsewhere — a
// fill's range as its mark shows it under a selection (the app's
// `FillRange.coveredWithin`): what the fill would write into, cut where
// the selection takes none of the pixel.
//
// The mask is a plane over its box, `width` × `height`, in mask.wgsl's
// layout; the other lies `dx`, `dy` pixels from it — the pixel (x, y) of
// the mask is (x + dx, y + dy) of the other's box, 0 past it.
//
// Needs byte.wgsl before it; defines its `mask_word`, the other's.

// The mask's box, where the other lies from it, and the other's box —
// byte.wgsl's `MaskPlane` laid flat, as a uniform's struct member would
// be padded to sixteen bytes.
struct Within {
  width: u32,
  height: u32,
  stride: u32,
  dx: i32,
  dy: i32,
  other_width: u32,
  other_height: u32,
  other_stride: u32,
}

@group(0) @binding(0) var<uniform> within: Within;
@group(0) @binding(1) var<storage, read> bytes_in: array<u32>;
@group(0) @binding(2) var<storage, read_write> bytes_out: array<u32>;
@group(0) @binding(3) var<storage, read> other_in: array<u32>;

fn mask_word(at: u32) -> u32 {
  return other_in[at];
}

@compute @workgroup_size(8, 8, 1)
fn mask_within(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= within.stride || id.y >= within.height) {
    return;
  }
  let other = MaskPlane(0u, within.other_width, within.other_height, within.other_stride);
  let at = id.y * within.stride + id.x;
  let word = bytes_in[at];
  var put = 0u;
  for (var k = 0u; k < 4u; k++) {
    let x = id.x * 4u + k;
    if (x >= within.width) {
      break;
    }
    // A negative place wraps past the other's box, which reads 0 there.
    let taken = mask_byte_of(other, u32(i32(x) + within.dx), u32(i32(id.y) + within.dy));
    if (((word >> (k * 8u)) & 0xffu) != 0u && taken != 0u) {
      put = put | (0xffu << (k * 8u));
    }
  }
  bytes_out[at] = put;
}
