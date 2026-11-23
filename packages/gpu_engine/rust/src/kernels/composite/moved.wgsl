// A surface's texels moved by whole pixels (moved.rs has why): a band of
// them copied out of the surface as it stores them, each stored back where
// the move puts it.

struct Moved {
  // The surface's texels this dispatch stores: from (left, top), so many
  // across and down.
  left: u32,
  top: u32,
  columns: u32,
  rows: u32,
  // The words a row of the band takes in the copy: its bytes a row, a
  // multiple of the copy's alignment, over four.
  stride: u32,
}

@group(0) @binding(0) var<storage, read> moved: Moved;
@group(0) @binding(1) var<storage, read> copied: array<u32>;
@group(0) @binding(2) var surface: texture_storage_2d<__FORMAT__, write>;

// A word of the copy as the texel a store takes: its bytes lie in the
// surface's own order, the format's — red first, or blue. The one float
// step, and why it cannot move a byte: fill.wgsl's.
fn texel_of_rgba8unorm(word: u32) -> vec4<f32> {
  return unpack4x8unorm(word);
}

fn texel_of_bgra8unorm(word: u32) -> vec4<f32> {
  return unpack4x8unorm(word).zyxw;
}

@compute @workgroup_size(8, 8, 1)
fn moved_store(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x >= moved.columns || id.y >= moved.rows) {
    return;
  }
  let word = copied[id.y * moved.stride + id.x];
  textureStore(surface, vec2<u32>(moved.left + id.x, moved.top + id.y), texel_of___FORMAT__(word));
}
