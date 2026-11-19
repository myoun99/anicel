//! The pool on a real GPU: a cel's tiles go to its own pages first and a
//! page is made only where none has room, a slot is handed out again only
//! once none holds it — the one released last first —, the pages nobody
//! holds are given back where its store asks, and the pages are what the
//! write path copies to, a pass reads and a readback reads.

use std::sync::{Condvar, Mutex};
use std::thread::ThreadId;
use std::time::{Duration, Instant};

use super::{Ahead, Full, MOST_NAMED, Pictures, Pool};
use crate::device::{Engine, NO_PAGE_BYTES};
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::composite::tests::{Rig, mix, rig, row, with_map};
use crate::kernels::composite::{
    Budget, FOLDED, NO_EDGE, Plan, TILE, TILE_BYTES, TILE_TEXELS, TileAt, TileSet, WHOLE,
};
use crate::kernels::shared::{ResampleMap, ResampleMode, le_bytes, room, words_buffer};
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
    // A page has as many slots as a u16 names under the bit that says a
    // folded tile's, and at least one.
    let named = usize::from(FOLDED);
    assert!(Pool::sized(0, 1, u64::MAX).is_none());
    assert!(Pool::sized(1, 1, u64::MAX).is_some());
    assert!(Pool::sized(named, 1, u64::MAX).is_some());
    assert!(Pool::sized(named + 1, 1, u64::MAX).is_none());
}

// A cel's tiles go to its own pages first, the first of them with room;
// where none of its has room, to another cel's page with a slot free; and a
// page is made only where no page has one (캔버스 베이스 11-08 02:54: a cel
// on pages of its own, nine of them held 399 of a cut's 8658 tiles).
#[test]
fn a_cel_s_tiles_go_to_its_own_pages_first_and_a_page_is_made_where_none_has_room() {
    let engine = rig().engine;
    let mut pool = Pool::sized(3, MOST_NAMED, u64::MAX).expect("pool");
    let (a, b) = (pool.cel(), pool.cel());
    assert_eq!(pool.fresh(engine, a), Ok(at(0, 0)));
    assert_eq!(pool.fresh(engine, b), Ok(at(0, 1)), "a's page has room");
    assert_eq!(pool.fresh(engine, a), Ok(at(0, 2)));
    assert_eq!(pool.fresh(engine, b), Ok(at(1, 0)), "no page has room");
    pool.release(at(0, 0)).expect("release");
    assert_eq!(pool.fresh(engine, b), Ok(at(1, 1)), "its own page before the first with room");
    assert_eq!(pool.fresh(engine, a), Ok(at(0, 0)));
    assert_eq!(pool.pages().len(), 2);
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
// page takes it — before another cel's page with room —, and no page more
// is made.
#[test]
fn a_page_none_holds_is_the_next_cel_s_that_needs_one() {
    let engine = rig().engine;
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let (a, b) = (pool.cel(), pool.cel());
    let of_a = [pool.fresh(engine, a), pool.fresh(engine, a)].map(|at| at.expect("fresh"));
    assert_eq!(pool.fresh(engine, b), Ok(at(1, 0)));
    pool.release(of_a[0]).expect("release");
    assert_eq!(pool.fresh(engine, b), Ok(at(1, 1)), "b's own page first");
    pool.release(at(1, 0)).expect("release");
    pool.release(at(1, 1)).expect("release");
    let c = pool.cel();
    assert_eq!(pool.fresh(engine, c), Ok(at(1, 1)), "nobody's page before a's with room");
    assert_eq!(pool.fresh(engine, c), Ok(at(1, 0)));
    assert_eq!(pool.fresh(engine, b), Ok(at(0, 0)), "c's page full, a's with room");
    assert_eq!(pool.pages().len(), 2);
}

// A cel's tile on another cel's page with room leaves the page the other's:
// the other's tiles still go there first, before a page with room that
// lies earlier.
#[test]
fn a_page_stays_the_cel_s_whose_tiles_go_to_it_first() {
    let engine = rig().engine;
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let (x, a, b) = (pool.cel(), pool.cel(), pool.cel());
    let of_x = [pool.fresh(engine, x), pool.fresh(engine, x)].map(|at| at.expect("fresh"));
    assert_eq!(pool.fresh(engine, a), Ok(at(1, 0)));
    let of_b = pool.fresh(engine, b).expect("fresh");
    assert_eq!(of_b, at(1, 1), "a's page has room");
    pool.release(of_x[0]).expect("release");
    pool.release(of_b).expect("release");
    assert_eq!(pool.fresh(engine, a), Ok(at(1, 1)), "a's page, not x's with room");
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
    assert_eq!(pool.fresh(engine, b), Ok(at(0, 1)));
    assert_eq!(pool.fresh(engine, b), Ok(at(1, 0)));
    assert_eq!(pool.fresh(engine, b), Ok(at(1, 1)));
    assert_eq!(pool.fresh(engine, b), Err(Full), "two pages are all its bytes hold");
    assert_eq!(pool.pages().len(), 2);
    pool.release(first).expect("release");
    assert_eq!(pool.fresh(engine, b), Ok(at(0, 0)));
    let mut none = Pool::new(engine, 0).expect("pool");
    let cel = none.cel();
    assert_eq!(none.fresh(engine, cel), Err(Full), "given no bytes, it makes no page");
}

// The bytes a pool may make move after it is made: the pages made stay —
// its bytes count them whole — and the next is made only within the bytes
// given now; a page none holds any more is still the next cel's.
#[test]
fn a_pool_s_bytes_move_and_the_pages_it_made_stay() {
    let engine = rig().engine;
    let page = 2 * TILE_BYTES;
    let mut pool = Pool::sized(2, MOST_NAMED, 0).expect("pool");
    let (a, b) = (pool.cel(), pool.cel());
    assert_eq!(pool.fresh(engine, a), Err(Full), "given no bytes, it makes no page");
    assert_eq!(pool.bytes(), 0);
    pool.set_most_bytes(page);
    let first = pool.fresh(engine, a).expect("a page within the bytes given now");
    assert_eq!(pool.bytes(), page);
    pool.set_most_bytes(0);
    let second = pool.fresh(engine, a).expect("a page made keeps its slots");
    assert_eq!(second, at(0, 1));
    assert_eq!(pool.fresh(engine, b), Err(Full));
    pool.release(first).expect("release");
    pool.release(second).expect("release");
    assert_eq!(pool.fresh(engine, b), Ok(at(0, 1)), "a page none holds is made already");
    assert_eq!(pool.bytes(), page, "a page none holds still counts");
}

// Where the OS says the budget it gives this process, a page more keeps
// within it as within the pool's bytes; where it says none, the pool's
// bytes are the bound.
#[test]
fn a_page_past_the_budget_the_os_gives_is_not_made() {
    let page = 2 * TILE_BYTES;
    let mut pool = Pool::sized(2, MOST_NAMED, page).expect("pool");
    // Kept to the OS's, as the app's pool is (`BUDGET_TILL_ONE_IS_SET`).
    pool.set_budget_instead(None);
    let said =
        |used, budget| Some(VideoMemory { used, budget, in_system: None, total: None });
    assert!(pool.fits(said(10, Some(10 + page)), page));
    assert!(!pool.fits(said(11, Some(10 + page)), page));
    assert!(!pool.fits(said(u64::MAX, Some(u64::MAX)), page), "a sum past a u64 is past any budget");
    assert!(pool.fits(said(u64::MAX, None), page));
    assert!(pool.fits(None, page));
    let mut small = Pool::sized(2, MOST_NAMED, page - 1).expect("pool");
    small.set_budget_instead(None);
    assert!(!small.fits(None, page));
    assert!(small.fits(said(10, Some(10 + page - TILE_BYTES)), page - TILE_BYTES), "grown by less");
}

// cargo test's pool keeps to no budget but its own bytes till a test sets
// one — made by itself, by the engine's size, or over the C ABI as the
// flood's tests make theirs: an OS that gives this process nothing makes
// no test's pool full (pool-tests-ride-the-os-vram-budget).
#[test]
fn a_test_s_pool_makes_a_page_whatever_budget_the_os_gives() {
    use super::{gpu_engine_pool_free, gpu_engine_pool_new};
    let engine = rig().engine;
    let nothing = Some(VideoMemory { used: u64::MAX / 2, budget: Some(0), in_system: None, total: None });
    let made = Pool::new(engine, u64::MAX).expect("pool");
    assert!(made.fits(nothing, made.page_bytes()), "by the engine's size");
    let sized = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    assert!(sized.fits(nothing, sized.page_bytes()), "by its own");
    // SAFETY: the engine is the tests' own, alive for the run; the pool is
    // freed once asked.
    unsafe {
        let handed = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        assert!((*handed).fits(nothing, (*handed).page_bytes()), "over the C ABI");
        gpu_engine_pool_free(handed);
    }
}

// A budget kept to in the OS's place is the bound in it — below what the OS
// says or past it —, and the OS's is again once none is kept to.
#[test]
fn a_budget_kept_to_instead_stands_in_the_os_s_place() {
    let page = 2 * TILE_BYTES;
    let mut kept = Pool::sized(2, MOST_NAMED, page).expect("pool");
    let said =
        |used, budget| Some(VideoMemory { used, budget, in_system: None, total: None });
    kept.set_budget_instead(Some(page - 1));
    assert!(!kept.fits(None, page), "where the OS says nothing");
    assert!(!kept.fits(said(0, Some(u64::MAX)), page), "where the OS gives more");
    assert!(kept.fits(said(0, Some(0)), page - 1), "where the OS gives less");
    kept.set_budget_instead(Some(u64::MAX));
    assert!(kept.fits(said(11, Some(10 + page)), page), "past the OS's");
    kept.set_budget_instead(None);
    assert!(!kept.fits(said(11, Some(10 + page)), page), "the OS's again");
}

// A page is made against the budget kept to: none at a line of nothing, one
// past any — and where the OS says nothing, what counts against it is the
// pool's own bytes.
#[test]
fn a_page_is_made_within_the_budget_kept_to_instead() {
    let engine = rig().engine;
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let cel = pool.cel();
    pool.set_budget_instead(Some(0));
    assert_eq!(pool.fresh(engine, cel), Err(Full), "a line of nothing");
    assert_eq!(pool.bytes(), 0);
    pool.set_budget_instead(Some(u64::MAX));
    assert_eq!(pool.fresh(engine, cel), Ok(at(0, 0)), "past any budget");
    let page = pool.bytes();
    pool.set_budget_instead(Some(page + TILE_BYTES - 1));
    assert!(!pool.fits(None, TILE_BYTES), "the pool's own bytes count where the OS says none");
    assert!(pool.fits(None, TILE_BYTES - 1));
}

/// `count` cels a page each, the page full: the slots of each, in order.
fn cels_a_page_each(engine: &crate::device::Engine, pool: &mut Pool, count: usize) -> Vec<Vec<TileAt>> {
    let slots = pool.slots();
    (0..count)
        .map(|_| {
            let cel = pool.cel();
            (0..slots).map(|_| pool.fresh(engine, cel).expect("fresh")).collect()
        })
        .collect()
}

// Its store gives back the pages nobody holds — on the memory warning, a
// project closed, its budget fallen under them (pool-pages-given-back): the
// last first, those past the last held cut off and one before it kept a
// tile's stand-in in its place, as a TileAt names a page by its place. A
// slot of one is no slot; a pass reads a page past it as before; and the
// next cel that needs a page has it made again there, before one past the
// last.
#[test]
fn the_pages_nobody_holds_are_given_back_the_last_first() {
    let Rig { engine, .. } = rig();
    let page = 2 * TILE_BYTES;
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let places = cels_a_page_each(engine, &mut pool, 4);
    let words: Vec<u32> = (0..2).flat_map(tile).collect();
    let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
    let put = words_buffer(engine, "tiles put", &words, usage);
    Write::put(engine, pool.pages(), &put, &[(0, places[1][0]), (1, places[1][1])]).expect("put");
    for &at in [&places[0], &places[2], &places[3]].into_iter().flatten() {
        pool.release(at).expect("release");
    }
    pool.give_back(engine, 0);
    assert_eq!(pool.pages().len(), 2, "the two past the last held cut off");
    assert_eq!(pool.pages()[0].size(), NO_PAGE_BYTES, "the one before it the engine's stand-in");
    assert_eq!(pool.bytes(), page, "which is none of the pool's bytes");
    assert!(read_back(&pool, &places[1]) == le_bytes(&words), "a page past it read as before");
    assert!(pool.release(at(0, 0)).is_none(), "a slot of a page given back");
    assert!(pool.hold(at(0, 0)).is_none());
    assert!(pool.release(at(2, 0)).is_none(), "a slot of a page cut off");
    let next = pool.cel();
    assert_eq!(pool.fresh(engine, next), Ok(at(0, 0)), "made again in its place");
    assert_eq!(pool.pages()[0].size(), page);
    assert_eq!(pool.fresh(engine, next), Ok(at(0, 1)));
    assert_eq!(pool.fresh(engine, next), Ok(at(2, 0)), "then one past the last");
    assert_eq!(pool.bytes(), 3 * page);
}

// Pages are given back only till they hold the bytes asked — a budget fallen
// under them keeps what lies within it —, and a stand-in left last goes
// with the page past it: it names no page a slot is held on.
#[test]
fn pages_are_given_back_till_they_hold_the_bytes_asked() {
    let engine = rig().engine;
    let page = 2 * TILE_BYTES;
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let places = cels_a_page_each(engine, &mut pool, 4);
    for &at in [&places[1], &places[3]].into_iter().flatten() {
        pool.release(at).expect("release");
    }
    pool.give_back(engine, 4 * page);
    assert_eq!(pool.bytes(), 4 * page, "within the bytes asked");
    pool.give_back(engine, 3 * page);
    assert_eq!(pool.pages().len(), 3, "the last cut off, enough");
    assert_eq!(pool.pages()[1].size(), page, "the one between kept");
    pool.give_back(engine, 3 * page - 1);
    assert_eq!(pool.pages()[1].size(), NO_PAGE_BYTES);
    assert_eq!(pool.bytes(), 2 * page);
    for &at in &places[2] {
        pool.release(at).expect("release");
    }
    pool.give_back(engine, 2 * page);
    assert_eq!(pool.pages().len(), 3, "within the bytes asked");
    pool.give_back(engine, 2 * page - 1);
    assert_eq!(pool.pages().len(), 1, "the stand-in left last gone with the page past it");
    assert_eq!(pool.bytes(), page);
    pool.give_back(engine, 0);
    assert_eq!(pool.bytes(), page, "a page held stays");
}

// A page given back is made again within the bytes the pool held with it
// made and past the pages a pool may make: its place is named already.
#[test]
fn a_page_given_back_is_made_again_within_the_pool_s_bounds() {
    let engine = rig().engine;
    let page = 2 * TILE_BYTES;
    let mut pool = Pool::sized(2, 2, 2 * page).expect("pool");
    let places = cels_a_page_each(engine, &mut pool, 2);
    for &at in &places[0] {
        pool.release(at).expect("release");
    }
    pool.give_back(engine, 0);
    assert_eq!(pool.bytes(), page);
    let next = pool.cel();
    assert_eq!(pool.fresh(engine, next), Ok(at(0, 0)));
    assert_eq!(pool.bytes(), 2 * page);
}

// What the write path copies to a slot is what a pass reads of it and what
// a readback of its page reads there — a cel's tiles over two pages, the
// last on another cel's.
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
    assert_eq!(pool.pages().len(), 2);
    assert!(read_buffer(engine, &pool.pages()[1]) == le_bytes(&[tile(2), tile(3)].concat()));
}

