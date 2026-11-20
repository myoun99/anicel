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
// A SLOT HOLDS A TILE AS IT IS OR FOLDED, and its number says which
// (STORED_FOLDED):
//
// - As it is: 16384 words, a pixel each, from word slot × 16384 of the
//   page.
// - Folded (fold.wgsl writes it): from granule (slot without the bit) of
//   the page, FOLD_GRANULE words a granule, a table of a word for each of
//   the tile's 8 × 8 blocks, 16 a row, and after it the words of the
//   blocks that are not of one colour. A table's word that is a colour —
//   some alpha, or nothing at all (`fold_is_colour`) — is its block's
//   every pixel. One with no alpha that is not nothing says where the
//   block's words lie, counted from the tile's first (FOLD_AT), and in
//   what form (FOLD_FORM): as they are, 64 words; or a palette — its
//   colours (FOLD_COUNT, one fewer) and after them each pixel's index
//   among them, 1, 2, 4 or 8 bits a pixel, the first pixel in a word's
//   low bits. A pixel is read in three words at most.
//
// 🔬WHY THESE FORMS (2026-11-19, a copy of the user's line art and S5_BA
// cut 352 with every row shown, each tile counted in whole words): a
// block of one colour alone folds line art's cels 3.7× and painted ones
// 1.6×; with palettes 6.6× and 3.6× (slots a power of two). One ink under
// a plane of its alphas was counted too and is not here: 0–5% of the
// blocks, 0–2% of the bytes.
//
// Needs shared/tile.wgsl and shared/pages.wgsl (with its bindings) before
// it: `Pages::stored` gives the two together.

// The bit of a slot's number that says its tile is folded (pool/mod.rs's
// `FOLDED`): no page of tiles as they are has so many slots.
const STORED_FOLDED: u32 = 0x8000u;
// The words of a granule: what a folded tile's place on its page is
// counted in, and the words of its table.
const FOLD_GRANULE: u32 = 256u;
const FOLD_TABLE: u32 = 256u;
// A block's side, its pixels, and the blocks across a tile.
const FOLD_BLOCK: u32 = 8u;
const FOLD_PIXELS: u32 = 64u;
const FOLD_ACROSS: u32 = 16u;
// A table's word that is no colour: where its block's words lie, the
// block's form, and its colours less one.
const FOLD_AT: u32 = 0x3fffu;
const FOLD_FORM_SHIFT: u32 = 14u;
const FOLD_FORM: u32 = 7u;
const FOLD_COUNT_SHIFT: u32 = 17u;
const FOLD_COUNT: u32 = 63u;
// The form of a block as it is; a palette's is 1 to 4, by the bits of its
// indices (`fold_index_bits`).
const FOLD_AS_IT_IS: u32 = 0u;

// Whether a table's word is its block's colour: one with some alpha, or
// nothing at all. A colour of no alpha that is not nothing is a palette
// of one.
fn fold_is_colour(word: u32) -> bool {
  return (word >> 24u) != 0u || word == 0u;
}

// The bits of a pixel's index in a palette of form `form`: 1, 2, 4, 8.
fn fold_index_bits(form: u32) -> u32 {
  return (1u << form) >> 1u;
}

// The word of the pixel at `texel` — its place in its tile (tile.wgsl's
// `tile_texel`) — of the tile in slot `slot` of the page this pass bound
// as its k-th; 0 for a k that is no page's, as `page_word` reads NO_PAGE.
fn stored_word(k: u32, slot: u32, texel: u32) -> u32 {
  if ((slot & STORED_FOLDED) == 0u) {
    return page_word(k, slot * TILE_TEXELS + texel);
  }
  let first = (slot ^ STORED_FOLDED) * FOLD_GRANULE;
  let x = texel % TILE_SIDE;
  let y = texel / TILE_SIDE;
  let entry = page_word(k, first + (y / FOLD_BLOCK) * FOLD_ACROSS + x / FOLD_BLOCK);
  if (fold_is_colour(entry)) {
    return entry;
  }
  let at = first + (entry & FOLD_AT);
  let pixel = (y % FOLD_BLOCK) * FOLD_BLOCK + x % FOLD_BLOCK;
  let form = (entry >> FOLD_FORM_SHIFT) & FOLD_FORM;
  if (form == FOLD_AS_IT_IS) {
    return page_word(k, at + pixel);
  }
  let colours = ((entry >> FOLD_COUNT_SHIFT) & FOLD_COUNT) + 1u;
  let bits = fold_index_bits(form);
  let bit = pixel * bits;
  let packed = page_word(k, at + colours + (bit >> 5u));
  return page_word(k, at + ((packed >> (bit & 31u)) & ((1u << bits) - 1u)));
}
