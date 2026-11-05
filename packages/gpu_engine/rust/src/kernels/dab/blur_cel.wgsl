// The blur brush's picture and the cel (I-75 흐리기 — BrushBlurPicture's
// rewritten tiles and its resultTile, C's qa_blur_result_tile; 캔버스
// 베이스 11-06 02:29). `blur_fill` makes a stroke tile's picture of the
// cel's tile as the executor copies a row whole over nothing — its stored
// bytes, straight RGBA8, tile after tile in the stroke's order
// (composite's `Composited.out`) — premultiplied. `blur_finish` takes the
// same copy and moves each pixel of it toward the picture by the cover,
// in place, stored the same way.
//
// The cover is the tool's opacity under the selection's byte at the pixel
// (blend_cover, 255 where no selection covers the stroke) — resultTile's
// mask, as a paint stroke's row is laid (R28, gpu-canonical-store 11-06
// 06:51). The move is the blur dab's own (blend_toward4) on the
// premultiplied 16-bit scale: at a whole cover the picture, at none the
// cel.
//
// Where the picture is still the cel's, or the cover is none, that is the
// cel's own bytes: the copy holds no colour behind no alpha (blend_pack8),
// and any other stored pixel comes back from its premultiplied form —
// 255p / 257a lies within 127.5 / 257a < ½ of c — so no pixel needs
// keeping as C keeps the cel's there, for the colour a cel read straight
// from its tile may hold behind no alpha.
//
// Needs blend.wgsl, tile.wgsl, the pages (pages.rs's `source`) and
// mask/byte.wgsl before it; defines byte.wgsl's `mask_word`.

// The cel's tiles as the copy put them, finished in place; and what a pass
// is given (shared/paged.rs's `given`): the cover — the opacity, whether a
// selection covers the stroke, and the rows of its mask the pass's tiles
// lie on: where they start here, its box's pixels across, the rows here, a
// row's words and the canvas pixel the first starts at — then each tile's
// place in the picture, the binding of its page and its slot, and its
// column and row, then those rows of the mask. The picture is the
// stroke's planes on their pages, from binding 2: two words a pixel, a
// tile a slot of a page.
@group(0) @binding(0) var<storage, read_write> blur_cel: array<u32>;
@group(0) @binding(1) var<storage, read> blur_given: array<u32>;

const BLUR_CEL_GROUP: u32 = 256u;
const BLUR_COVER_WORDS: u32 = 8u;
const BLUR_TILE_WORDS: u32 = 4u;

fn mask_word(at: u32) -> u32 {
  return blur_given[at];
}

// Workgroup (x, y) takes tile y, its texels from 256x on: the texel's word
// among the tiles.
fn blur_cel_word(group: vec3<u32>, lane: u32) -> u32 {
  return group.y * TILE_TEXELS + group.x * BLUR_CEL_GROUP + lane;
}

// Word `word` of tile y's place.
fn blur_cel_tile(group: vec3<u32>, word: u32) -> u32 {
  return blur_given[BLUR_COVER_WORDS + group.y * BLUR_TILE_WORDS + word];
}

// The first of the two words of that texel on its page.
fn blur_cel_plane(group: vec3<u32>, lane: u32) -> u32 {
  let texel = group.x * BLUR_CEL_GROUP + lane;
  return (blur_cel_tile(group, 1u) * TILE_TEXELS + texel) * 2u;
}

// The cover at that texel: the opacity under the selection's byte there,
// or under 255 where none covers the stroke.
fn blur_cel_cover(group: vec3<u32>, lane: u32) -> u32 {
  if (blur_given[1] == 0u) {
    return blend_cover(blur_given[0], 255u);
  }
  let texel = group.x * BLUR_CEL_GROUP + lane;
  let x = bitcast<i32>(blur_cel_tile(group, 2u)) * i32(TILE_SIDE) + i32(texel % TILE_SIDE);
  let y = bitcast<i32>(blur_cel_tile(group, 3u)) * i32(TILE_SIDE) + i32(texel / TILE_SIDE);
  let mask = MaskPlane(blur_given[2], blur_given[3], blur_given[4], blur_given[5]);
  let left = bitcast<i32>(blur_given[6]);
  let top = bitcast<i32>(blur_given[7]);
  return blend_cover(blur_given[0], mask_byte_of(mask, u32(x - left), u32(y - top)));
}

@compute @workgroup_size(256)
fn blur_fill(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_index) lane: u32,
) {
  let pair = blend_pack16(blend_unpack8_premultiplied(blur_cel[blur_cel_word(group, lane)]));
  let k = blur_cel_tile(group, 0u);
  let at = blur_cel_plane(group, lane);
  page_put(k, at, pair.x);
  page_put(k, at + 1u, pair.y);
}

@compute @workgroup_size(256)
fn blur_finish(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_index) lane: u32,
) {
  let k = blur_cel_tile(group, 0u);
  let at = blur_cel_plane(group, lane);
  let own = blend_unpack16(vec2<u32>(page_word(k, at), page_word(k, at + 1u)));
  let word = blur_cel_word(group, lane);
  let cel = blend_unpack8_premultiplied(blur_cel[word]);
  let cover = blur_cel_cover(group, lane);
  blur_cel[word] = blend_pack8_premultiplied(blend_toward4(cel, own, cover));
}