// The pages shared, a cel's tiles may lie on more pages than a pass binds
// — two where GLES reports four (관제 11-08 02:57): a cel stored after
// three others took a page and a half lies on three, and a pass of two
// pages, or of one, lays it as a pass binding them all does — copied, a
// step a page; posed, its tiles under an output tile gathered.
#[test]
fn a_cel_on_more_pages_than_a_pass_binds_composites_as_in_one_pass() {
    let Rig { engine, composite } = rig();
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    for _ in 0..3 {
        let cel = pool.cel();
        pool.fresh(engine, cel).expect("fresh");
    }
    let cel = pool.cel();
    let places: Vec<TileAt> = (0..4).map(|_| pool.fresh(engine, cel).expect("fresh")).collect();
    assert_eq!(places, [at(1, 1), at(2, 0), at(2, 1), at(3, 0)]);
    let words: Vec<u32> = (0..4).flat_map(tile).collect();
    let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
    let put = words_buffer(engine, "tiles put", &words, usage);
    let writes: Vec<(usize, TileAt)> = places.iter().copied().enumerate().collect();
    Write::put(engine, pool.pages(), &put, &writes).expect("put");
    let sets = [TileSet {
        x0: 0,
        y0: 0,
        columns: 2,
        rows: 2,
        tiles: places.iter().copied().map(Some).collect(),
    }];
    let tiles = [(0, 0), (1, 0), (0, 1), (1, 1)];
    let both = [1.0, 0.0, 0.5, 0.0, 1.0, 0.5, 0.0, 0.0, 1.0];
    let half = ResampleMap::new(both, 1.0, ResampleMode::Blend, TILE, TILE).unwrap();
    let copied = row(0, (0, 0), WHOLE, NORMAL);
    for (name, step) in [("copied", copied), ("posed", with_map(0, half, WHOLE, NORMAL))] {
        let steps = [step];
        let plan = Plan {
            pages: pool.pages(),
            sets: &sets,
            keys: &[],
            matrices: &[],
            chains: &[],
            steps: &steps,
            mask: None,
            stamps: None,
        };
        let laid = |pages| {
            let budget = Budget { pages, ..composite.widest() };
            let done = composite.run(engine, &plan, &tiles, NO_EDGE, budget).expect("composite");
            read_buffer(engine, &done.out)
        };
        let all = laid(composite.widest().pages);
        for pages in [1, 2] {
            assert!(laid(pages) == all, "{name} at {pages} pages a pass");
        }
    }
}

/// What a store through the C ABI tells where its tiles' bytes are read
/// (`gpu_engine_pool_store`) and a test that keeps them for its run asks
/// nothing of.
extern "C" fn told_nothing(_: u64, _: bool) {}

/// What `places` of `pool` hold, read as a pass reads them: one row of
/// output tiles, a stored tile each.
fn read_back(pool: &Pool, places: &[TileAt]) -> Vec<u8> {
    let Rig { engine, composite } = rig();
    let set = TileSet {
        x0: 0,
        y0: 0,
        columns: places.len() as u32,
        rows: 1,
        tiles: places.iter().copied().map(Some).collect(),
    };
    let tiles: Vec<(i32, i32)> = (0..places.len() as i32).map(|column| (column, 0)).collect();
    let read = composite
        .copied(engine, pool.pages(), &set, &tiles, composite.widest())
        .expect("copied");
    read_buffer(engine, &read.out)
}

// The app's tiles, stored from the CPU, land each whole in a fresh slot of
// their cel — its own pages first, then a page with room, as a fresh slot
// is.
#[test]
fn stored_tiles_land_each_in_a_fresh_slot_of_their_cel() {
    let engine = rig().engine;
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let (a, b) = (pool.cel(), pool.cel());
    let bytes: Vec<Vec<u8>> = (0..4).map(|n| le_bytes(&tile(n))).collect();
    let tiles: Vec<&[u8]> = bytes.iter().map(Vec::as_slice).collect();
    let of_a = pool.store(engine, a, &tiles[..3]).expect("store a");
    let of_b = pool.store(engine, b, &tiles[3..]).expect("store b");
    assert_eq!(of_a, [at(0, 0), at(0, 1), at(1, 0)]);
    assert_eq!(of_b, [at(1, 1)]);
    let places = [of_a, of_b].concat();
    assert!(read_back(&pool, &places) == bytes.concat());
}

// A pool full partway stores the tiles before it, keeps them, and stores
// none past it; a tile not of a tile's bytes is refused, and no slot is
// taken for any of its store.
#[test]
fn a_store_stops_where_the_pool_is_full_and_refuses_a_tile_of_other_bytes() {
    let engine = rig().engine;
    let mut pool = Pool::sized(2, MOST_NAMED, 2 * TILE_BYTES).expect("pool");
    let cel = pool.cel();
    let bytes: Vec<Vec<u8>> = (0..3).map(|n| le_bytes(&tile(n))).collect();
    let tiles: Vec<&[u8]> = bytes.iter().map(Vec::as_slice).collect();
    let stored = pool.store(engine, cel, &tiles).expect("store");
    assert_eq!(stored, [at(0, 0), at(0, 1)], "one page is all its bytes hold");
    assert!(read_back(&pool, &stored) == bytes[..2].concat());
    assert_eq!(pool.store(engine, cel, &tiles[2..]), Some(Vec::new()));
    let mut room = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let other = room.cel();
    let short = [tiles[0], &tiles[1][1..]];
    assert!(room.store(engine, other, &short).is_none());
    assert_eq!(room.fresh(engine, other), Ok(at(0, 0)), "the refused store took no slot");
}

// The C ABI stores and lets go as the pool does: a cel a number of its
// own, each tile's place written out, a slot let go handed out again, and
// one let go twice refused.
#[test]
fn the_c_abi_stores_and_lets_go_as_the_pool_does() {
    use super::{
        gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_new, gpu_engine_pool_release,
        gpu_engine_pool_store,
    };
    let engine = rig().engine;
    let bytes: Vec<Vec<u8>> = (0..2).map(|n| le_bytes(&tile(n))).collect();
    let tiles: Vec<*const u8> = bytes.iter().map(|tile| tile.as_ptr()).collect();
    let (mut pages, mut slots) = ([u16::MAX; 2], [u16::MAX; 2]);
    // SAFETY: the engine is the tests' own, alive for the run; the tiles,
    // pages and slots hold two each.
    unsafe {
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        assert!(!pool.is_null());
        let (a, b) = (gpu_engine_pool_cel(pool), gpu_engine_pool_cel(pool));
        assert_ne!(a, b);
        let stored = gpu_engine_pool_store(
            pool,
            engine,
            a,
            tiles.as_ptr(),
            2,
            pages.as_mut_ptr(),
            slots.as_mut_ptr(),
            told_nothing,
            0,
        );
        assert_eq!(stored, 2);
        assert_eq!((pages, slots), ([0, 0], [0, 1]));
        assert!(read_back(&*pool, &[at(0, 0), at(0, 1)]) == bytes.concat());
        assert!(gpu_engine_pool_release(pool, 0, 0));
        assert!(!gpu_engine_pool_release(pool, 0, 0), "let go twice");
        let again =
            gpu_engine_pool_store(pool, engine, a, tiles.as_ptr(), 1, pages.as_mut_ptr(), slots.as_mut_ptr(), told_nothing, 0);
        assert_eq!((again, pages[0], slots[0]), (1, 0, 0));
        let none = gpu_engine_pool_store(pool, engine, b, tiles.as_ptr(), 0, pages.as_mut_ptr(), slots.as_mut_ptr(), told_nothing, 0);
        assert_eq!(none, 0);
        gpu_engine_pool_free(pool);
        gpu_engine_pool_free(std::ptr::null_mut());
        let full = gpu_engine_pool_new(engine, u64::MAX, 0);
        let cel = gpu_engine_pool_cel(full);
        let stored =
            gpu_engine_pool_store(full, engine, cel, tiles.as_ptr(), 2, pages.as_mut_ptr(), slots.as_mut_ptr(), told_nothing, 0);
        assert_eq!(stored, 0, "a pool given no bytes stores none of the two");
        gpu_engine_pool_free(full);
    }
}

