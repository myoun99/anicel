//! The fold on a real GPU: a tile folded is read word for word as it was,
//! by every pass that reads a stored tile; it takes the words its blocks'
//! colours say, and none past its own where it folds to more than a
//! folded tile takes; and a pass cut smaller folds the same.
//!
//! ⛔NO SECOND SPELLING OF THE FORM HERE: what a folded tile holds is read
//! through the passes that read a stored tile — the write path's test is
//! the one that tells a word from another — and never unfolded on the
//! CPU. What the tests know of the form is how many words a block takes.

use std::sync::OnceLock;

use super::{Fold, Folded, MOST_FOLDED_BYTES};
use crate::device::Engine;
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::cel_pixel::ink::Ink;
use crate::kernels::composite::tests::{Rig, mix, rig, row, with_map};
use crate::kernels::composite::{
    FOLDED, GRANULE_BYTES, NO_EDGE, Plan, Step, TILE, TILE_BYTES, TILE_TEXELS, TileAt, TileSet,
    WHOLE,
};
use crate::kernels::shared::{ResampleMap, ResampleMode, plane, words_buffer};
use crate::kernels::write::{Change, Write};
use crate::testing::read_buffer;

/// The passes the tests read a stored tile through, beside the
/// composite's ([`rig`]), and the fold.
pub(super) struct Kernels {
    pub(super) fold: Fold,
    write: Write,
    ink: Ink,
}

pub(super) fn kernels() -> &'static Kernels {
    static KERNELS: OnceLock<Kernels> = OnceLock::new();
    KERNELS.get_or_init(|| {
        let engine = rig().engine;
        Kernels {
            fold: Fold::new(engine).expect("compile the fold"),
            write: Write::new(engine).expect("compile the write path's test"),
            ink: Ink::new(engine).expect("compile the ink scan"),
        }
    })
}

/// The blocks of a tile, and the pixels of a block.
const BLOCKS: u32 = 256;
const PIXELS: u32 = 64;

/// The `index`-th colour of block `block` of a tile of `seed`: unlike the
/// block's every other, of some alpha — but its second nothing in a block
/// in three and its third of no alpha, yet not nothing, in another: a
/// palette holds either as any colour.
fn colour(seed: u32, block: u32, index: u32) -> u32 {
    match (block % 3, index) {
        (0, 1) => 0,
        (1, 2) => block + 1,
        _ => (1 + (block * 7 + index * 13) % 255) << 24 | (seed & 0xff) << 16 | block << 6 | index,
    }
}

/// A tile whose block `block` holds `counts(block)` colours of its own
/// ([`colour`]): each once in its first pixels, then as they fall.
pub(super) fn tile_of(seed: u32, counts: impl Fn(u32) -> u32) -> Vec<u32> {
    let mut words = vec![0; TILE_TEXELS as usize];
    for block in 0..BLOCKS {
        let count = counts(block);
        for pixel in 0..PIXELS {
            let index = match pixel < count {
                true => pixel,
                false => mix(seed ^ block << 6 ^ pixel) % count,
            };
            let (x, y) = ((block % 16) * 8 + pixel % 8, (block / 16) * 8 + pixel / 8);
            words[(y * TILE + x) as usize] = colour(seed, block, index);
        }
    }
    words
}

/// The words a block of `count` colours takes past the table, the first
/// of them `first`: none where the table's word is the block, a palette's
/// colours and its indices — 1, 2, 4 or 8 bits a pixel —, or its 64 words.
fn block_words(count: u32, first: u32) -> u32 {
    let a_table_s_word = first >> 24 != 0 || first == 0;
    match count {
        1 if a_table_s_word => 0,
        1..=2 => count + 2,
        3..=4 => count + 4,
        5..=16 => count + 8,
        17..=47 => count + 16,
        _ => 64,
    }
}

/// The words [`tile_of`]'s tile of `counts` folds to: its table and its
/// blocks'.
fn tile_words(counts: impl Fn(u32) -> u32) -> u32 {
    BLOCKS + (0..BLOCKS).map(|block| block_words(counts(block), colour(0, block, 0))).sum::<u32>()
}

