// A mask's byte at a pixel of its box, in the layout mask.wgsl's head
// gives: four to a word, the leftmost in the low byte, a row `stride`
// words; 0 past the box, where a pixel before it wraps past either side.
// ⛔ONE READING: the finishing passes and the cel pixel pass each spelled
// it, and the lift came as a third to read a selection (11-06, rule of
// three).
//
// Its host defines `mask_word(at)`, the word `at` of what holds the plane.

// Where a host holds a plane: the word its first row starts at, its box's
// pixels across, the rows of it there, and a row's words.
struct MaskPlane {
  at: u32,
  width: u32,
  height: u32,
  stride: u32,
}

fn mask_byte_of(plane: MaskPlane, x: u32, y: u32) -> u32 {
  if (x >= plane.width || y >= plane.height) {
    return 0u;
  }
  let word = mask_word(plane.at + y * plane.stride + x / 4u);
  return (word >> (x % 4u * 8u)) & 0xffu;
}
