//! The pool on a real GPU: a cel's tiles go to its own pages first and a
//! page is made only where none has room, a slot is handed out again only
//! once none holds it — the one released last first —, the pages nobody
//! holds are given back where its store asks, and the pages are what the
//! write path copies to, a pass reads and a readback reads.

use std::sync::{Condvar, Mutex};
use std::thread::ThreadId;
use std::time::Duration;

use super::{Full, MOST_NAMED, Pictures, Pool};
use crate::kernels::blend::mode::NORMAL;
use crate::kernels::composite::tests::{Rig, mix, rig, row, with_map};
use crate::kernels::composite::{
    Budget, NO_EDGE, Plan, TILE, TILE_BYTES, TILE_TEXELS, TileAt, TileSet, WHOLE,
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
    // A page has as many slots as a u16 names, and at least one.
    let named = usize::from(u16::MAX) + 1;
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
    let pool = Pool::sized(2, MOST_NAMED, page).expect("pool");
    let said = |used, budget| Some(VideoMemory { used, budget });
    assert!(pool.fits(said(10, Some(10 + page)), page));
    assert!(!pool.fits(said(11, Some(10 + page)), page));
    assert!(!pool.fits(said(u64::MAX, Some(u64::MAX)), page), "a sum past a u64 is past any budget");
    assert!(pool.fits(said(u64::MAX, None), page));
    assert!(pool.fits(None, page));
    let small = Pool::sized(2, MOST_NAMED, page - 1).expect("pool");
    assert!(!small.fits(None, page));
    assert!(small.fits(said(10, Some(10 + page - TILE_BYTES)), page - TILE_BYTES), "grown by less");
}

// A budget kept to in the OS's place is the bound in it — below what the OS
// says or past it —, and the OS's is again once none is kept to.
#[test]
fn a_budget_kept_to_instead_stands_in_the_os_s_place() {
    let page = 2 * TILE_BYTES;
    let mut kept = Pool::sized(2, MOST_NAMED, page).expect("pool");
    let said = |used, budget| Some(VideoMemory { used, budget });
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
    assert_eq!(pool.pages()[0].size(), TILE_BYTES, "the one before it a stand-in");
    assert_eq!(pool.bytes(), page + TILE_BYTES);
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
    assert_eq!(pool.pages()[1].size(), TILE_BYTES);
    assert_eq!(pool.bytes(), 2 * page + TILE_BYTES);
    for &at in &places[2] {
        pool.release(at).expect("release");
    }
    pool.give_back(engine, 2 * page);
    assert_eq!(pool.pages().len(), 1, "the stand-in left last gone with the page past it");
    assert_eq!(pool.bytes(), page);
    pool.give_back(engine, 0);
    assert_eq!(pool.bytes(), page, "a page held stays");
}

