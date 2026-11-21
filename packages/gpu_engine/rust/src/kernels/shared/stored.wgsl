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

// What the word read next is: a pixel's own — a tile as it is, a block as
// it is, a palette's colour —, a folded tile's table entry, or the word a
// pixel's index among a palette's colours is packed in.
const STORED_PIXEL: u32 = 0u;
const STORED_ENTRY: u32 = 1u;
const STORED_PACKED: u32 = 2u;

// The word of the pixel at `texel` — its place in its tile (tile.wgsl's
// `tile_texel`) — of the tile in slot `slot` of the page this pass bound
// as its k-th; 0 for a k that is no page's, as `page_word` reads NO_PAGE.
//
// 🚨THE PAGE IS READ AT ONE SITE, in a loop (F-610, 2026-11-21): where
// the next word lies is worked out first, and the one call reads it.
// `page_word` is a switch with a case for each page a pass binds —
// sixteen at the most (pages.rs's `MOST_PAGES`) — and a device's compiler
// lays that switch out again at every call of it. ↩️Read at five sites —
// one a branch, as this was written on 2026-11-19 — the composite, which
// reads a stored tile at seven places of its own, took two and a half
// times as long to compile as it had before tiles were kept folded: the
// wait window of a new build's first run stood 4.6 to 5.05 s on the
// Surface where it had stood 2.76 to 3.02 (검증 2026-11-20; 저장 found
// the commit the day after, card
// the-wait-window-stands-seven-seconds-on-the-surface).
//
// 🔬The composite's one full pass, DXC, a release build, main PC with
// every core busy, each shape nine times turn about (the middle one): 21.6
// s read at five sites, 8.6 as it was before the fold, 8.9 so; 14.1 at
// three sites with no loop, and 9.4 in a loop of three turns counted — a
// loop that ends by what it read is the one no compiler can lay out
// three times. What the GPU takes to read a folded tile did not move
// within what that machine can tell (kernels/fold/cost.rs: a folded
// read against the same read as it is, 0.90 to 1.13 times for every
// shape) — ⏳a tablet's has not been asked. The words read and the
// pixel answered are the same. `one_stored_read.rs` keeps it the one
// site.
fn stored_word(k: u32, slot: u32, texel: u32) -> u32 {
  var index = slot * TILE_TEXELS + texel;
  var reads = STORED_PIXEL;
  var first = 0u;
  var pixel = 0u;
  if ((slot & STORED_FOLDED) != 0u) {
    first = (slot ^ STORED_FOLDED) * FOLD_GRANULE;
    let x = texel % TILE_SIDE;
    let y = texel / TILE_SIDE;
    index = first + (y / FOLD_BLOCK) * FOLD_ACROSS + x / FOLD_BLOCK;
    pixel = (y % FOLD_BLOCK) * FOLD_BLOCK + x % FOLD_BLOCK;
    reads = STORED_ENTRY;
  }
  var at = 0u;
  var bits = 0u;
  var word = 0u;
  // It ends by what it read, in three turns at most: a table's entry leads
  // to a pixel's own word or to the word its index is packed in, that word
  // to a pixel's own, and a pixel's own ends it.
  loop {
    word = page_word(k, index);
    if (reads == STORED_PIXEL) {
      break;
    }
    if (reads == STORED_ENTRY) {
      if (fold_is_colour(word)) {
        break;
      }
      at = first + (word & FOLD_AT);
      let form = (word >> FOLD_FORM_SHIFT) & FOLD_FORM;
      if (form == FOLD_AS_IT_IS) {
        index = at + pixel;
        reads = STORED_PIXEL;
      } else {
        bits = fold_index_bits(form);
        let colours = ((word >> FOLD_COUNT_SHIFT) & FOLD_COUNT) + 1u;
        index = at + colours + ((pixel * bits) >> 5u);
        reads = STORED_PACKED;
      }
    } else {
      index = at + ((word >> ((pixel * bits) & 31u)) & ((1u << bits) - 1u));
      reads = STORED_PIXEL;
    }
  }
  return word;
}
