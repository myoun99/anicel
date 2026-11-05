// The blur brush's picture and the cel (I-75 흐리기 — BrushBlurPicture's
// rewritten tiles and its resultTile, C's qa_blur_result_tile; 캔버스
// 베이스 11-06 02:29). `blur_fill` makes a stroke tile's picture of the
// cel's tile as the executor copies a row whole over nothing — its stored
// bytes, straight RGBA8, tile after tile in the stroke's order
// (composite's `Composited.out`) — premultiplied. `blur_finish` stores the
// picture back the same way, tile after tile in the stroke's order.
//
// Where the picture is still the cel's, that is the cel's own bytes: the
// copy holds no colour behind no alpha (blend_pack8), and any other stored
// pixel comes back from its premultiplied form — 255p / 257a lies within
// 127.5 / 257a < ½ of c — so no pixel needs keeping as C keeps the cel's
// there, for the colour a cel read straight from its tile may hold behind
// no alpha.
//
// ⏳The selection and the tool's opacity, which cap how far a finished
// pixel moves from the cel (resultTile's mask), come with a paint stroke's
// (R28), and the cel's copy with them: until then a finished tile is the
// picture all the way.
//
// Needs blend.wgsl, tile.wgsl and the pages (pages.rs's `source`) before
// it.

// The cel's tiles as the copy put them, or the finished tiles; and where
// each of those tiles is kept in the picture — the binding of its page, its
// slot. The picture is the stroke's planes on their pages, from binding 2:
// two words a pixel, a tile a slot of a page.
@group(0) @binding(0) var<storage, read_write> blur_cel: array<u32>;
@group(0) @binding(1) var<storage, read> blur_slots: array<u32>;

const BLUR_CEL_GROUP: u32 = 256u;

// Workgroup (x, y) takes tile y, its texels from 256x on: the texel's word
// among the tiles.
fn blur_cel_word(group: vec3<u32>, lane: u32) -> u32 {
  return group.y * TILE_TEXELS + group.x * BLUR_CEL_GROUP + lane;
}

// The binding of tile y's page.
fn blur_cel_page(group: vec3<u32>) -> u32 {
  return blur_slots[group.y * 2u];
}

// The first of the two words of that texel on its page.
fn blur_cel_plane(group: vec3<u32>, lane: u32) -> u32 {
  let texel = group.x * BLUR_CEL_GROUP + lane;
  return (blur_slots[group.y * 2u + 1u] * TILE_TEXELS + texel) * 2u;
}

@compute @workgroup_size(256)
fn blur_fill(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_index) lane: u32,
) {
  let pair = blend_pack16(blend_unpack8_premultiplied(blur_cel[blur_cel_word(group, lane)]));
  let k = blur_cel_page(group);
  let at = blur_cel_plane(group, lane);
  page_put(k, at, pair.x);
  page_put(k, at + 1u, pair.y);
}

@compute @workgroup_size(256)
fn blur_finish(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_index) lane: u32,
) {
  let k = blur_cel_page(group);
  let at = blur_cel_plane(group, lane);
  let own = blend_unpack16(vec2<u32>(page_word(k, at), page_word(k, at + 1u)));
  blur_cel[blur_cel_word(group, lane)] = blend_pack8_premultiplied(own);
}
