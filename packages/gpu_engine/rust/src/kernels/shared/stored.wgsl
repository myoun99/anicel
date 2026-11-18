// A tile stored on a page lies in a slot of it — the pool's, and every
// page a pass reads tiles off by the same law: a stroke's view, a stamp's,
// a plate of letters, a gathered one — and a pixel of it is read here and
// nowhere else.
//
// 🚨ONE READ OF A STORED TILE (F-610, 2026-11-19 — 🗣️유저, F-610-Q5:
// 「압축은 … 결국은 3번대로 하자」, the tiles kept folded): how a tile's
// words lie in its slot is this function's to know, so the form they are
// stored in changes in one place. ↩️Till then each of the three passes
// that read a stored tile — the composite's rows, the walk over a cel's
// pixels and the write path's test — spelled where a slot's words lie for
// itself. `one_stored_read.rs` keeps it the one.
//
// Needs shared/tile.wgsl and shared/pages.wgsl (with its bindings) before
// it: `Pages::stored` gives the two together.

// The word of the pixel at `texel` — its place in its tile (tile.wgsl's
// `tile_texel`) — of the tile in slot `slot` of the page this pass bound
// as its k-th; 0 for a k that is no page's, as `page_word` reads NO_PAGE.
fn stored_word(k: u32, slot: u32, texel: u32) -> u32 {
  return page_word(k, slot * TILE_TEXELS + texel);
}
