// The Gaussian a way's three passes a dispatch, over strips in workgroup
// memory (three.wgsl): the way's first pass reads the tiles or the rows'
// plane by its edge, and its last puts the plane or the tiles.
//
// Needs gaussian.wgsl and three.wgsl before it.

// The way's three passes, box.wgsl's words, the first's first; then the
// lines and the run along a workgroup takes (gaussian.rs's `three`).
@group(0) @binding(3) var<uniform> three_words: array<vec4<u32>, 8>;

fn three_word(index: u32) -> u32 {
  return three_words[index / 4u][index % 4u];
}

fn blur_load(first: BoxPass, line: i32, p: i32) -> vec4<u32> {
  return gaussian_read(first, line, p);
}

fn blur_store(last: BoxPass, line: i32, p: i32, pixel: vec4<u32>) {
  gaussian_write(last, line, p, pixel);
}

@compute @workgroup_size(256)
fn box_three(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_index) lane: u32,
) {
  var passes: array<BoxPass, 3>;
  for (var k = 0u; k < 3u; k++) {
    var words: array<u32, 9>;
    for (var i = 0u; i < 9u; i++) {
      words[i] = three_word(k * 9u + i);
    }
    passes[k] = box_pass(words);
  }
  blur_way(passes, group.x, group.y, three_word(28u), three_word(27u), lane);
}
