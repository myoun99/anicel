// Lays a picture over the frame an export makes (gpu-export-path ①⑵):
// the frame's last picture is made on the engine — its ground, the cut's
// picture cut at the canvas's edge, what is drawn over it, a track's units
// one over another and a fade thinning one as a whole — so what a writer
// takes is read back once. Each is this one pass: a source laid over the
// frame at a strength, under a cover where one is given.
//
// The source is a frame's rows (frame_shown.wgsl: premultiplied, RGBA or
// BGRA, `params.stride` words a row) or one colour. The frame laid onto is
// premultiplied RGBA, `params.onto_stride` words a row. Laid by the blend
// family's normal mode (blend.wgsl) — the composite's own source-over, one
// formula on the engine — on its 16-bit straight scale, and kept as bytes
// premultiplied between passes (premultiply.wgsl), which the conversions
// read.
//
// Needs shared/isqrt.wgsl and blend/blend.wgsl before it.

struct Params {
  // The source's words a row, as frame_shown.wgsl reads it.
  stride: u32,
  // The frame laid onto: its words a row, and a cover's bytes a row.
  onto_stride: u32,
  // The box laid: its top-left on the frame laid onto, its size, and the
  // source's pixel at that top-left.
  x0: u32,
  y0: u32,
  width: u32,
  height: u32,
  sx: u32,
  sy: u32,
  // The source's strength, a byte: 255 lays it as it is.
  opacity: u32,
  // 1: `colour` everywhere — straight, red the low byte — in place of the
  // source's rows.
  solid: u32,
  colour: u32,
  // 1: `cover` holds a byte a pixel of the frame laid onto, four a word,
  // the low byte first — how much of the source each pixel takes.
  covered: u32,
  pad0: u32,
  pad1: u32,
  pad2: u32,
  pad3: u32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(2) var<storage, read_write> onto: array<u32>;
@group(0) @binding(3) var<storage, read> cover: array<u32>;

// A premultiplied word on the blend family's scale: straight, 16 bits a
// channel. No alpha is no colour.
fn widened(word: u32) -> vec4<u32> {
  let alpha = word >> 24u;
  if (alpha == 0u) {
    return vec4<u32>(0u);
  }
  return vec4<u32>(
    min(blend_div(word & 0xffu, alpha), W_ONE),
    min(blend_div((word >> 8u) & 0xffu, alpha), W_ONE),
    min(blend_div((word >> 16u) & 0xffu, alpha), W_ONE),
    alpha * 257u,
  );
}

// A straight 16-bit pixel back as the premultiplied word the frame keeps.
fn narrowed(pixel: vec4<u32>) -> u32 {
  return premultiply8(
    blend_to8(pixel.x) | (blend_to8(pixel.y) << 8u) | (blend_to8(pixel.z) << 16u)
      | (blend_to8(pixel.w) << 24u),
  );
}

// The cover's byte at the frame's pixel `index`.
fn covering(index: u32) -> u32 {
  return (cover[index / 4u] >> (index % 4u * 8u)) & 0xffu;
}

@compute @workgroup_size(64)
fn lay_pass(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= params.width || id.y >= params.height) {
    return;
  }
  let x = params.x0 + id.x;
  let y = params.y0 + id.y;
  let at = y * params.onto_stride + x;
  var word = premultiply8(params.colour);
  if (params.solid == 0u) {
    word = frame_premultiplied(params.sx + id.x, params.sy + id.y);
  }
  let source = widened(word);
  var strength = blend_cover(source.w, params.opacity);
  if (params.covered == 1u) {
    strength = blend_cover(strength, covering(at));
  }
  // What takes none of the source is not written: the blend would give it
  // back as it lies (a premultiplied word made straight and premultiplied
  // again is itself — the mutant without this return lives, 🔬2026-11-11).
  if (strength == 0u) {
    return;
  }
  let laid = blend_composite(BLEND_NORMAL, vec4<u32>(source.xyz, strength), widened(onto[at]));
  onto[at] = narrowed(laid);
}