/// Every count of colours at which a block's form changes, and the ends.
const COUNTS: [u32; 10] = [1, 2, 3, 4, 5, 16, 17, 47, 48, 64];

fn every_count(block: u32) -> u32 {
    COUNTS[block as usize % COUNTS.len()]
}

/// The most blocks a folded tile holds as they are: its table and these
/// are [`MOST_FOLDED_BYTES`].
const MOST_AS_THEY_ARE: u32 = 124;

fn as_they_are(blocks: u32) -> impl Fn(u32) -> u32 {
    move |block| if block < blocks { PIXELS } else { 1 }
}

/// Nothing but two pixels of ink in one block and one in another.
fn sparse() -> Vec<u32> {
    let mut words = vec![0; TILE_TEXELS as usize];
    for (x, y, word) in [(70, 33, 0xff10_2030), (71, 38, 0x8040_5060), (101, 90, 0x0100_00ff)] {
        words[y * TILE as usize + x] = word;
    }
    words
}

fn flat(word: u32) -> Vec<u32> {
    vec![word; TILE_TEXELS as usize]
}

/// Tiles on pages as the tests read them: each as it is on the first
/// page, a slot each in order, and a second page for them folded.
pub(super) struct Stored {
    pub(super) pages: Vec<wgpu::Buffer>,
    pub(super) as_they_are: Vec<TileAt>,
}

pub(super) fn page(engine: &Engine, label: &str, bytes: u64) -> wgpu::Buffer {
    engine.device().create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: bytes,
        usage: PAGE,
        mapped_at_creation: false,
    })
}

/// What a page of the pool is: a pass's storage, a copy's source and its
/// destination.
const PAGE: wgpu::BufferUsages = wgpu::BufferUsages::STORAGE
    .union(wgpu::BufferUsages::COPY_SRC)
    .union(wgpu::BufferUsages::COPY_DST);

fn stored(tiles: &[Vec<u32>]) -> Stored {
    let engine = rig().engine;
    let as_they_are = words_buffer(engine, "tiles as they are", &tiles.concat(), PAGE);
    let folded = page(engine, "tiles folded", tiles.len() as u64 * MOST_FOLDED_BYTES);
    Stored {
        pages: vec![as_they_are, folded],
        as_they_are: (0..tiles.len() as u16).map(|slot| TileAt { page: 0, slot }).collect(),
    }
}

/// Puts each of `folded`'s tiles that folds on page `page`, one after
/// another from its first granule, and says where each is — none for a
/// tile that stays as it is.
pub(super) fn placed(pages: &[wgpu::Buffer], folded: &Folded, page: u16) -> Vec<Option<TileAt>> {
    let mut granule = 0;
    let places: Vec<Option<TileAt>> = (0..folded.sizes.len())
        .map(|index| {
            let granules = folded.granules(index)?;
            let at = TileAt { page, slot: FOLDED | granule };
            granule += granules;
            Some(at)
        })
        .collect();
    let writes: Vec<(usize, TileAt)> =
        places.iter().enumerate().filter_map(|(index, at)| Some((index, (*at)?))).collect();
    folded.put(rig().engine, pages, &writes).expect("put the folded tiles");
    places
}

/// `tiles` stored, folded and put: the pages, where each is as it is and
/// where folded.
fn folded(tiles: &[Vec<u32>]) -> (Stored, Folded, Vec<TileAt>) {
    let stored = stored(tiles);
    let folded =
        kernels().fold.folded(rig().engine, &stored.pages, &stored.as_they_are).expect("fold");
    let places = placed(&stored.pages, &folded, 1);
    let places = places.into_iter().map(|at| at.expect("the tile folds")).collect();
    (stored, folded, places)
}

/// What the write path's test says of `tiles` beside what is stored at
/// `places`: `Same` where every word is the stored one's.
fn beside(pages: &[wgpu::Buffer], tiles: &[Vec<u32>], places: &[TileAt]) -> Vec<Change> {
    let engine = rig().engine;
    let put = words_buffer(engine, "tiles put", &tiles.concat(), wgpu::BufferUsages::STORAGE);
    let places: Vec<Option<TileAt>> = places.iter().copied().map(Some).collect();
    kernels().write.changed(engine, pages, &put, &places).expect("the write path's test")
}