// The C ABI moves the bytes a pool may make, counts the pages it made and
// gives back the pages nobody holds, as the pool does.
#[test]
fn the_c_abi_moves_a_pool_s_bytes_counts_its_pages_and_gives_them_back() {
    use super::{
        gpu_engine_pool_bytes, gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_give_back,
        gpu_engine_pool_most_bytes, gpu_engine_pool_new, gpu_engine_pool_release, gpu_engine_pool_store,
    };
    let engine = rig().engine;
    let bytes = le_bytes(&tile(3));
    let tiles = [bytes.as_ptr()];
    let (mut pages, mut slots) = ([u16::MAX], [u16::MAX]);
    // SAFETY: the engine is the tests' own, alive for the run; the tiles,
    // pages and slots hold one each.
    unsafe {
        let pool = gpu_engine_pool_new(engine, u64::MAX, 0);
        let cel = gpu_engine_pool_cel(pool);
        let none =
            gpu_engine_pool_store(pool, engine, cel, tiles.as_ptr(), 1, pages.as_mut_ptr(), slots.as_mut_ptr(), told_nothing, 0);
        assert_eq!(none, 0, "given no bytes, it stores none");
        assert_eq!(gpu_engine_pool_bytes(pool), 0);
        gpu_engine_pool_most_bytes(pool, u64::MAX);
        let one =
            gpu_engine_pool_store(pool, engine, cel, tiles.as_ptr(), 1, pages.as_mut_ptr(), slots.as_mut_ptr(), told_nothing, 0);
        assert_eq!(one, 1);
        assert_eq!(gpu_engine_pool_bytes(pool), (*pool).slots() as u64 * TILE_BYTES);
        assert!(read_back(&*pool, &[at(pages[0], slots[0])]) == bytes);
        gpu_engine_pool_give_back(pool, engine, 0);
        assert_eq!(gpu_engine_pool_bytes(pool), (*pool).slots() as u64 * TILE_BYTES, "a page held stays");
        assert!(gpu_engine_pool_release(pool, pages[0], slots[0]));
        // Given back with the engine's thread held: the books are its
        // caller's, and the page goes on the pages' thread.
        let (go, held) = std::sync::mpsc::channel::<()>();
        (*engine).posted(move || held.recv_timeout(Duration::from_secs(60)).ok());
        let began = Instant::now();
        gpu_engine_pool_give_back(pool, engine, 0);
        assert!(began.elapsed() < Duration::from_secs(30), "the give-back waited for the engine's thread");
        assert_eq!(gpu_engine_pool_bytes(pool), 0);
        go.send(()).expect("the engine's thread waits");
        gpu_engine_pool_free(pool);
    }
}

// The C ABI keeps a pool to a budget in the OS's place, and to the OS's
// again where negative.
#[test]
fn the_c_abi_keeps_a_pool_to_a_budget_in_the_os_s_place() {
    use super::{
        gpu_engine_pool_budget_instead, gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_new,
        gpu_engine_pool_store,
    };
    let engine = rig().engine;
    let bytes = le_bytes(&tile(3));
    let tiles = [bytes.as_ptr()];
    let (mut pages, mut slots) = ([u16::MAX], [u16::MAX]);
    // SAFETY: the engine is the tests' own, alive for the run; the tiles,
    // pages and slots hold one each.
    unsafe {
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        gpu_engine_pool_budget_instead(pool, 0);
        let none =
            gpu_engine_pool_store(pool, engine, cel, tiles.as_ptr(), 1, pages.as_mut_ptr(), slots.as_mut_ptr(), told_nothing, 0);
        assert_eq!(none, 0, "kept to nothing, it stores none");
        gpu_engine_pool_budget_instead(pool, i64::MAX);
        let one = gpu_engine_pool_store(pool, engine, cel, tiles.as_ptr(), 1, pages.as_mut_ptr(), slots.as_mut_ptr(), told_nothing, 0);
        assert_eq!(one, 1, "kept to more than any device has, it stores");
        gpu_engine_pool_budget_instead(pool, -1);
        assert!((*pool).budget_instead.is_none(), "the OS's again");
        gpu_engine_pool_free(pool);
    }
}

// A read puts each held tile's bytes in the order asked, from whichever
// page it is on, as a pass reads them — what a save, a cel cooled and an
// undo record parked read back of the canonical tiles.
#[test]
fn a_read_puts_each_held_tile_s_bytes_in_the_order_asked_from_any_page() {
    let engine = rig().engine;
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let cel = pool.cel();
    let bytes: Vec<Vec<u8>> = (0..3).map(|n| le_bytes(&tile(n))).collect();
    let tiles: Vec<&[u8]> = bytes.iter().map(Vec::as_slice).collect();
    let stored = pool.store(engine, cel, &tiles).expect("store");
    assert_eq!(stored, [at(0, 0), at(0, 1), at(1, 0)], "two pages");
    let asked = [stored[2], stored[0], stored[1], stored[0]];
    let mut into = vec![0xA5; asked.len() * TILE_BYTES as usize];
    pool.read(engine, &asked, &mut into).expect("read");
    assert!(into == [&bytes[2], &bytes[0], &bytes[1], &bytes[0]].map(Vec::as_slice).concat());
    assert!(into == read_back(&pool, &asked), "as a pass reads them");
    assert_eq!(pool.read(engine, &[], &mut []), Some(()), "none asked, none read");
}

// A read of a tile none holds — a slot free, a page past the pool's or one
// given back — or into other bytes than the tiles' is refused, and puts
// nothing.
#[test]
fn a_read_of_a_tile_none_holds_or_into_other_bytes_is_refused() {
    let engine = rig().engine;
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let places = cels_a_page_each(engine, &mut pool, 2);
    let held = places[1][0];
    pool.release(places[1][1]).expect("release");
    let mut into = vec![0xA5; 2 * TILE_BYTES as usize];
    for (asked, why) in [
        (places[1][1], "a slot free"),
        (at(2, 0), "a page past the pool's"),
        (at(1, 2), "a slot past a page's"),
    ] {
        assert_eq!(pool.read(engine, &[held, asked], &mut into), None, "{why}");
    }
    assert!(into.iter().all(|&byte| byte == 0xA5), "refused, it put nothing");
    assert_eq!(pool.read(engine, &[held], &mut into), None, "into two tiles' bytes");
    for &at in &places[0] {
        pool.release(at).expect("release");
    }
    pool.give_back(engine, 0);
    assert_eq!(pool.pages()[0].size(), NO_PAGE_BYTES, "its first page given back");
    let one = &mut into[..TILE_BYTES as usize];
    assert_eq!(pool.read(engine, &[places[0][0]], one), None, "a page given back");
    assert_eq!(pool.read(engine, &[held], one), Some(()), "a page held reads");
}

// The C ABI reads back the tiles its words name, in their order, and
// refuses a word that names none and a tile none holds.
#[test]
fn the_c_abi_reads_back_the_tiles_its_words_name() {
    use super::{
        gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_new, gpu_engine_pool_read, gpu_engine_pool_store,
    };
    use crate::kernels::composite::NO_TILE;
    let engine = rig().engine;
    let bytes: Vec<Vec<u8>> = (0..2).map(|n| le_bytes(&tile(n))).collect();
    let tiles: Vec<*const u8> = bytes.iter().map(|tile| tile.as_ptr()).collect();
    let (mut pages, mut slots) = ([u16::MAX; 2], [u16::MAX; 2]);
    let mut into = vec![0; 2 * TILE_BYTES as usize];
    // SAFETY: the engine is the tests' own, alive for the run; the tiles,
    // pages, slots and words hold two each, and `into` two tiles' bytes.
    unsafe {
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        let stored = gpu_engine_pool_store(pool, engine, cel, tiles.as_ptr(), 2, pages.as_mut_ptr(), slots.as_mut_ptr(), told_nothing, 0);
        assert_eq!(stored, 2);
        let words = [at(pages[1], slots[1]).word(), at(pages[0], slots[0]).word()];
        assert!(gpu_engine_pool_read(pool, engine, words.as_ptr(), 2, into.as_mut_ptr()));
        assert!(into == [bytes[1].as_slice(), &bytes[0]].concat());
        let none = [words[0], NO_TILE];
        assert!(!gpu_engine_pool_read(pool, engine, none.as_ptr(), 2, into.as_mut_ptr()), "a word of none");
        let free = [words[0], at(pages[0], slots[0] + 2).word()];
        assert!(!gpu_engine_pool_read(pool, engine, free.as_ptr(), 2, into.as_mut_ptr()), "a slot free");
        gpu_engine_pool_free(pool);
    }
}

// A readout holds each tile's bytes in the order asked, from whichever
// page it is on, as its slot held them when it was asked for: a slot let
// go and written over since is read as it was — what the copies the app
// keeps of the engine's tiles are taken by, with no wait on the thread
// that asks.
#[test]
fn a_readout_holds_each_tile_s_bytes_as_its_slot_held_them_when_asked() {
    let engine = rig().engine;
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let cel = pool.cel();
    let bytes: Vec<Vec<u8>> = (0..5).map(|n| le_bytes(&tile(n))).collect();
    let tiles: Vec<&[u8]> = bytes[..4].iter().map(Vec::as_slice).collect();
    let stored = pool.store(engine, cel, &tiles).expect("store");
    let asked = [stored[2], stored[0], stored[3], stored[0]];
    let out = pool.read_out(engine, &asked).expect("read out");
    // The first tile's slot goes to another tile before the readout is read.
    pool.release(stored[0]).expect("release");
    let over = pool.store(engine, cel, &[bytes[4].as_slice()]).expect("store");
    assert_eq!(over, [stored[0]], "⛔premise: the slot let go is the one written over");
    let mut now = vec![0; TILE_BYTES as usize];
    pool.read(engine, &over, &mut now).expect("read");
    assert!(now == bytes[4], "⛔premise: it holds the tile stored over it");
    let mut read = vec![0; 4 * TILE_BYTES as usize];
    engine.mapped_into(&out, &mut read).expect("mapped");
    assert!(read == [&bytes[2], &bytes[0], &bytes[3], &bytes[0]].map(Vec::as_slice).concat());
}

