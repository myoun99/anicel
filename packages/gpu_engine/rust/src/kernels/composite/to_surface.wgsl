// The composite's pixels on a surface Flutter shows: each at its own (x, y),
// premultiplied as Flutter reads it (premultiply.wgsl). Outside the output's
// pixels the surface is left as it was — an atlas's other panels.

@group(0) @binding(__BINDING__) var surface: texture_storage_2d<__FORMAT__, write>;

fn put(tile: u32, texel: u32, x: i32, y: i32, inside: bool, word: u32) {
  if (inside) {
    textureStore(surface, vec2<i32>(x, y), unpack4x8unorm(premultiply8(word)));
  }
}