/// A row of the tiles at `places`, a column each, laid by `step`.
fn laid(pages: &[wgpu::Buffer], places: &[TileAt], step: Step) -> Vec<u8> {
    let Rig { engine, composite } = rig();
    let sets = [a_row(places)];
    let tiles: Vec<(i32, i32)> = (0..places.len() as i32).map(|column| (column, 0)).collect();
    let steps = [step];
    let plan = Plan {
        pages,
        sets: &sets,
        keys: &[],
        matrices: &[],
        chains: &[],
        steps: &steps,
        mask: None,
        stamps: None,
    };
    let done = composite.run(engine, &plan, &tiles, NO_EDGE, composite.widest()).expect("composite");
    read_buffer(engine, &done.out)
}

fn a_row(places: &[TileAt]) -> TileSet {
    TileSet {
        x0: 0,
        y0: 0,
        columns: places.len() as u32,
        rows: 1,
        tiles: places.iter().copied().map(Some).collect(),
    }
}

/// The tiles the tests fold: nothing, one colour, one of no alpha that is
/// not nothing — a table's word cannot be it —, a little ink, every count
/// of colours a form begins and ends at, and the most blocks as they are
/// a folded tile holds.
fn tiles() -> Vec<Vec<u32>> {
    vec![
        flat(0),
        flat(0x80aa_bbcc),
        flat(0x0012_3456),
        sparse(),
        tile_of(1, every_count),
        tile_of(2, as_they_are(MOST_AS_THEY_ARE)),
    ]
}

// A folded tile holds every word it held: the write path's test, which
// tells one word unlike the stored one, says each tile is the one stored —
// and says so of none with one word changed.
#[test]
fn a_tile_folded_is_read_word_for_word_as_it_was() {
    let tiles = tiles();
    let (stored, _, places) = folded(&tiles);
    assert!(places.iter().all(|at| at.folded().is_some()));
    assert_eq!(beside(&stored.pages, &tiles, &places), vec![Change::Same; tiles.len()]);
    // One word of each unlike it, a pixel of each of the first ten blocks:
    // in the tile of every count they are a block of one colour, a palette
    // of each width at its least and its most colours, and one as it is.
    for (block, pixel) in (0..).zip([0, 9, 3, 1, 60, 17, 33, 5, 7, 63]) {
        let texel = (pixel / 8) * TILE + block * 8 + pixel % 8;
        let mut changed = tiles.clone();
        for tile in &mut changed {
            tile[texel as usize] ^= 0x0100_0001;
        }
        let said = beside(&stored.pages, &changed, &places);
        assert!(said.iter().all(|&change| change != Change::Same), "block {block}: {said:?}");
    }
}

// A folded tile takes its table and what its blocks' colours say: nothing
// more for a block of one colour, a palette's colours under 1, 2, 4 or 8
// bits a pixel, or the block's 64 words — and a place of a power of two of
// granules.
#[test]
fn a_tile_folds_to_its_table_and_its_blocks_least_forms() {
    let (_, folded, _) = folded(&tiles());
    let most = (MOST_FOLDED_BYTES / 4) as u32;
    assert_eq!(
        folded.sizes,
        [256, 256, 256 + 256 * 3, 256 + 7 + 4, tile_words(every_count), most],
        "nothing, one colour, a palette of one, a little ink, every count, the most as they are"
    );
    assert_eq!(tile_words(every_count), 7312);
    let granules: Vec<Option<u16>> = (0..folded.sizes.len()).map(|at| folded.granules(at)).collect();
    assert_eq!(granules, [Some(1), Some(1), Some(4), Some(2), Some(32), Some(32)]);
}