// A readout of a tile none holds — a slot free, a page past the pool's —
// or of no tile is refused.
#[test]
fn a_readout_of_a_tile_none_holds_or_of_none_is_refused() {
    let engine = rig().engine;
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let places = cels_a_page_each(engine, &mut pool, 1);
    let held = places[0][0];
    pool.release(places[0][1]).expect("release");
    for (asked, why) in [(places[0][1], "a slot free"), (at(2, 0), "a page past the pool's")] {
        assert!(pool.read_out(engine, &[held, asked]).is_none(), "{why}");
    }
    assert!(pool.read_out(engine, &[]).is_none(), "none asked");
    assert!(pool.read_out(engine, &[held]).is_some(), "a tile held reads out");
}

/// Where a wait its caller did not stay for says that it has ended — a
/// test's, one a wait: the thread that said so, and the number it said.
struct ToldOn(Mutex<Option<(ThreadId, u64)>>, Condvar);

impl ToldOn {
    const fn new() -> Self {
        Self(Mutex::new(None), Condvar::new())
    }

    fn tell(&self, wait: u64) {
        *self.0.lock().expect("told") = Some((std::thread::current().id(), wait));
        self.1.notify_all();
    }

    /// The thread that told and the number it told, once one has.
    fn told(&self) -> (ThreadId, u64) {
        let none_yet = |told: &mut Option<(ThreadId, u64)>| told.is_none();
        let (waiting, minute) = (self.0.lock().expect("told"), Duration::from_secs(60));
        let (told, _) = self.1.wait_timeout_while(waiting, minute, none_yet).expect("told");
        told.expect("a wait that ended is told within the minute")
    }
}

// The C ABI reads out the tiles its words name with no wait on the thread
// that asks — the engine's thread waits for the GPU and tells once they
// are mapped, by the number the wait was asked under, as the app is told
// with its frames going on — and hands them over as rows of a tile's
// bytes, in the words' order; a word that names none, a tile none holds
// and no tile at all are refused.
#[test]
fn the_c_abi_reads_out_the_tiles_its_words_name_and_who_asks_waits_for_no_gpu() {
    use super::{
        gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_new, gpu_engine_pool_readout,
        gpu_engine_pool_store,
    };
    use crate::device::gpu_engine_waits_here;
    use crate::kernels::composite::NO_TILE;
    use crate::kernels::export::abi::{
        gpu_engine_readout_bytes, gpu_engine_readout_free, gpu_engine_readout_map_then,
        gpu_engine_readout_rows,
    };
    use crate::testing::last_error;
    static TOLD: ToldOn = ToldOn::new();
    extern "C" fn told(wait: u64, _: bool) {
        TOLD.tell(wait);
    }
    let engine = rig().engine;
    let bytes: Vec<Vec<u8>> = (0..2).map(|n| le_bytes(&tile(n))).collect();
    let tiles: Vec<*const u8> = bytes.iter().map(|tile| tile.as_ptr()).collect();
    let (mut pages, mut slots) = ([u16::MAX; 2], [u16::MAX; 2]);
    let mut into = vec![0; 2 * TILE_BYTES as usize];
    // SAFETY: the engine is the tests' own, alive for the run; the tiles,
    // pages, slots and words hold two each, and `into` two tiles' bytes;
    // the readout is left alone till its wait is told to have ended.
    unsafe {
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        let (to_pages, to_slots) = (pages.as_mut_ptr(), slots.as_mut_ptr());
        let stored =
            gpu_engine_pool_store(pool, engine, cel, tiles.as_ptr(), 2, to_pages, to_slots, told_nothing, 0);
        assert_eq!(stored, 2);
        let words = [at(pages[1], slots[1]).word(), at(pages[0], slots[0]).word()];
        let readout = gpu_engine_pool_readout(pool, engine, words.as_ptr(), 2);
        assert!(!readout.is_null(), "{}", last_error());
        assert_eq!(gpu_engine_readout_bytes(readout), 2 * TILE_BYTES);
        let (each, to) = (TILE_BYTES, into.as_mut_ptr());
        assert!(!gpu_engine_readout_rows(readout, 0, each, each, 2, to, each), "not mapped yet");
        let waits = gpu_engine_waits_here();
        gpu_engine_readout_map_then(engine, readout, told, 7);
        let (on, wait) = TOLD.told();
        assert_ne!(on, std::thread::current().id(), "told on the engine's thread");
        assert_eq!(wait, 7, "by the number it was asked under");
        assert_eq!(gpu_engine_waits_here(), waits, "the thread that asked waited for no GPU");
        assert!(gpu_engine_readout_rows(readout, 0, each, each, 2, to, each), "{}", last_error());
        assert!(into == [bytes[1].as_slice(), &bytes[0]].concat());
        gpu_engine_readout_free(readout);
        let none = [words[0], NO_TILE];
        let refused = gpu_engine_pool_readout(pool, engine, none.as_ptr(), 2);
        assert!(refused.is_null(), "a word of none");
        let free = [words[0], at(pages[0], slots[0] + 2).word()];
        assert!(gpu_engine_pool_readout(pool, engine, free.as_ptr(), 2).is_null(), "a slot free");
        assert!(gpu_engine_pool_readout(pool, engine, words.as_ptr(), 0).is_null(), "no tile");
        gpu_engine_pool_free(pool);
    }
}

// A readout whose device went before its wait is told all the same, and
// its rows fail by why — the word the app lays those tiles as the pictures
// they landed on for. On an engine of the test's own: a device that is
// gone is gone for every test after it.
#[test]
fn a_readout_whose_device_is_gone_is_told_all_the_same_and_its_rows_fail_by_why() {
    use super::{
        gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_new, gpu_engine_pool_readout,
        gpu_engine_pool_store,
    };
    use crate::device::{
        gpu_engine_close, gpu_engine_gone, gpu_engine_lose, gpu_engine_open_first,
    };
    use crate::kernels::export::abi::{
        gpu_engine_readout_free, gpu_engine_readout_map_then, gpu_engine_readout_rows,
    };
    use crate::testing::{a_device_of_its_own, last_error};
    static TOLD: ToldOn = ToldOn::new();
    extern "C" fn told(wait: u64, _: bool) {
        TOLD.tell(wait);
    }
    let _turn = a_device_of_its_own();
    let bytes = le_bytes(&tile(0));
    let (mut page, mut slot) = (u16::MAX, u16::MAX);
    let mut into = vec![0; TILE_BYTES as usize];
    // SAFETY: the engine is this test's own, live till its close; the tile,
    // page, slot and word are one each, and `into` holds a tile's bytes;
    // the readout is left alone till its wait is told to have ended.
    unsafe {
        let engine = gpu_engine_open_first();
        assert!(!engine.is_null(), "{}", last_error());
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        let stored =
            gpu_engine_pool_store(pool, engine, cel, &bytes.as_ptr(), 1, &mut page, &mut slot, told_nothing, 0);
        assert_eq!(stored, 1);
        let word = at(page, slot).word();
        let readout = gpu_engine_pool_readout(pool, engine, &word, 1);
        assert!(!readout.is_null(), "{}", last_error());
        gpu_engine_lose(engine, false);
        gpu_engine_readout_map_then(engine, readout, told, 0);
        TOLD.told();
        let (each, to) = (TILE_BYTES, into.as_mut_ptr());
        assert!(!gpu_engine_readout_rows(readout, 0, each, each, 1, to, each));
        assert!(last_error().starts_with("the graphics device is gone"), "{}", last_error());
        assert!(gpu_engine_gone(engine));
        gpu_engine_readout_free(readout);
        gpu_engine_pool_free(pool);
        gpu_engine_close(engine);
    }
}

// The pictures' pool hands out slots and takes holds all or none: fresh
// slots past the pages it makes leave none held, and a hold of tiles one
// of which no one holds leaves the ones before it as they were.
#[test]
fn the_pictures_pool_holds_all_that_is_asked_or_none() {
    use crate::testing::last_error;
    let engine = rig().engine;
    // One page of two tiles, and no page more.
    let pool = Pool::sized(2, 1, u64::MAX).expect("pool");
    let pictures = Pictures::of(pool);
    let cel = pictures.cel(engine).expect("a cel");
    assert!(pictures.fresh(engine, cel, 3).is_none());
    assert!(last_error().contains("makes no page more"), "{}", last_error());
    assert_eq!(pictures.idle_bytes(), 2 * TILE_BYTES, "the two handed out before the refusal");
    let (places, _) = pictures.fresh(engine, cel, 1).expect("a slot");
    let free = at(0, 1 - places[0].slot);
    assert!(pictures.hold(engine, &[places[0], free]).is_none());
    assert!(last_error().contains("is free"), "{}", last_error());
    pictures.release(places.iter().copied(), std::iter::empty());
    assert_eq!(pictures.idle_bytes(), 2 * TILE_BYTES, "the hold taken before the refusal");
}

// A page of the engine's pictures' pool holds a 4K canvas's tiles, 32 MiB
// — or what one binding of the device does, where that is less.
#[test]
fn a_page_of_the_engines_pictures_holds_a_4k_canvass_tiles() {
    let engine = rig().engine;
    let slots = engine.pictures.slots(engine).expect("the pool") as u64;
    assert_eq!(slots, room(engine).min(32 << 20) / TILE_BYTES);
    assert!(room(engine) < 32 << 20 || slots >= 30 * 17, "{slots} slots a page");
}

// The engine's pictures' pool makes a page past the OS's budget, where the
// cels' refuses one (⛔`Pictures`: what keeps a picture lets it go, not
// this pool).
#[test]
fn the_engines_pictures_pool_makes_a_page_past_the_oss_budget() {
    let engine = rig().engine;
    let said =
        Some(VideoMemory { used: 11, budget: Some(10), in_system: None, total: None });
    let fits = engine.pictures.with(engine, |pool| Some(pool.fits(said, pool.page_bytes())));
    assert_eq!(fits, Some(true));
}

/// What stores through the C ABI told of their copies: each one's number
/// and whether it wrote (`gpu_engine_pool_store`).
static READ: Mutex<Vec<(u64, bool)>> = Mutex::new(Vec::new());

extern "C" fn read(number: u64, written: bool) {
    READ.lock().unwrap().push((number, written));
}

fn was_read(number: u64) -> Option<bool> {
    READ.lock().unwrap().iter().find(|&&(told, _)| told == number).map(|&(_, written)| written)
}

