//! The pool on a real GPU: a cel's tiles keep to pages of its own, a slot
//! is handed out again only once none holds it — the one released last
//! first —, and the pages are what the write path copies to, a pass reads
//! and a readback reads.

use super::{Full, MOST_NAMED, Pool};
use crate::kernels::composite::tests::{Rig, mix, rig};
use crate::kernels::composite::{TILE_BYTES, TILE_TEXELS, TileAt, TileSet};
use crate::kernels::shared::{le_bytes, room, words_buffer};
use crate::kernels::write::Write;
use crate::platform::VideoMemory;
use crate::testing::read_buffer;

fn at(page: u16, slot: u16) -> TileAt {
    TileAt { page, slot }
}

/// A tile of words of its own, `n` — a pixel of no alpha all 0, as a pass
/// lays one ([`texel`]'s pixels are so for the same reason).
///
/// [`texel`]: crate::kernels::composite::tests::texel
fn tile(n: u32) -> Vec<u32> {
    let word = |i| match mix(n.wrapping_mul(7919) ^ i) {
        word if word >> 24 == 0 => 0,
        word => word,
    };
    (0..TILE_TEXELS as u32).map(word).collect()
}

// A page holds what one binding of the device does, 128 MiB at most, and
// none is made before a cel needs one.
#[test]
fn a_page_holds_what_a_binding_does_and_no_more_than_128_mib() {
    let engine = rig().engine;
    let pool = Pool::new(engine, u64::MAX).expect("pool");
    assert_eq!(pool.slots() as u64, room(engine).min(128 << 20) / TILE_BYTES);
    assert!(pool.pages().is_empty());
    // A page has as many slots as a u16 names, and at least one.
    let named = usize::from(u16::MAX) + 1;
    assert!(Pool::sized(0, 1, u64::MAX).is_none());
    assert!(Pool::sized(1, 1, u64::MAX).is_some());
    assert!(Pool::sized(named, 1, u64::MAX).is_some());
    assert!(Pool::sized(named + 1, 1, u64::MAX).is_none());
}

// A cel's tiles go on its own pages, the first of them with room first; a
// page full, its next tile is on a page of its own again.
#[test]
fn a_cel_s_tiles_keep_to_pages_of_its_own() {
    let engine = rig().engine;
    let mut pool = Pool::sized(3, MOST_NAMED, u64::MAX).expect("pool");
    let (a, b) = (pool.cel(), pool.cel());
    let mut fresh = |cel| pool.fresh(engine, cel).expect("fresh");
    assert_eq!(fresh(a), at(0, 0));
    assert_eq!(fresh(b), at(1, 0));
    assert_eq!(fresh(a), at(0, 1));
    assert_eq!(fresh(a), at(0, 2));
    assert_eq!(fresh(a), at(2, 0));
    assert_eq!(fresh(b), at(1, 1));
    assert_eq!(pool.pages().len(), 3);
}

// A slot held twice is free after two releases, not one; free slots are
// handed out again the one released last first, on the cel's first page
// with one.
#[test]
fn a_slot_is_handed_out_again_once_none_holds_it_the_last_released_first() {
    let engine = rig().engine;
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let a = pool.cel();
    let tiles: Vec<TileAt> = (0..4).map(|_| pool.fresh(engine, a).expect("fresh")).collect();
    pool.hold(tiles[1]).expect("hold");
    pool.release(tiles[1]).expect("release");
    pool.release(tiles[2]).expect("release");
    pool.release(tiles[3]).expect("release");
    assert_eq!(pool.fresh(engine, a), Ok(tiles[3]));
    assert_eq!(pool.fresh(engine, a), Ok(tiles[2]));
    assert_eq!(pool.fresh(engine, a), Ok(at(1, 0)), "the tile held twice is held still");
    pool.release(tiles[1]).expect("release");
    assert_eq!(pool.fresh(engine, a), Ok(tiles[1]));
}

// A page none of whose slots is held is nobody's: the next cel that needs a
// page takes it, and no page more is made.
#[test]
fn a_page_none_holds_is_the_next_cel_s_that_needs_one() {
    let engine = rig().engine;
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let (a, b) = (pool.cel(), pool.cel());
    let first = [pool.fresh(engine, a), pool.fresh(engine, a)].map(|at| at.expect("fresh"));
    assert_eq!(pool.fresh(engine, b), Ok(at(1, 0)));
    pool.release(first[0]).expect("release");
    assert_eq!(pool.fresh(engine, b), Ok(at(1, 1)), "a page still a's is not b's");
    pool.release(first[1]).expect("release");
    let c = pool.cel();
    assert_eq!(pool.fresh(engine, c), Ok(at(0, 1)));
    assert_eq!(pool.pages().len(), 2);
    assert_eq!(pool.fresh(engine, a), Ok(at(2, 0)), "a's page is c's now");
}