// The granules a folded tile takes: as many as hold its words, in a place
// of a power of two of them, and none past half a tile as it is.
#[test]
fn a_folded_tile_takes_a_power_of_two_of_granules_up_to_half_a_tile() {
    let sizes = vec![256, 257, 512, 513, 1280, 4097, 8192, 8193, 16640];
    let folded = Folded { words: plane(rig().engine, "none", 4), sizes };
    let granules: Vec<Option<u16>> = (0..folded.sizes.len()).map(|at| folded.granules(at)).collect();
    assert_eq!(
        granules,
        [Some(1), Some(2), Some(2), Some(4), Some(8), Some(32), Some(32), None, None]
    );
    assert_eq!(MOST_FOLDED_BYTES, 32 * GRANULE_BYTES);
}

// Every pass that reads a stored tile reads a folded one as it reads the
// tile as it is: the composite — a row copied and a row posed, which reads
// four pixels for one —, the walk over a cel's pixels (its ink), and the
// two side by side in one row.
#[test]
fn every_pass_reads_a_folded_tile_as_it_reads_the_tile_as_it_is() {
    let tiles = tiles();
    let (stored, _, places) = folded(&tiles);
    let half = [1.0, 0.0, 0.5, 0.0, 1.0, 0.5, 0.0, 0.0, 1.0];
    let half = ResampleMap::new(half, 1.0, ResampleMode::Blend, TILE, TILE).unwrap();
    let side_by_side: Vec<TileAt> = (0..tiles.len())
        .map(|at| if at % 2 == 0 { places[at] } else { stored.as_they_are[at] })
        .collect();
    for (name, step) in [
        ("copied", row(0, (0, 0), WHOLE, NORMAL)),
        ("posed", with_map(0, half, WHOLE, NORMAL)),
    ] {
        let as_they_are = laid(&stored.pages, &stored.as_they_are, step);
        assert!(as_they_are.iter().any(|&byte| byte != 0), "{name} lays something");
        assert!(laid(&stored.pages, &places, step) == as_they_are, "{name}, folded");
        assert!(laid(&stored.pages, &side_by_side, step) == as_they_are, "{name}, side by side");
    }
    let Kernels { ink, .. } = kernels();
    let inked = |places: &[TileAt]| ink.run(rig().engine, &stored.pages, &a_row(places)).expect("ink");
    let as_they_are = inked(&stored.as_they_are);
    assert!(as_they_are[0].ink.is_none() && as_they_are[3].ink.is_some());
    assert_eq!(inked(&places), as_they_are);
}

// A tile that folds to more than a folded tile takes stays as it is: its
// size says so, and its blocks write nothing past its own words — the
// tile after it folds to its table alone, and every word after that table
// is as the buffer was made.
#[test]
fn a_tile_past_half_stays_as_it_is_and_writes_nothing_past_its_words() {
    let engine = rig().engine;
    let one_past = tile_of(4, as_they_are(MOST_AS_THEY_ARE + 1));
    let tiles = [tile_of(3, |_| PIXELS), flat(0), one_past, flat(0)];
    let stored = stored(&tiles);
    let folded = kernels().fold.folded(engine, &stored.pages, &stored.as_they_are).expect("fold");
    let most = (MOST_FOLDED_BYTES / 4) as u32;
    assert_eq!(folded.sizes, [256 + 256 * 64, 256, most + 64, 256]);
    assert_eq!(folded.granules(0), None);
    assert_eq!(folded.granules(2), None);
    let words = read_buffer(engine, &folded.words);
    for after in [1, 3] {
        let its = &words[after * MOST_FOLDED_BYTES as usize..][..MOST_FOLDED_BYTES as usize];
        assert!(its.iter().all(|&byte| byte == 0), "the tile after tile {}", after - 1);
    }
    // And it is given no place.
    let at = TileAt { page: 1, slot: FOLDED };
    assert!(folded.put(engine, &stored.pages, &[(0, at)]).is_none());
    assert!(folded.put(engine, &stored.pages, &[(1, at)]).is_some());
}