// A store's copy is the engine's thread's, its caller waiting for none of
// it (the-ui-thread-never-enters-the-driver B1-b): its slot is told while
// that thread stands still, and the copy is told read — and its bytes are
// there — once the thread goes on.
#[test]
fn a_store_tells_its_slot_while_the_engines_thread_stands_still() {
    use super::{gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_new, gpu_engine_pool_read, gpu_engine_pool_store};
    use crate::device::{gpu_engine_close, gpu_engine_open_first, gpu_engine_stand_still};
    use crate::testing::{a_device_of_its_own, done_here, last_error};
    let _turn = a_device_of_its_own();
    let bytes = le_bytes(&tile(5));
    let tiles = [bytes.as_ptr()];
    let (mut page, mut slot) = (u16::MAX, u16::MAX);
    let mut into = vec![0; TILE_BYTES as usize];
    // SAFETY: the engine is this test's own, live till its close; the tile,
    // page, slot and word are one each, and `into` holds a tile's bytes —
    // `bytes` outlives every copy told of.
    unsafe {
        let engine = gpu_engine_open_first();
        assert!(!engine.is_null(), "{}", last_error());
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        // ⛔premise: a page with room — a page is made on the engine's
        // thread, which stands still below.
        assert_eq!(gpu_engine_pool_store(pool, engine, cel, tiles.as_ptr(), 1, &mut page, &mut slot, read, 101), 1);
        assert_eq!(done_here(&*engine), Ok(()));
        assert_eq!(was_read(101), Some(true), "⛔premise: a copy is told");
        gpu_engine_stand_still(engine, 2_000);
        assert_eq!(gpu_engine_pool_store(pool, engine, cel, tiles.as_ptr(), 1, &mut page, &mut slot, read, 102), 1);
        assert_eq!(was_read(102), None, "told its slot before its copy ran");
        assert_eq!(done_here(&*engine), Ok(()));
        assert_eq!(was_read(102), Some(true));
        let word = at(page, slot).word();
        assert!(gpu_engine_pool_read(pool, engine, &word, 1, into.as_mut_ptr()), "{}", last_error());
        assert!(into == bytes, "its slot holds its bytes");
        gpu_engine_pool_free(pool);
        gpu_engine_close(engine);
    }
}

// A pool full by its own bytes says so on its caller's thread: a store is
// told none has a slot while the engine's thread stands still — only the
// OS's count is asked there ([`Pool::claimed`]).
#[test]
fn a_pool_full_by_its_bytes_says_so_while_the_engines_thread_stands_still() {
    use super::{gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_new, gpu_engine_pool_store};
    use crate::device::{gpu_engine_close, gpu_engine_open_first, gpu_engine_stand_still};
    use crate::testing::{a_device_of_its_own, done_here, last_error};
    let _turn = a_device_of_its_own();
    let bytes = le_bytes(&tile(7));
    let tiles = [bytes.as_ptr()];
    let (mut page, mut slot) = (u16::MAX, u16::MAX);
    // SAFETY: the engine is this test's own, live till its close; the tile,
    // page and slot are one each, and no copy is handed over to read
    // `bytes`: none is stored.
    unsafe {
        let engine = gpu_engine_open_first();
        assert!(!engine.is_null(), "{}", last_error());
        // Given no bytes, it makes no page: full before its first tile.
        let pool = gpu_engine_pool_new(engine, u64::MAX, 0);
        let cel = gpu_engine_pool_cel(pool);
        gpu_engine_stand_still(engine, 2_000);
        let asked = Instant::now();
        assert_eq!(gpu_engine_pool_store(pool, engine, cel, tiles.as_ptr(), 1, &mut page, &mut slot, read, 301), 0);
        let told = asked.elapsed();
        assert!(told < Duration::from_millis(1_000), "told after {told:?}, the thread standing 2 s");
        assert_eq!(done_here(&*engine), Ok(()));
        gpu_engine_pool_free(pool);
        gpu_engine_close(engine);
    }
}

// A store's copy the device refuses says so: its slot was told, as the
// books are the caller's, the copy is told unwritten and its place is the
// caller's to let go — taken once — and the caller's next done fails.
#[test]
fn a_store_whose_copy_the_device_refuses_says_its_place_unwritten() {
    use super::{
        gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_new, gpu_engine_pool_store,
        gpu_engine_pool_unwritten,
    };
    use crate::device::{gpu_engine_close, gpu_engine_lose, gpu_engine_open_first};
    use crate::testing::{a_device_of_its_own, done_here, last_error};
    let _turn = a_device_of_its_own();
    let bytes = le_bytes(&tile(6));
    let tiles = [bytes.as_ptr()];
    let (mut page, mut slot) = (u16::MAX, u16::MAX);
    let (mut pages, mut slots) = ([u16::MAX; 2], [u16::MAX; 2]);
    // SAFETY: the engine is this test's own, live till its close; the tile,
    // page and slot are one each, `pages` and `slots` two each — `bytes`
    // outlives every copy told of.
    unsafe {
        let engine = gpu_engine_open_first();
        assert!(!engine.is_null(), "{}", last_error());
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        assert_eq!(gpu_engine_pool_store(pool, engine, cel, tiles.as_ptr(), 1, &mut page, &mut slot, read, 201), 1);
        assert_eq!(done_here(&*engine), Ok(()));
        assert_eq!(gpu_engine_pool_unwritten(pool, pages.as_mut_ptr(), slots.as_mut_ptr(), 2), 0, "⛔premise");
        gpu_engine_lose(engine, false);
        assert_eq!(gpu_engine_pool_store(pool, engine, cel, tiles.as_ptr(), 1, &mut page, &mut slot, read, 202), 1);
        assert!(done_here(&*engine).is_err(), "the next done is told");
        assert_eq!(was_read(202), Some(false));
        assert_eq!(gpu_engine_pool_unwritten(pool, pages.as_mut_ptr(), slots.as_mut_ptr(), 2), 1);
        assert_eq!((pages[0], slots[0]), (page, slot));
        assert_eq!(gpu_engine_pool_unwritten(pool, pages.as_mut_ptr(), slots.as_mut_ptr(), 2), 0, "taken once");
        gpu_engine_pool_free(pool);
        gpu_engine_close(engine);
    }
}

/// Stores `count` tiles of `bytes` each through the C ABI, as the app's
/// ledger does, waiting for none of it: how many it gave a slot.
///
/// # Safety
/// `pool` and `engine` are live, the pool made on `engine`; `bytes` is a
/// tile's and stays alive till the engine's thread has read it — by the
/// caller's next done.
unsafe fn stored_now(pool: *mut Pool, engine: *const Engine, cel: u32, bytes: &[u8], count: usize) -> usize {
    use super::gpu_engine_pool_store;
    let tiles = vec![bytes.as_ptr(); count];
    let (mut pages, mut slots) = (vec![u16::MAX; count], vec![u16::MAX; count]);
    // SAFETY: see the function's contract; `tiles`, `pages` and `slots`
    // hold `count` each.
    unsafe {
        gpu_engine_pool_store(pool, engine, cel, tiles.as_ptr(), count, pages.as_mut_ptr(), slots.as_mut_ptr(), told_nothing, 0)
    }
}

/// [`stored_now`], then a done and a turn of the pages' thread: the
/// engine's thread has run the copy the store handed it, and the pages'
/// thread a page it asked for ahead.
///
/// # Safety
/// As [`stored_now`]'s.
unsafe fn stored_and_done(pool: *mut Pool, engine: *const Engine, cel: u32, bytes: &[u8], count: usize) -> usize {
    use crate::testing::done_here;
    // SAFETY: see the function's contract.
    let (stored, engine) = unsafe { (stored_now(pool, engine, cel, bytes, count), &*engine) };
    assert_eq!(done_here(engine), Ok(()));
    engine.on_pages_thread(|| ());
    stored
}

/// Where a pool's page made ahead stands, by name.
///
/// # Safety
/// `pool` is live.
pub(super) unsafe fn ahead(pool: *const Pool) -> &'static str {
    // SAFETY: see the function's contract.
    let held = unsafe { &*pool }.ahead.held();
    match &*held {
        Ahead::Unasked => "unasked",
        Ahead::Making => "making",
        Ahead::Made(..) => "made",
        Ahead::Refused(_) => "refused",
    }
}

// A page is made ahead once less than half a page is free, and the store
// that needs it takes it while the engine's thread stands still: no wait
// for it there ([`Pool::make_a_page_ahead`]).
#[test]
fn a_store_takes_the_page_made_ahead_while_the_engines_thread_stands_still() {
    use super::{gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_new};
    use crate::device::{gpu_engine_close, gpu_engine_open_first, gpu_engine_stand_still};
    use crate::testing::{a_device_of_its_own, done_here, last_error};
    let _turn = a_device_of_its_own();
    let bytes = le_bytes(&tile(9));
    // SAFETY: the engine is this test's own, live till its close; each
    // store's copy has read `bytes` by the done after it.
    unsafe {
        let engine = gpu_engine_open_first();
        assert!(!engine.is_null(), "{}", last_error());
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        let slots = (*pool).slots();
        let half = slots / 2;
        assert_eq!(stored_and_done(pool, engine, cel, &bytes, half), half);
        assert_eq!(ahead(pool), "unasked", "half a page free, none is made ahead");
        assert_eq!(stored_and_done(pool, engine, cel, &bytes, 1), 1);
        assert_eq!(ahead(pool), "made", "less than half free, one is");
        let rest = slots - half - 1;
        assert_eq!(stored_and_done(pool, engine, cel, &bytes, rest), rest);
        assert_eq!((*pool).pages().len(), 1, "premise: a page full");
        gpu_engine_stand_still(engine, 2_000);
        let asked = Instant::now();
        assert_eq!(stored_now(pool, engine, cel, &bytes, 1), 1);
        let told = asked.elapsed();
        assert!(told < Duration::from_millis(1_000), "stored after {told:?}, the thread standing 2 s");
        assert_eq!((*pool).pages().len(), 2, "on the page made ahead");
        assert_eq!(ahead(pool), "unasked", "taken, and a page free ahead of the next");
        assert_eq!(done_here(&*engine), Ok(()));
        gpu_engine_pool_free(pool);
        gpu_engine_close(engine);
    }
}

// A page asked for ahead is made on the pages' thread, not the engine's:
// made while the engine's thread stands still. 🔬Made on the engine's
// thread, it held the UI's waits handed over behind it 48 to 195 ms (card
// a-picture-lay-holds-the-raster-thread, the Surface, 2026-11-16).
#[test]
fn a_page_ahead_is_made_while_the_engines_thread_stands_still() {
    use super::{gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_new};
    use crate::device::{gpu_engine_close, gpu_engine_device_entered_here, gpu_engine_open_first, gpu_engine_stand_still};
    use crate::testing::{a_device_of_its_own, done_here, last_error};
    let _turn = a_device_of_its_own();
    let bytes = le_bytes(&tile(11));
    // SAFETY: the engine is this test's own, live till its close; each
    // store's copy has read `bytes` by the done after it.
    unsafe {
        let engine = gpu_engine_open_first();
        assert!(!engine.is_null(), "{}", last_error());
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        let half = (*pool).slots() / 2;
        assert_eq!(stored_and_done(pool, engine, cel, &bytes, half), half);
        assert_eq!(ahead(pool), "unasked", "premise: half a page free, none asked");
        gpu_engine_stand_still(engine, 2_000);
        let (asked, entered) = (Instant::now(), gpu_engine_device_entered_here());
        assert_eq!(stored_now(pool, engine, cel, &bytes, 1), 1);
        (*engine).on_pages_thread(|| ());
        let made = asked.elapsed();
        assert_eq!(ahead(pool), "made", "made with the engine's thread standing");
        assert!(made < Duration::from_millis(1_000), "made after {made:?}, the engine's thread standing 2 s");
        assert_eq!(gpu_engine_device_entered_here(), entered, "nor on the store's thread (B1-b)");
        assert_eq!(done_here(&*engine), Ok(()));
        gpu_engine_pool_free(pool);
        gpu_engine_close(engine);
    }
}