// A free slot is neither held nor released, nor one past the pool; a pool
// with every page it may make taken makes no more.
#[test]
fn a_free_or_unknown_slot_is_neither_held_nor_released() {
    let engine = rig().engine;
    let mut pool = Pool::sized(2, 1, u64::MAX).expect("pool");
    let (a, b) = (pool.cel(), pool.cel());
    let tile = pool.fresh(engine, a).expect("fresh");
    assert!(pool.hold(at(0, 1)).is_none());
    assert!(pool.release(at(0, 1)).is_none());
    assert!(pool.hold(at(1, 0)).is_none());
    assert!(pool.release(at(0, 2)).is_none());
    pool.release(tile).expect("release");
    assert!(pool.release(tile).is_none(), "released twice");
    assert!(pool.hold(tile).is_none(), "held once free");
    assert_eq!(pool.fresh(engine, b), Ok(at(0, 0)));
    assert!(pool.fresh(engine, b).is_ok());
    assert_eq!(pool.fresh(engine, a), Err(Full));
    assert_eq!(pool.pages().len(), 1);
}

// A pool makes no page past the bytes it is given — it says it is full —
// and a page none holds any more is the next cel's that needs one.
#[test]
fn a_pool_makes_no_page_past_its_bytes() {
    let engine = rig().engine;
    let mut pool = Pool::sized(2, MOST_NAMED, 4 * TILE_BYTES).expect("pool");
    let (a, b) = (pool.cel(), pool.cel());
    let first = pool.fresh(engine, a).expect("fresh");
    assert_eq!(pool.fresh(engine, b), Ok(at(1, 0)));
    assert_eq!(pool.fresh(engine, b), Ok(at(1, 1)));
    assert_eq!(pool.fresh(engine, b), Err(Full), "two pages are all its bytes hold");
    assert_eq!(pool.pages().len(), 2);
    pool.release(first).expect("release");
    assert_eq!(pool.fresh(engine, b), Ok(at(0, 0)));
}

// Where the OS says the budget it gives this process, a page more keeps
// within it as within the pool's bytes; where it says none, the pool's
// bytes are the bound.
#[test]
fn a_page_past_the_budget_the_os_gives_is_not_made() {
    let page = 2 * TILE_BYTES;
    let pool = Pool::sized(2, MOST_NAMED, page).expect("pool");
    let said = |used, budget| Some(VideoMemory { used, budget });
    assert!(pool.fits(said(10, Some(10 + page))));
    assert!(!pool.fits(said(11, Some(10 + page))));
    assert!(!pool.fits(said(u64::MAX, Some(u64::MAX))), "a sum past a u64 is past any budget");
    assert!(pool.fits(said(u64::MAX, None)));
    assert!(pool.fits(None));
    let small = Pool::sized(2, MOST_NAMED, page - 1).expect("pool");
    assert!(!small.fits(None));
}

// What the write path copies to a slot is what a pass reads of it and what
// a readback of its page reads there — a cel's tiles over two pages, and
// another cel's between them.
#[test]
fn the_pages_are_what_the_write_path_copies_to_and_a_pass_reads() {
    let Rig { engine, composite } = rig();
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let (a, b) = (pool.cel(), pool.cel());
    let places: Vec<TileAt> =
        [a, a, b, a].iter().map(|&cel| pool.fresh(engine, cel).expect("fresh")).collect();
    let words: Vec<u32> = (0..4).flat_map(tile).collect();
    let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
    let put = words_buffer(engine, "tiles put", &words, usage);
    let writes: Vec<(usize, TileAt)> = places.iter().copied().enumerate().collect();
    Write::put(engine, pool.pages(), &put, &writes).expect("put");
    let set = TileSet {
        x0: 0,
        y0: 0,
        columns: 3,
        rows: 1,
        tiles: vec![Some(places[0]), Some(places[1]), Some(places[3])],
    };
    let tiles = [(0, 0), (1, 0), (2, 0)];
    let read = composite
        .copied(engine, pool.pages(), &set, &tiles, composite.widest())
        .expect("copied");
    assert!(read_buffer(engine, &read.out) == le_bytes(&[tile(0), tile(1), tile(3)].concat()));
    let nothing = vec![0; TILE_TEXELS as usize];
    assert!(read_buffer(engine, &pool.pages()[1]) == le_bytes(&[tile(2), nothing].concat()));
}