// A page given back is made again within the bytes the pool held with it
// made — its stand-in counted out — and past the pages a pool may make: its
// place is named already.
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
    assert_eq!(pool.bytes(), page + TILE_BYTES);
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
        let pool = gpu_engine_pool_new(engine, u64::MAX);
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
        );
        assert_eq!(stored, 2);
        assert_eq!((pages, slots), ([0, 0], [0, 1]));
        assert!(read_back(&*pool, &[at(0, 0), at(0, 1)]) == bytes.concat());
        assert!(gpu_engine_pool_release(pool, 0, 0));
        assert!(!gpu_engine_pool_release(pool, 0, 0), "let go twice");
        let again =
            gpu_engine_pool_store(pool, engine, a, tiles.as_ptr(), 1, pages.as_mut_ptr(), slots.as_mut_ptr());
        assert_eq!((again, pages[0], slots[0]), (1, 0, 0));
        let none = gpu_engine_pool_store(pool, engine, b, tiles.as_ptr(), 0, pages.as_mut_ptr(), slots.as_mut_ptr());
        assert_eq!(none, 0);
        gpu_engine_pool_free(pool);
        gpu_engine_pool_free(std::ptr::null_mut());
        let full = gpu_engine_pool_new(engine, 0);
        let cel = gpu_engine_pool_cel(full);
        let stored =
            gpu_engine_pool_store(full, engine, cel, tiles.as_ptr(), 2, pages.as_mut_ptr(), slots.as_mut_ptr());
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
        let pool = gpu_engine_pool_new(engine, 0);
        let cel = gpu_engine_pool_cel(pool);
        let none =
            gpu_engine_pool_store(pool, engine, cel, tiles.as_ptr(), 1, pages.as_mut_ptr(), slots.as_mut_ptr());
        assert_eq!(none, 0, "given no bytes, it stores none");
        assert_eq!(gpu_engine_pool_bytes(pool), 0);
        gpu_engine_pool_most_bytes(pool, u64::MAX);
        let one =
            gpu_engine_pool_store(pool, engine, cel, tiles.as_ptr(), 1, pages.as_mut_ptr(), slots.as_mut_ptr());
        assert_eq!(one, 1);
        assert_eq!(gpu_engine_pool_bytes(pool), (*pool).slots() as u64 * TILE_BYTES);
        assert!(read_back(&*pool, &[at(pages[0], slots[0])]) == bytes);
        gpu_engine_pool_give_back(pool, engine, 0);
        assert_eq!(gpu_engine_pool_bytes(pool), (*pool).slots() as u64 * TILE_BYTES, "a page held stays");
        assert!(gpu_engine_pool_release(pool, pages[0], slots[0]));
        gpu_engine_pool_give_back(pool, engine, 0);
        assert_eq!(gpu_engine_pool_bytes(pool), 0);
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
        let pool = gpu_engine_pool_new(engine, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        gpu_engine_pool_budget_instead(pool, 0);
        let none =
            gpu_engine_pool_store(pool, engine, cel, tiles.as_ptr(), 1, pages.as_mut_ptr(), slots.as_mut_ptr());
        assert_eq!(none, 0, "kept to nothing, it stores none");
        gpu_engine_pool_budget_instead(pool, i64::MAX);
        let one = gpu_engine_pool_store(pool, engine, cel, tiles.as_ptr(), 1, pages.as_mut_ptr(), slots.as_mut_ptr());
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
    assert_eq!(pool.pages()[0].size(), TILE_BYTES, "its first page given back");
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
        let pool = gpu_engine_pool_new(engine, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        let stored = gpu_engine_pool_store(pool, engine, cel, tiles.as_ptr(), 2, pages.as_mut_ptr(), slots.as_mut_ptr());
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
    extern "C" fn told(wait: u64) {
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
        let pool = gpu_engine_pool_new(engine, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        let (to_pages, to_slots) = (pages.as_mut_ptr(), slots.as_mut_ptr());
        let stored =
            gpu_engine_pool_store(pool, engine, cel, tiles.as_ptr(), 2, to_pages, to_slots);
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
    extern "C" fn told(wait: u64) {
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
        let pool = gpu_engine_pool_new(engine, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        let stored =
            gpu_engine_pool_store(pool, engine, cel, &bytes.as_ptr(), 1, &mut page, &mut slot);
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
    let pictures = Pictures(std::sync::Arc::new(Mutex::new(Some(pool))));
    let cel = pictures.cel(engine).expect("a cel");
    assert!(pictures.fresh(engine, cel, 3).is_none());
    assert!(last_error().contains("makes no page more"), "{}", last_error());
    assert_eq!(pictures.idle_bytes(), 2 * TILE_BYTES, "the two handed out before the refusal");
    let (places, _) = pictures.fresh(engine, cel, 1).expect("a slot");
    let free = at(0, 1 - places[0].slot);
    assert!(pictures.hold(engine, &[places[0], free]).is_none());
    assert!(last_error().contains("is free"), "{}", last_error());
    pictures.release(places.iter().copied());
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
    let said = Some(VideoMemory { used: 11, budget: Some(10) });
    let fits = engine.pictures.with(engine, |pool| Some(pool.fits(said, pool.page_bytes())));
    assert_eq!(fits, Some(true));
}