/// Where the page made ahead of `pictures`' pool stands ([`ahead`]).
fn picture_ahead(pictures: &Pictures) -> &'static str {
    let kept = pictures.kept();
    let pool = kept.pool.as_ref().expect("made by its first picture");
    // SAFETY: the pool is live while it is kept.
    unsafe { ahead(pool) }
}

// The pictures' pool asks for its next page ahead as the cels' does, at the
// one place both ask — [`Pool::fresh`] (관제 2026-11-16 02:58): its pages
// were made where a picture needed one, 48 to 188 ms of the engine's thread
// (the Surface, FNK_02 cut 59 with the onion on).
#[test]
fn the_pictures_pool_makes_its_next_page_ahead_too() {
    let engine = rig().engine;
    let pictures = Pictures::sized(4).expect("pictures");
    let cel = pictures.cel(engine).expect("a picture");
    let (first, _) = pictures.fresh(engine, cel, 2).expect("two slots");
    engine.on_pages_thread(|| ());
    assert_eq!(picture_ahead(&pictures), "unasked", "half a page free, none asked");
    let (second, _) = pictures.fresh(engine, cel, 1).expect("a third");
    engine.on_pages_thread(|| ());
    assert_eq!(picture_ahead(&pictures), "made", "less than half free, one made");
    let (third, pages) = pictures.fresh(engine, cel, 2).expect("past the page");
    assert_eq!(pages.len(), 2, "premise: on a second page");
    assert_eq!(picture_ahead(&pictures), "unasked", "taken: the one made ahead");
    pictures.release(first.into_iter().chain(second).chain(third), std::iter::empty());
}

// A picture's page made ahead is no picture's: the memory census counts it
// among the pictures' idle bytes, and a give-back lets it go first (관제
// 2026-11-16 08:28 ①).
#[test]
fn a_picture_s_page_made_ahead_is_counted_idle_and_given_back_first() {
    let engine = rig().engine;
    let pictures = Pictures::sized(4).expect("pictures");
    let cel = pictures.cel(engine).expect("a picture");
    let (places, _) = pictures.fresh(engine, cel, 3).expect("three slots");
    engine.on_pages_thread(|| ());
    assert_eq!(picture_ahead(&pictures), "made", "premise: one made ahead");
    assert_eq!(pictures.idle_bytes(), (1 + 4) * TILE_BYTES, "the slot free, and the page made ahead");
    pictures.give_back(engine, TILE_BYTES);
    assert_eq!(picture_ahead(&pictures), "unasked", "let go first");
    assert_eq!(pictures.idle_bytes(), TILE_BYTES, "the slot free on the page a picture is on");
    pictures.release(places.into_iter(), std::iter::empty());
}

// A page still being made ahead when the pool is given back is called off,
// not left to come: made on a thread of its own, it would land after the
// give-back and stay, no picture's, past what may stay idle.
#[test]
fn a_page_being_made_ahead_is_called_off_by_a_give_back() {
    let turn = crate::testing::a_device_of_its_own();
    let engine = turn.engine();
    let pictures = Pictures::sized(4).expect("pictures");
    let cel = pictures.cel(&engine).expect("a picture");
    let (first, _) = pictures.fresh(&engine, cel, 1).expect("a slot, on a page made for it");
    let (open, shut) = std::sync::mpsc::channel::<()>();
    engine.pages_posted(move || shut.recv().unwrap_or_default());
    let (rest, _) = pictures.fresh(&engine, cel, 2).expect("two slots more");
    assert_eq!(picture_ahead(&pictures), "making", "premise: asked for, the pages' thread held");
    pictures.give_back(&engine, TILE_BYTES);
    assert_eq!(picture_ahead(&pictures), "unasked", "called off");
    open.send(()).expect("the pages' thread waits");
    engine.on_pages_thread(|| ());
    assert_eq!(picture_ahead(&pictures), "unasked", "made, and let go where it was made");
    assert_eq!(pictures.idle_bytes(), TILE_BYTES, "the slot free on the page a picture is on");
    pictures.release(first.into_iter().chain(rest), std::iter::empty());
}

// A page made apart from wgpu's allocator ([`crate::platform::committed_buffer`])
// is let go with its buffer: once the pool that holds it goes, no hold of
// its resource is left but this test's — no allocator keeps a ledger of it
// (관제 2026-11-16 08:28 ①).
#[cfg(windows)]
#[test]
fn a_page_made_apart_is_let_go_with_its_pool() {
    use wgpu::hal::api::Dx12;
    let engine = rig().engine;
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let cel = pool.cel();
    pool.fresh(engine, cel).expect("a slot");
    // SAFETY: only reads the buffer's resource, holding it once more.
    let resource = unsafe { pool.pages()[0].as_hal::<Dx12>() }
        .map(|page| unsafe { page.raw_resource() }.clone())
        .expect("a D3D12 buffer");
    assert_eq!(holds(&resource), 2, "premise: the page's and this test's");
    drop(pool);
    assert_eq!(engine.wait(), Some(()), "the GPU done, and what was dropped let go");
    assert_eq!(holds(&resource), 1, "this test's alone");
}