// A pass cut smaller — fewer pages bound, fewer tiles taken — folds the
// same: each tile's words where its place among them all says, and its
// size there. The tiles lie on three pages, one of them folded already.
#[test]
fn a_fold_cut_into_smaller_passes_folds_the_same() {
    let engine = rig().engine;
    let Kernels { fold, .. } = kernels();
    let tiles = tiles();
    let (mut stored, _, places) = folded(&tiles);
    let more = [tile_of(5, every_count), sparse()];
    stored.pages.push(words_buffer(engine, "more tiles", &more.concat(), PAGE));
    let at = |page, slot| TileAt { page, slot };
    let all = [at(2, 1), places[4], at(0, 3), at(2, 0), places[5], at(0, 4), places[2]];
    let whole = fold.folded(engine, &stored.pages, &all).expect("fold");
    assert_eq!(whole.sizes, [267, 7312, 267, 7312, 8192, 7312, 1024]);
    let words = read_buffer(engine, &whole.words);
    for cut in [(1, 1), (1, 3), (2, 2), (2, usize::MAX)] {
        let folded = fold.folded_by(engine, &stored.pages, &all, cut).expect("fold");
        assert_eq!(folded.sizes, whole.sizes, "{cut:?}");
        assert!(read_buffer(engine, &folded.words) == words, "{cut:?}");
    }
    assert!(fold.folded_by(engine, &stored.pages, &all, (0, 1)).is_none());
    assert!(fold.folded_by(engine, &stored.pages, &all, (1, 0)).is_none());
}

// A fold reads its tile as any pass does, so a folded tile folds again to
// the words it has.
#[test]
fn a_folded_tile_folds_again_to_the_same_words() {
    let engine = rig().engine;
    let (stored, first, places) = folded(&tiles());
    let again = kernels().fold.folded(engine, &stored.pages, &places).expect("fold");
    assert_eq!(again.sizes, first.sizes);
    assert!(read_buffer(engine, &again.words) == read_buffer(engine, &first.words));
}

// What is no fold and no place is refused by name, not folded or copied
// somewhere: no tile, a page the pool has not, a place that is not a
// folded one, one past its page — and a tile as it is is put to no folded
// place.
#[test]
fn what_is_no_tile_s_place_is_refused() {
    let engine = rig().engine;
    let Kernels { fold, .. } = kernels();
    let tiles = tiles();
    let (stored, folded, places) = folded(&tiles);
    assert!(fold.folded(engine, &stored.pages, &[]).is_none());
    assert!(fold.folded(engine, &stored.pages, &[TileAt { page: 2, slot: 0 }]).is_none());
    let put = |index, at| folded.put(engine, &stored.pages, &[(index, at)]);
    assert!(put(4, places[4]).is_some());
    assert!(put(tiles.len(), places[4]).is_none(), "no such tile folded");
    assert!(put(4, stored.as_they_are[4]).is_none(), "a place as it is");
    assert!(put(4, TileAt { page: 2, slot: FOLDED }).is_none(), "no such page");
    // Its 32 granules, the last of them past the page's.
    let granules = (stored.pages[1].size() / GRANULE_BYTES) as u16;
    assert!(put(4, TileAt { page: 1, slot: FOLDED | (granules - 32) }).is_some());
    assert!(put(4, TileAt { page: 1, slot: FOLDED | (granules - 31) }).is_none(), "past its page");
    let unwritable = [stored.pages[0].clone(), plane(engine, "no page", stored.pages[1].size())];
    assert!(folded.put(engine, &unwritable, &[(4, places[4])]).is_none(), "no copy's destination");
    // The write path puts a tile as it is, and to no folded place.
    let source = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
    let as_it_is = words_buffer(engine, "tiles put", &tiles[4], source);
    assert!(Write::put(engine, &stored.pages, &as_it_is, &[(0, stored.as_they_are[4])]).is_some());
    assert!(Write::put(engine, &stored.pages, &as_it_is, &[(0, places[4])]).is_none());
    // And its test reads no place past its page: a tile's bytes as it is, a
    // folded one's table.
    let said = |at| kernels().write.changed(engine, &stored.pages, &as_it_is, &[Some(at)]);
    let slots = (stored.pages[0].size() / TILE_BYTES) as u16;
    assert!(said(TileAt { page: 0, slot: slots - 1 }).is_some());
    assert!(said(TileAt { page: 0, slot: slots }).is_none());
    assert!(said(TileAt { page: 1, slot: FOLDED | (granules - 1) }).is_some());
    assert!(said(TileAt { page: 1, slot: FOLDED | granules }).is_none());
}
