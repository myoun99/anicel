// The fold (F-610, 2026-11-19 — 🗣️유저, F-610-Q5: 「압축은 … 결국은 3번대로
// 하자. 결과가 제일 좋으니까」): a stored tile written folded, as
// stored.wgsl reads one — a table of a word for each of its 8 × 8 blocks
// and, after it, the words of the blocks that are not of one colour, each
// in the least of the forms: a palette of its colours under each pixel's
// index, or its 64 words as they are.
//
// A tile is a workgroup and a block a lane: a lane reads its block's 64
// pixels, counts their colours and says how many words the block takes;
// the lanes then meet (a barrier), and each writes its block where the
// blocks before it end. The last lane says how many words the tile folds
// to — past FOLD_MOST, it is no folded tile: its words here are no tile's,
// and it stays as it is.
//
// Folds any tile stored_word reads, a folded one too: the words it writes
// are the tile's alone, whatever they were read from.
//
// ⚠️Compiled with its workgroup memory left as the device hands it
// (`pipeline_unzeroed`): every lane writes its word of `fold_words` before
// the barrier, and none reads a word before it.
//
// Needs shared/tile.wgsl, shared/pages.wgsl (with its bindings) and
// shared/stored.wgsl before it.

// The most words a folded tile takes (fold/mod.rs's MOST_FOLDED_BYTES):
// half a tile's as it is.
const FOLD_MOST: u32 = 8192u;
// The colours past which a block of a palette under a byte a pixel takes
// no fewer words than as it is: its colours and 16 words of indices.
const FOLD_MOST_COLOURS: u32 = 47u;

// x: the pass's first tile among all the fold is given.
@group(0) @binding(0) var<uniform> folding: vec4<u32>;
// Each of the pass's tiles: the binding of its page among the pass's, and
// its slot.
@group(0) @binding(1) var<storage, read> given: array<u32>;
// The pass's tiles folded, FOLD_MOST words each.
@group(0) @binding(2) var<storage, read_write> folded: array<u32>;
// A word a tile: the words it folds to.
@group(0) @binding(3) var<storage, read_write> sizes: array<u32>;

// The words each block takes past the table, for the lanes after it.
var<workgroup> fold_words: array<u32, FOLD_TABLE>;

@compute @workgroup_size(256, 1, 1)
fn fold(
  @builtin(workgroup_id) group: vec3<u32>,
  @builtin(local_invocation_index) block: u32,
) {
  let tile = group.x;
  let k = given[tile * 2u];
  let slot = given[tile * 2u + 1u];
  let left = (block % FOLD_ACROSS) * FOLD_BLOCK;
  let top = (block / FOLD_ACROSS) * FOLD_BLOCK;
  // The block's colours in the order they come, and each pixel's among
  // them.
  var colours: array<u32, FOLD_PIXELS>;
  var index: array<u32, FOLD_PIXELS>;
  var count = 0u;
  for (var pixel = 0u; pixel < FOLD_PIXELS; pixel++) {
    let texel = (top + pixel / FOLD_BLOCK) * TILE_SIDE + left + pixel % FOLD_BLOCK;
    let word = stored_word(k, slot, texel);
    var at = 0u;
    while (at < count && colours[at] != word) {
      at++;
    }
    if (at == count) {
      colours[count] = word;
      count++;
    }
    index[pixel] = at;
  }
  // The least form: none where the table's word is the block — one
  // colour, and one a table's word can be (stored.wgsl) —, else a palette
  // under indices of as few bits as count its colours, else as it is.
  var form = FOLD_AS_IT_IS;
  var words = FOLD_PIXELS;
  let one = count == 1u && fold_is_colour(colours[0]);
  if (one) {
    words = 0u;
  } else if (count <= 2u) {
    form = 1u;
  } else if (count <= 4u) {
    form = 2u;
  } else if (count <= 16u) {
    form = 3u;
  } else if (count <= FOLD_MOST_COLOURS) {
    form = 4u;
  }
  let bits = fold_index_bits(form);
  if (form != FOLD_AS_IT_IS) {
    words = count + FOLD_PIXELS * bits / 32u;
  }
  fold_words[block] = words;
  workgroupBarrier();
  var at = FOLD_TABLE;
  for (var before = 0u; before < block; before++) {
    at += fold_words[before];
  }
  if (block == FOLD_TABLE - 1u) {
    sizes[folding.x + tile] = at + words;
  }
  let out = tile * FOLD_MOST;
  if (one) {
    folded[out + block] = colours[0];
    return;
  }
  // Past the most a folded tile takes, the tile is none: nothing of the
  // block is written past its tile's words.
  if (at + words > FOLD_MOST) {
    return;
  }
  if (form == FOLD_AS_IT_IS) {
    folded[out + block] = at;
    for (var pixel = 0u; pixel < FOLD_PIXELS; pixel++) {
      folded[out + at + pixel] = colours[index[pixel]];
    }
    return;
  }
  folded[out + block] = at | (form << FOLD_FORM_SHIFT) | ((count - 1u) << FOLD_COUNT_SHIFT);
  for (var colour = 0u; colour < count; colour++) {
    folded[out + at + colour] = colours[colour];
  }
  let a_word = 32u / bits;
  for (var word = 0u; word < FOLD_PIXELS / a_word; word++) {
    var packed = 0u;
    for (var pixel = 0u; pixel < a_word; pixel++) {
      packed |= index[word * a_word + pixel] << (pixel * bits);
    }
    folded[out + at + count + word] = packed;
  }
}