// A page is made apart from wgpu's allocator: none of the allocations its
// report names is a pool's page — so its lock, held as a new block of the
// device's memory is made, holds no body of the engine's thread for one
// ([`crate::platform::committed_buffer`] has the Surface's numbers).
#[cfg(windows)]
#[test]
fn a_page_is_made_apart_from_wgpus_allocator() {
    let engine = rig().engine;
    let premise = engine.device().create_buffer(&wgpu::BufferDescriptor {
        label: Some("premise: a buffer of wgpu's own"),
        size: TILE_BYTES,
        usage: wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let cel = pool.cel();
    pool.fresh(engine, cel).expect("a slot");
    let report = engine.device().generate_allocator_report().expect("a D3D12 allocator");
    let named = |name: &str| report.allocations.iter().filter(|made| made.name == name).count();
    assert_eq!(named("premise: a buffer of wgpu's own"), 1, "premise: the report names what it made");
    assert_eq!(named("pool page"), 0, "a page in wgpu's allocator");
    drop(premise);
}

// A buffer made apart is described as wgpu describes one of its own made of
// the same descriptor — its size, its layout, its flags — so a pass binds
// it as it binds wgpu's (브러시/렌더링 2026-11-16 08:32 ②). ⚠️No test sees
// the flag a pass writes through go missing: 🧪without it the passes wrote
// all the same on the Surface's driver, release and debug alike (mutant,
// 2026-11-16) — so it is read off the resource.
#[cfg(windows)]
#[test]
fn a_buffer_made_apart_is_described_as_wgpu_describes_its_own() {
    use wgpu::hal::api::Dx12;
    let engine = rig().engine;
    let described = |buffer: &wgpu::Buffer| {
        // SAFETY: only reads the buffer's resource's description.
        unsafe { buffer.as_hal::<Dx12>() }.map(|made| unsafe { made.raw_resource().GetDesc() }).expect("a D3D12 buffer")
    };
    let page = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC;
    for usage in [page, wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC] {
        let desc = wgpu::BufferDescriptor { label: Some("a buffer described"), size: 4 * TILE_BYTES, usage, mapped_at_creation: false };
        let apart = crate::platform::committed_buffer(engine.device(), &desc).expect("made apart");
        let wgpu_s = engine.device().create_buffer(&desc);
        assert_eq!(described(&apart), described(&wgpu_s), "{usage:?}");
    }
}

// A page a store waits for — none made ahead — is made on the pages'
// thread too: the store is answered while the engine's thread stands still.
#[test]
fn a_page_a_store_waits_for_is_made_while_the_engines_thread_stands_still() {
    use super::{gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_new};
    use crate::device::{gpu_engine_close, gpu_engine_device_entered_here, gpu_engine_open_first, gpu_engine_stand_still};
    use crate::testing::{a_device_of_its_own, done_here, last_error};
    let _turn = a_device_of_its_own();
    let bytes = le_bytes(&tile(12));
    // SAFETY: the engine is this test's own, live till its close; the
    // store's copy has read `bytes` by the done after it.
    unsafe {
        let engine = gpu_engine_open_first();
        assert!(!engine.is_null(), "{}", last_error());
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        assert!((*pool).pages().is_empty(), "premise: no page made, none ahead");
        gpu_engine_stand_still(engine, 2_000);
        let (asked, entered) = (Instant::now(), gpu_engine_device_entered_here());
        assert_eq!(stored_now(pool, engine, cel, &bytes, 1), 1);
        let told = asked.elapsed();
        assert!(told < Duration::from_millis(1_000), "stored after {told:?}, the engine's thread standing 2 s");
        assert_eq!((*pool).pages().len(), 1, "on a page made for it");
        assert_eq!(gpu_engine_device_entered_here(), entered, "made off the store's thread (B1-b)");
        assert_eq!(done_here(&*engine), Ok(()));
        gpu_engine_pool_free(pool);
        gpu_engine_close(engine);
    }
}

/// How many hold `resource`, read by one more hold let go.
#[cfg(windows)]
fn holds(resource: &windows::Win32::Graphics::Direct3D12::ID3D12Resource) -> u32 {
    use windows::core::Interface;
    let raw = resource.as_raw();
    // SAFETY: a live COM object, held once more and let go of once.
    unsafe {
        let vtable = *(raw as *const *const windows::core::IUnknown_Vtbl);
        ((*vtable).AddRef)(raw);
        ((*vtable).Release)(raw)
    }
}

// None is made ahead past the bytes a pool may make, and one made goes once
// the pool may make no page more: at the next store, and at the store it is
// full for.
#[test]
fn a_page_ahead_is_made_within_the_bytes_a_pool_may_make_and_goes_past_them() {
    use super::{gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_most_bytes, gpu_engine_pool_new};
    use crate::device::{gpu_engine_close, gpu_engine_open_first};
    use crate::testing::{a_device_of_its_own, done_here, last_error};
    let _turn = a_device_of_its_own();
    let bytes = le_bytes(&tile(10));
    // SAFETY: the engine is this test's own, live till its close; each
    // store's copy has read `bytes` by the done after it.
    unsafe {
        let engine = gpu_engine_open_first();
        assert!(!engine.is_null(), "{}", last_error());
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        let slots = (*pool).slots();
        let page = slots as u64 * TILE_BYTES;
        gpu_engine_pool_most_bytes(pool, page);
        let past_half = slots / 2 + 1;
        assert_eq!(stored_and_done(pool, engine, cel, &bytes, past_half), past_half);
        assert_eq!(ahead(pool), "unasked", "a page the most, none ahead of a second");
        gpu_engine_pool_most_bytes(pool, 2 * page);
        assert_eq!(stored_and_done(pool, engine, cel, &bytes, 1), 1);
        assert_eq!(ahead(pool), "made", "room for a second, one made ahead");
        gpu_engine_pool_most_bytes(pool, page);
        assert_eq!(stored_now(pool, engine, cel, &bytes, 1), 1);
        assert_eq!(ahead(pool), "unasked", "no room for it, the next store lets it go");
        gpu_engine_pool_most_bytes(pool, 2 * page);
        assert_eq!(stored_and_done(pool, engine, cel, &bytes, 1), 1);
        assert_eq!(ahead(pool), "made", "premise: made again");
        let rest = slots - past_half - 3;
        assert_eq!(stored_and_done(pool, engine, cel, &bytes, rest), rest);
        gpu_engine_pool_most_bytes(pool, page);
        assert_eq!(stored_now(pool, engine, cel, &bytes, 1), 0, "full at a page");
        assert_eq!(ahead(pool), "unasked", "and the store it is full for lets it go");
        assert_eq!((*pool).bytes(), page);
        assert_eq!(done_here(&*engine), Ok(()));
        gpu_engine_pool_free(pool);
        gpu_engine_close(engine);
    }
}

// A page made ahead against one budget is not taken where the pool keeps
// to another: kept to none, it makes no page, and the one made ahead goes.
#[test]
fn a_page_made_ahead_against_another_budget_is_not_taken() {
    use super::{gpu_engine_pool_budget_instead, gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_new};
    use crate::device::{gpu_engine_close, gpu_engine_open_first};
    use crate::testing::{a_device_of_its_own, done_here, last_error};
    let _turn = a_device_of_its_own();
    let bytes = le_bytes(&tile(11));
    // SAFETY: the engine is this test's own, live till its close; each
    // store's copy has read `bytes` by the done after it.
    unsafe {
        let engine = gpu_engine_open_first();
        assert!(!engine.is_null(), "{}", last_error());
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        let slots = (*pool).slots();
        let past_half = slots / 2 + 1;
        assert_eq!(stored_and_done(pool, engine, cel, &bytes, past_half), past_half);
        assert_eq!(ahead(pool), "made", "premise");
        gpu_engine_pool_budget_instead(pool, 0);
        let rest = slots - past_half;
        assert_eq!(stored_and_done(pool, engine, cel, &bytes, rest), rest);
        assert_eq!(stored_and_done(pool, engine, cel, &bytes, 1), 0, "kept to nothing, no page");
        assert_eq!(ahead(pool), "unasked", "the page made ahead gone");
        assert_eq!((*pool).pages().len(), 1);
        assert_eq!(done_here(&*engine), Ok(()));
        gpu_engine_pool_free(pool);
        gpu_engine_close(engine);
    }
}

// A page the budget refuses ahead is not asked for again till the pool's
// bytes or the budget kept to move.
#[test]
fn a_page_refused_ahead_is_not_asked_again_till_the_budget_moves() {
    use super::{gpu_engine_pool_budget_instead, gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_new};
    use crate::device::{gpu_engine_close, gpu_engine_open_first, gpu_engine_stand_still};
    use crate::testing::{a_device_of_its_own, done_here, last_error};
    let _turn = a_device_of_its_own();
    let bytes = le_bytes(&tile(12));
    // SAFETY: the engine is this test's own, live till its close; each
    // store's copy has read `bytes` by the done after it.
    unsafe {
        let engine = gpu_engine_open_first();
        assert!(!engine.is_null(), "{}", last_error());
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        let half = (*pool).slots() / 2;
        assert_eq!(stored_and_done(pool, engine, cel, &bytes, half), half);
        gpu_engine_pool_budget_instead(pool, 0);
        assert_eq!(stored_and_done(pool, engine, cel, &bytes, 1), 1);
        assert_eq!(ahead(pool), "refused", "kept to nothing");
        gpu_engine_stand_still(engine, 2_000);
        // 🚨Where the page stands is read by the order of the pages'
        // thread, never by the clock: held, a page asked for is being
        // made for as long as this looks — one asked for where none is to
        // be, too —, and it is made once a turn of that thread is
        // through. ↩️Till 2026-11-19 read "making" right after the store
        // and "made" after a done — the engine's thread's, which makes no
        // page: a crowded debug run read "making" there (card
        // a-page-ahead-test-reads-making-under-load).
        let (open, shut) = std::sync::mpsc::channel::<()>();
        (*engine).pages_posted(move || shut.recv().unwrap_or_default());
        assert_eq!(stored_now(pool, engine, cel, &bytes, 1), 1);
        assert_eq!(ahead(pool), "refused", "not asked again as it stands");
        gpu_engine_pool_budget_instead(pool, i64::MAX);
        assert_eq!(stored_now(pool, engine, cel, &bytes, 1), 1);
        assert_eq!(ahead(pool), "making", "asked again once the budget moved");
        open.send(()).expect("the pages' thread waits");
        assert_eq!(done_here(&*engine), Ok(()));
        (*engine).on_pages_thread(|| ());
        assert_eq!(ahead(pool), "made");
        gpu_engine_pool_free(pool);
        gpu_engine_close(engine);
    }
}

// A store's give-back lets the page made ahead go first: where the pages
// with it would pass the bytes asked for, and not where they keep within.
#[test]
fn a_give_back_lets_the_page_made_ahead_go_past_the_bytes_asked_for() {
    use super::{gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_give_back, gpu_engine_pool_new};
    use crate::device::{gpu_engine_close, gpu_engine_open_first};
    use crate::testing::{a_device_of_its_own, done_here, last_error};
    let _turn = a_device_of_its_own();
    let bytes = le_bytes(&tile(13));
    // SAFETY: the engine is this test's own, live till its close; each
    // store's copy has read `bytes` by the done after it.
    unsafe {
        let engine = gpu_engine_open_first();
        assert!(!engine.is_null(), "{}", last_error());
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        let slots = (*pool).slots();
        let page = slots as u64 * TILE_BYTES;
        let past_half = slots / 2 + 1;
        assert_eq!(stored_and_done(pool, engine, cel, &bytes, past_half), past_half);
        assert_eq!(ahead(pool), "made", "premise");
        gpu_engine_pool_give_back(pool, engine, 2 * page);
        assert_eq!(ahead(pool), "made", "the pages with it keep within two");
        gpu_engine_pool_give_back(pool, engine, 2 * page - 1);
        assert_eq!(ahead(pool), "unasked", "past them, it goes");
        assert_eq!((*pool).pages().len(), 1, "the page its tiles hold stays");
        assert_eq!(done_here(&*engine), Ok(()));
        gpu_engine_pool_free(pool);
        gpu_engine_close(engine);
    }
}

// A page made ahead is counted on its own, not among the pages a store
// took: the census reads both, the budget the pages alone
// ([`Pool::ahead_bytes`]) — and once taken it is counted once, a page.
#[test]
fn a_page_made_ahead_is_counted_apart_from_the_pages_taken() {
    use super::{
        gpu_engine_pool_ahead_bytes, gpu_engine_pool_bytes, gpu_engine_pool_cel, gpu_engine_pool_free,
        gpu_engine_pool_new,
    };
    use crate::device::{gpu_engine_close, gpu_engine_open_first};
    use crate::testing::{a_device_of_its_own, done_here, last_error};
    let _turn = a_device_of_its_own();
    let bytes = le_bytes(&tile(14));
    // SAFETY: the engine is this test's own, live till its close; each
    // store's copy has read `bytes` by the done after it.
    unsafe {
        let engine = gpu_engine_open_first();
        assert!(!engine.is_null(), "{}", last_error());
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        let slots = (*pool).slots();
        let page = slots as u64 * TILE_BYTES;
        let half = slots / 2;
        assert_eq!(stored_and_done(pool, engine, cel, &bytes, half), half);
        assert_eq!(gpu_engine_pool_ahead_bytes(pool), 0, "none made ahead");
        assert_eq!(stored_and_done(pool, engine, cel, &bytes, 1), 1);
        assert_eq!(ahead(pool), "made", "premise");
        assert_eq!(gpu_engine_pool_ahead_bytes(pool), page, "the page made ahead");
        assert_eq!(gpu_engine_pool_bytes(pool), page, "and the page taken, alone");
        let into_the_next = slots - half;
        assert_eq!(stored_and_done(pool, engine, cel, &bytes, into_the_next), into_the_next);
        assert_eq!(gpu_engine_pool_bytes(pool), 2 * page, "premise: the page made ahead taken");
        assert_eq!(gpu_engine_pool_ahead_bytes(pool), 0, "counted once, among the pages");
        assert_eq!(done_here(&*engine), Ok(()));
        gpu_engine_pool_free(pool);
        gpu_engine_close(engine);
    }
}

// The pool folds its tiles at its caller's word (`gpu_engine_pool_fold`,
// `gpu_engine_pool_settle`): those next to fold, each read behind the
// store handed over before its fold — the engine's thread held as both
// were —, their page made on the pages' thread before the fold is told
// and taken by a settle that waits for no thread; a fold whose tile the
// page made holds asks for none; and with no tile left nothing is handed
// over, and what reads the tiles by their names reads what was stored —
// their page of tiles away by then, no tile lying on it. A pool of three
// tiles a page, which the three fill: a page with a slot free is the
// pool's room, and none of its tiles is a fold's.
#[test]
fn a_pool_folds_its_tiles_at_its_callers_word_and_its_thread_waits_for_no_page() {
    use super::folded_tests::{numbered, tile as coloured, told, told_within};
    use super::{
        gpu_engine_pool_bytes, gpu_engine_pool_cel, gpu_engine_pool_fold, gpu_engine_pool_free, gpu_engine_pool_read,
        gpu_engine_pool_settle,
    };
    use crate::device::{gpu_engine_close, gpu_engine_open_first, gpu_engine_waits_here};
    use crate::kernels::fold::{gpu_engine_fold_free, gpu_engine_fold_new};
    use crate::testing::{a_device_of_its_own, done_here, last_error};
    let _turn = a_device_of_its_own();
    let (bytes, long) = (coloured(7, 2), Duration::from_secs(120));
    // A thread held till its test lets it go — a minute at most, so a wait
    // for it that should not be fails the test, and hangs nothing.
    let held = || {
        let (open, shut) = std::sync::mpsc::channel::<()>();
        (open, move || shut.recv_timeout(Duration::from_secs(60)).ok())
    };
    // SAFETY: the engine is this test's own, live till its close; the
    // store's copy has read `bytes` by the fold told behind it.
    unsafe {
        let engine = gpu_engine_open_first();
        assert!(!engine.is_null(), "{}", last_error());
        let (pool, page) = ((*engine).hands(Pool::sized(3, MOST_NAMED, u64::MAX).expect("pool")), 3 * TILE_BYTES);
        let cel = gpu_engine_pool_cel(pool);
        let fold = gpu_engine_fold_new(engine);
        assert!(!fold.is_null(), "{}", last_error());
        let waits = gpu_engine_waits_here();
        // The engine's thread held: the store's copy and the fold are
        // handed over behind it, in that order, no tile written as the
        // fold is asked.
        let (go, wait) = held();
        (*engine).posted(wait);
        assert_eq!(stored_now(pool, engine, cel, &bytes, 3), 3);
        // The page of tiles the store asked for ahead, its own full, is
        // made by here.
        (*engine).on_pages_thread(|| ());
        let ahead = (*pool).ahead_bytes();
        let first = numbered();
        assert_eq!(gpu_engine_pool_fold(pool, engine, fold, 2, told, first), 2);
        // The pages' thread held: the fold, once run, is not told till the
        // page it asks for is made.
        let (open, wait) = held();
        (*engine).pages_posted(move || wait().unwrap_or_default());
        go.send(()).expect("the engine's thread waits");
        assert_eq!(told_within(first, Duration::from_millis(500)), None, "told before its page was made");
        assert_eq!(((*pool).pages().len(), (*pool).ahead_bytes()), (1, ahead));
        open.send(()).expect("the pages' thread waits");
        assert_eq!(told_within(first, long), Some(true));
        assert_eq!(((*pool).pages().len(), (*pool).ahead_bytes()), (1, ahead + page));
        // A settle goes through with the pages' thread held: it takes the
        // page made, and waits for none.
        let (open, wait) = held();
        (*engine).pages_posted(move || wait().unwrap_or_default());
        let began = Instant::now();
        assert_eq!(gpu_engine_pool_settle(pool, engine), 2);
        assert!(began.elapsed() < Duration::from_secs(30), "the settle waited for the pages' thread");
        assert_eq!(((*pool).pages().len(), (*pool).ahead_bytes()), (2, ahead));
        assert_eq!(gpu_engine_pool_bytes(pool), 2 * page, "the third tile lies on its page still");
        // The third tile's run is on the page made: no page is asked for,
        // and its fold is told with the pages' thread held still.
        let second = numbered();
        assert_eq!(gpu_engine_pool_fold(pool, engine, fold, 2, told, second), 1);
        assert_eq!(told_within(second, long), Some(true));
        // Its page of tiles gives its buffer back with the pages' thread
        // held still: the settle waits for no page let go.
        assert_eq!(gpu_engine_pool_settle(pool, engine), 1);
        assert_eq!(((*pool).pages().len(), (*pool).ahead_bytes()), (2, ahead));
        assert_eq!(gpu_engine_pool_bytes(pool), page, "no tile lies on the page of tiles");
        open.send(()).expect("the pages' thread waits");
        assert_eq!(gpu_engine_pool_fold(pool, engine, fold, 2, told, numbered()), 0);
        assert_eq!(gpu_engine_pool_settle(pool, engine), 0);
        // No thread of the two waited for the GPU: not this one, nor the
        // engine's under a fold — what a body handed over waits there
        // is counted here once it has run, as every one has behind a
        // job this thread waited for.
        (*engine).on_thread(|| ());
        assert_eq!(gpu_engine_waits_here(), waits, "a thread waited for the GPU under a fold");
        let places = [at(0, 0), at(0, 1), at(0, 2)];
        assert!(places.iter().all(|&at| (*pool).lies(at).slot & FOLDED != 0));
        let words: Vec<u32> = places.iter().map(|at| at.word()).collect();
        let mut read = vec![0; 3 * TILE_BYTES as usize];
        assert!(gpu_engine_pool_read(pool, engine, words.as_ptr(), 3, read.as_mut_ptr()), "{}", last_error());
        assert!(read == bytes.repeat(3), "a tile folded before its store's copy was written");
        assert_eq!(done_here(&*engine), Ok(()));
        gpu_engine_fold_free(fold);
        gpu_engine_pool_free(pool);
        gpu_engine_close(engine);
    }
}

// A fold the device refuses is told so and leaves its tiles as they are,
// a fold's to take again once it is settled: none lies folded, and the
// next fold is handed the same tiles.
#[test]
fn a_fold_the_device_refuses_leaves_its_tiles_a_fold_s_to_take_again() {
    use super::folded_tests::{numbered, tile as coloured, told, told_within};
    use super::{gpu_engine_pool_cel, gpu_engine_pool_fold, gpu_engine_pool_free, gpu_engine_pool_settle};
    use crate::device::{gpu_engine_close, gpu_engine_lose, gpu_engine_open_first};
    use crate::kernels::fold::{gpu_engine_fold_free, gpu_engine_fold_new};
    use crate::testing::{a_device_of_its_own, done_here, last_error};
    let _turn = a_device_of_its_own();
    let (bytes, long) = (coloured(7, 2), Duration::from_secs(120));
    let places = [at(0, 0), at(0, 1)];
    // SAFETY: the engine is this test's own, live till its close; the
    // store's copy has read `bytes` by the done behind it.
    unsafe {
        let engine = gpu_engine_open_first();
        assert!(!engine.is_null(), "{}", last_error());
        // A page the two fill: one with a slot free is the pool's room.
        let pool = (*engine).hands(Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool"));
        let cel = gpu_engine_pool_cel(pool);
        let fold = gpu_engine_fold_new(engine);
        assert!(!fold.is_null(), "{}", last_error());
        assert_eq!(stored_now(pool, engine, cel, &bytes, 2), 2);
        assert_eq!(done_here(&*engine), Ok(()));
        gpu_engine_lose(engine, false);
        for _ in 0..2 {
            let number = numbered();
            assert_eq!(gpu_engine_pool_fold(pool, engine, fold, 2, told, number), 2);
            assert_eq!(told_within(number, long), Some(false));
            assert!((*pool).to_fold(usize::MAX).is_empty(), "in a fold's hand till it is settled");
            assert_eq!(gpu_engine_pool_settle(pool, engine), 0);
            assert_eq!((*pool).to_fold(usize::MAX), places);
        }
        assert!(places.iter().all(|&at| (*pool).lies(at) == at));
        gpu_engine_fold_free(fold);
        gpu_engine_pool_free(pool);
        gpu_engine_close(engine);
    }
}

// The slots free on a page away are no room: the page made ahead is asked
// for by the slots free on the pages made alone.
#[test]
fn the_page_made_ahead_counts_no_slot_of_a_page_away() {
    use super::folded_tests::{settled, tile as coloured};
    let engine = rig().engine;
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let (cel, a) = (pool.cel(), coloured(1, 2));
    let places = pool.store(engine, cel, &[&a[..]; 4]).expect("store");
    // The page its tiles fill, away with them settled, and three of its
    // slots let go: free, and no tile's to take.
    assert_eq!(settled(&mut pool, &places), 4);
    for &at in &places[1..] {
        pool.release(at).expect("release");
    }
    // The page made ahead of the first store is taken by the next, three
    // slots of it free: none is asked for.
    engine.on_pages_thread(|| ());
    let next = pool.cel();
    assert_eq!(pool.fresh(engine, next), Ok(at(2, 0)));
    engine.on_pages_thread(|| ());
    // SAFETY: the pool is live.
    assert_eq!(unsafe { ahead(&pool) }, "unasked");
    // One slot free of the four made: a page is asked for ahead, whatever
    // is free on the page away.
    assert_eq!(pool.fresh(engine, next), Ok(at(2, 1)));
    assert_eq!(pool.fresh(engine, next), Ok(at(2, 2)));
    engine.on_pages_thread(|| ());
    // SAFETY: the pool is live.
    assert_eq!(unsafe { ahead(&pool) }, "made");
}

// A page made ahead is taken whatever the pool's pages did since it was
// asked for — a page of folded tiles taken by a settle, here — and its
// taker waits for no thread: the budget kept to is what it was asked
// against, and the pool's bytes as they stood are a refusal's alone.
#[test]
fn a_page_made_ahead_is_taken_though_the_pool_s_bytes_moved_since() {
    use super::folded_tests::{numbered, tile as coloured, told, told_within};
    use crate::kernels::fold::Fold;
    let turn = crate::testing::a_device_of_its_own();
    let engine = turn.engine();
    let fold = engine.on_thread(|| Fold::new(&engine)).expect("the fold's kernels");
    let mut pool = Pool::sized(3, MOST_NAMED, u64::MAX).expect("pool");
    let (cel, a) = (pool.cel(), coloured(1, 2));
    // Two tiles of a page of three: the next page is asked for ahead.
    let places = pool.store(&engine, cel, &[&a[..]; 2]).expect("store");
    engine.on_pages_thread(|| ());
    // SAFETY: the pool is live.
    assert_eq!(unsafe { ahead(&pool) }, "made", "premise");
    let asked_at = pool.bytes();
    let number = numbered();
    // SAFETY: the kernels are let go after the fold is told, and `told`
    // is any thread's to call.
    assert_eq!(unsafe { pool.folds_unwaited(&engine, &fold, &places, (told, number)) }, 2);
    assert_eq!(told_within(number, Duration::from_secs(120)), Some(true));
    assert_eq!(pool.settles_unwaited(&engine), 2);
    assert_ne!(pool.bytes(), asked_at, "premise: a page of folded tiles taken since");
    // The pages' thread held: the tile past the page's last slot takes
    // the page made ahead, and waits for none.
    let (open, shut) = std::sync::mpsc::channel::<()>();
    engine.pages_posted(move || shut.recv_timeout(Duration::from_secs(60)).unwrap_or_default());
    assert_eq!(pool.fresh(&engine, cel), Ok(at(0, 2)));
    let began = Instant::now();
    assert_eq!(pool.fresh(&engine, cel), Ok(at(2, 0)));
    assert!(began.elapsed() < Duration::from_secs(30), "its taker waited for the pages' thread");
    open.send(()).expect("the pages' thread waits");
}

// A pool is made of pages as large as it is asked for, the app's where
// that is past what the pool makes one — and of none that holds no tile.
#[test]
fn a_pool_is_made_of_pages_no_larger_than_asked() {
    use super::{gpu_engine_pool_free, gpu_engine_pool_new};
    use crate::testing::last_error;
    let engine = rig().engine;
    let app_s =Pool::new(engine, u64::MAX).expect("pool").slots();
    assert!(app_s > 3, "premise: a device whose binding holds more than three tiles");
    // SAFETY: the engine is the tests' own, alive for the run; each pool
    // is freed once asked.
    unsafe {
        for (asked, slots) in [(u64::MAX, app_s), (3 * TILE_BYTES, 3), (4 * TILE_BYTES - 1, 3), (TILE_BYTES, 1)] {
            let pool = gpu_engine_pool_new(engine, asked, u64::MAX);
            assert_eq!((*pool).slots(), slots, "asked for {asked}");
            gpu_engine_pool_free(pool);
        }
        assert!(gpu_engine_pool_new(engine, TILE_BYTES - 1, u64::MAX).is_null());
    }
    assert!(last_error().contains("a page of 0 tiles"), "{}", last_error());
}

// What a pool lets go of its pages goes on the pages' thread, its caller
// waiting for none of it: held, that thread has dropped nothing by the
// time the caller goes on, and it is the one that drops it.
#[test]
fn what_a_pool_lets_go_is_dropped_on_the_pages_thread_and_waited_for_by_none() {
    use super::let_go_on_the_pages_thread;
    struct Told(std::sync::Arc<Mutex<Option<ThreadId>>>);
    impl Drop for Told {
        fn drop(&mut self) {
            *self.0.lock().expect("told") = Some(std::thread::current().id());
        }
    }
    let turn = crate::testing::a_device_of_its_own();
    let engine = turn.engine();
    let dropped = std::sync::Arc::new(Mutex::new(None));
    let (open, shut) = std::sync::mpsc::channel::<()>();
    engine.pages_posted(move || shut.recv_timeout(Duration::from_secs(60)).unwrap_or_default());
    let began = Instant::now();
    let_go_on_the_pages_thread(&engine, Some(Told(dropped.clone())));
    let_go_on_the_pages_thread(&engine, None::<Told>);
    assert!(began.elapsed() < Duration::from_secs(30), "its caller waited for the pages' thread");
    assert_eq!(*dropped.lock().expect("told"), None, "dropped where it was let go");
    open.send(()).expect("the pages' thread waits");
    let pages = engine.on_pages_thread(|| std::thread::current().id());
    assert_eq!(*dropped.lock().expect("told"), Some(pages));
}
