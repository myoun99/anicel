//! The pool's folded tiles on a real GPU: a tile folded keeps its name and
//! reads as it was — off the pool, and by a pass laid on where it lies —,
//! its place goes with its last hold, one let go or handed out again
//! before it is settled stays as it is, one that folds to more than a
//! folded tile takes lies whole beside the folded, and the pages of
//! folded tiles are made and filled as the books say — a page's runs
//! first, the books alone —, and the tiles next to fold are the pool's to
//! say: none of its room's. A page of tiles no tile lies on gives its
//! buffer back, its slots the tiles' names still.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Condvar, Mutex, OnceLock};
use std::time::{Duration, Instant};

use super::folded::{Arena, Takes};
use super::{MOST_NAMED, Pool};
use crate::kernels::composite::tests::{Rig, rig};
use crate::device::{Engine, NO_PAGE_BYTES};
use crate::kernels::fold::Fold;
use crate::kernels::composite::{FOLDED, GRANULE_BYTES, NO_TILE, TILE, TILE_BYTES, TileAt, TileSet};
use crate::testing::read_buffer;

fn at(page: u16, slot: u16) -> TileAt {
    TileAt { page, slot }
}

/// A folded place: page `page`, from granule `first`.
fn folded_at(page: u16, first: u16) -> TileAt {
    TileAt { page, slot: FOLDED | first }
}

/// A tile of `seed` whose every 8 × 8 block holds `colours` colours of its
/// own: one folds to its table alone, two to 5 granules, sixteen to 25,
/// and sixty-four — every pixel its own — to more than a folded tile
/// takes.
pub(crate) fn tile(seed: u32, colours: u32) -> Vec<u8> {
    let word = |texel: u32| {
        let (x, y) = (texel % TILE, texel / TILE);
        let (block, pixel) = ((y / 8) * 16 + x / 8, (y % 8) * 8 + x % 8);
        0xff00_0000 | (seed & 0xff) << 16 | block << 6 | pixel % colours
    };
    (0..TILE * TILE).flat_map(|texel| word(texel).to_le_bytes()).collect()
}

/// The granules [`tile`]'s tile of each count of colours takes folded.
const ONE: u16 = 1;
const TWO: u16 = 5;
const SIXTEEN: u16 = 25;

/// What each fold handed over has told, by its number.
static TOLD: Mutex<Vec<(u64, bool)>> = Mutex::new(Vec::new());
static TELLING: Condvar = Condvar::new();
static NUMBERS: AtomicU64 = AtomicU64::new(1);

pub(crate) extern "C" fn told(number: u64, folded: bool) {
    TOLD.lock().unwrap().push((number, folded));
    TELLING.notify_all();
}

/// A number no other fold of the tests is told by.
pub(crate) fn numbered() -> u64 {
    NUMBERS.fetch_add(1, Ordering::Relaxed)
}

/// What the fold handed over under `number` told, waited for no longer
/// than `within`: none where it has not told by then.
pub(crate) fn told_within(number: u64, within: Duration) -> Option<bool> {
    let deadline = Instant::now() + within;
    let mut said = TOLD.lock().unwrap();
    loop {
        if let Some(mine) = said.iter().position(|&(told, _)| told == number) {
            return Some(said.remove(mine).1);
        }
        let left = deadline.checked_duration_since(Instant::now())?;
        said = TELLING.wait_timeout(said, left.min(Duration::from_secs(1))).unwrap().0;
    }
}

/// The fold's kernels on the rig's engine, compiled once for every test
/// and never let go.
fn kernels() -> *const Fold {
    static KERNELS: OnceLock<Fold> = OnceLock::new();
    let engine = rig().engine;
    KERNELS.get_or_init(|| engine.on_thread(|| Fold::new(engine)).expect("the fold's kernels"))
}

/// Hands over a fold of the tiles named at `places`, told by `number`,
/// waiting for none of it: how many it handed over.
fn handed(pool: &mut Pool, places: &[TileAt], number: u64) -> usize {
    // SAFETY: the kernels are never let go, and `told` is any thread's to
    // call.
    unsafe { pool.folds_unwaited(rig().engine, kernels(), places, (told, number)) }
}

/// Hands over a fold of the tiles named at `places` and waits till it is
/// told: how many it handed over, and whether they folded — none where
/// none was handed over.
fn fold(pool: &mut Pool, places: &[TileAt]) -> (usize, Option<bool>) {
    let number = numbered();
    let handed = handed(pool, places, number);
    if handed == 0 {
        return (0, None);
    }
    let told = told_within(number, Duration::from_secs(120));
    assert!(told.is_some(), "the fold was never told");
    (handed, told)
}

/// Folds and settles the pool's tiles as the verbs do — a fold of those
/// next to fold, `most` at most, then its settle, till none is next: how
/// many settled. ⚠️Within as many rounds as no test's pool needs: one
/// whose tiles stay next for ever fails its test, and hangs none.
fn folded_whole(pool: &mut Pool, most: usize) -> usize {
    let mut settled = 0;
    for _ in 0..64 {
        let next = pool.to_fold(most);
        if next.is_empty() {
            return settled;
        }
        assert_eq!(fold(pool, &next), (next.len(), Some(true)));
        settled += pool.settles_unwaited(rig().engine);
    }
    panic!("the pool's tiles are next for ever: {:?}", pool.to_fold(most));
}

/// Folds the tiles named at `places` and settles them: how many settled.
pub(crate) fn settled(pool: &mut Pool, places: &[TileAt]) -> usize {
    assert_eq!(fold(pool, places).1, Some(true));
    pool.settles_unwaited(rig().engine)
}

/// `tiles` stored for a cel of `pool`, in fresh slots.
fn stored(pool: &mut Pool, tiles: &[&Vec<u8>]) -> Vec<TileAt> {
    let (engine, cel) = (rig().engine, pool.cel());
    let tiles: Vec<&[u8]> = tiles.iter().map(|tile| tile.as_slice()).collect();
    pool.store(engine, cel, &tiles).expect("store")
}

/// The bytes of the tiles named at `places`, read off the pool on the
/// engine's thread — behind the copies a settle handed over, as a verb's
/// read is.
fn read(pool: &Pool, places: &[TileAt]) -> Option<Vec<u8>> {
    let engine = rig().engine;
    let mut into = vec![0; places.len() * TILE_BYTES as usize];
    engine.on_thread(|| pool.read(engine, places, &mut into)).map(|()| into)
}

/// What a pass copies of the tiles at `places`, a row of them, laid on the
/// pool's pages on the engine's thread.
fn laid(pool: &Pool, places: &[TileAt]) -> Vec<u8> {
    laid_on(pool.pages(), places)
}

/// [`laid`] on `pages`: a pool's as they were taken.
fn laid_on(pages: &[wgpu::Buffer], places: &[TileAt]) -> Vec<u8> {
    let Rig { engine, composite } = rig();
    let set = TileSet {
        x0: 0,
        y0: 0,
        columns: places.len() as u32,
        rows: 1,
        tiles: places.iter().copied().map(Some).collect(),
    };
    let tiles: Vec<(i32, i32)> = (0..places.len() as i32).map(|column| (column, 0)).collect();
    let copied = engine
        .on_thread(|| composite.copied(engine, pages, &set, &tiles, composite.widest()))
        .expect("copied");
    read_buffer(engine, &copied.out)
}

/// Writes over the slots of the tiles named at `places`, on `engine` —
/// the pool's —: what a slot holds once its tile lies elsewhere is
/// nobody's to read. A slot of a page away is no bytes to write over, and
/// none to read: a place said there is refused (`TileAt::stored_on`).
pub(crate) fn scrubbed(engine: &Engine, pool: &Pool, places: &[TileAt]) {
    let scrub = vec![0xa5; TILE_BYTES as usize];
    let written = engine.on_thread(|| {
        for at in places {
            let (page, slot) = (&pool.pages()[usize::from(at.page)], at.as_it_is().expect("a slot"));
            if page.size() > NO_PAGE_BYTES {
                engine.queue.write_buffer(page, slot, &scrub);
            }
        }
        Some(())
    });
    written.expect("scrubbed");
}

// A page of folded tiles' runs, the books alone: a tile takes the first
// run that holds it — one just as large whole, which is then no run, a
// larger one from its beginning —, and a run let go is one with the free
// runs on either side of it, in its place among them.
#[test]
fn a_run_is_taken_from_the_first_that_holds_it_and_let_go_is_one_with_those_beside_it() {
    let run = Takes::Folded;
    let mut arena = Arena::of(20);
    let taken: Vec<Option<u32>> = [5, 1, 5, 4, 5].iter().map(|&granules| arena.taken(run(granules), 7)).collect();
    assert_eq!(taken, [Some(0), Some(5), Some(6), Some(11), Some(15)]);
    assert_eq!(arena.taken(run(1), 7), None);
    assert_eq!(arena.held_bytes(), 20 * GRANULE_BYTES);
    // A tile's stamp is where it begins, and nowhere once it is let go;
    // nothing is let go where no tile begins.
    assert_eq!((arena.stamps[5], arena.stamps[6], arena.stamps[7]), (7, 7, 0));
    arena.let_go(7);
    assert_eq!(arena.held_bytes(), 20 * GRANULE_BYTES);
    arena.let_go(5);
    assert_eq!((arena.stamps[5], arena.held_bytes()), (0, 19 * GRANULE_BYTES));
    // A run just as large is taken whole, and is no run then.
    assert_eq!(arena.taken(run(1), 8), Some(5));
    assert_eq!(arena.taken(run(1), 8), None);
    // One with the run before it: 11..15 and 15..20 let go, in that
    // order, behind the run 0..5 let go between them.
    arena.let_go(11);
    arena.let_go(0);
    arena.let_go(15);
    assert_eq!(arena.taken(run(9), 8), Some(11));
    // One with the run after it: 11..20 again free, 6..11 let go before
    // it — and the first of two runs that hold a tile is the one taken,
    // from its beginning, what is left of it the next.
    arena.let_go(11);
    arena.let_go(6);
    assert_eq!(arena.taken(run(2), 8), Some(0));
    assert_eq!(arena.taken(run(3), 8), Some(2));
    assert_eq!(arena.taken(run(14), 8), Some(6));
    // One with both: the tile at 5 let go last, between the two.
    arena.let_go(6);
    arena.let_go(2);
    arena.let_go(0);
    arena.let_go(5);
    assert_eq!(arena.held_bytes(), 0);
    assert_eq!(arena.taken(run(20), 8), Some(0));
}

// A tile whole takes a tile's granules from where a slot of the page would
// begin: the first run that holds them from there, however wide it is
// before —, what is left of the run before it and after it free for the
// tiles to come. Let go, its run is one with those beside it, as any.
#[test]
fn a_tile_whole_takes_its_run_from_where_a_slot_begins() {
    let run = Takes::Folded;
    let mut arena = Arena::of(128);
    let taken: Vec<Option<u32>> =
        [10, 32, 22, 32, 32].iter().map(|&granules| arena.taken(run(granules), 7)).collect();
    assert_eq!(taken, [Some(0), Some(10), Some(42), Some(64), Some(96)]);
    // 86 granules free, 10..96, and no slot's 64 among them.
    arena.let_go(10);
    arena.let_go(42);
    arena.let_go(64);
    assert_eq!(arena.taken(Takes::Whole, 8), None);
    // With 96..128 free too, the second slot's — and the run before it
    // free still, for a tile no wider.
    arena.let_go(96);
    assert_eq!(arena.taken(Takes::Whole, 8), Some(64));
    assert_eq!((arena.stamps[64], arena.held_bytes()), (8, (10 + 64) * GRANULE_BYTES));
    assert_eq!(arena.taken(run(55), 9), None);
    assert_eq!(arena.taken(run(54), 9), Some(10));
    assert_eq!(arena.taken(run(1), 9), None);
    arena.let_go(64);
    arena.let_go(10);
    assert_eq!((arena.stamps[64], arena.held_bytes()), (0, 10 * GRANULE_BYTES));
    assert_eq!(arena.taken(run(118), 9), Some(10));
    // What is left after it is the next run: a second tile whole behind
    // the first, and no third.
    let mut arena = Arena::of(192);
    assert_eq!(arena.taken(run(1), 7), Some(0));
    assert_eq!(arena.taken(Takes::Whole, 7), Some(64));
    assert_eq!(arena.taken(Takes::Whole, 7), Some(128));
    assert_eq!(arena.taken(Takes::Whole, 7), None);
    assert_eq!(arena.taken(run(63), 7), Some(1));
    assert_eq!(arena.held_bytes(), 192 * GRANULE_BYTES);
}

// A tile folded keeps the name it was stored under: its slot's book says
// where it lies, a read of the pool by that name hands its bytes as they
// were — unfolded, beside one that stayed as it is —, a pass laid on where
// each lies copies what it copied of the slots, and its stamp is the one
// its name has. One that folds to more than a folded tile takes lies
// whole on that page, where its second slot would begin — a tile as it is
// to whatever reads it, and no name. And their page of tiles, no tile
// lying on it, has given its buffer back: what was taken of the pool
// before reads the slots by a hold of its own, and on the pool as it
// stands a slot is no place.
#[test]
fn a_tile_folded_keeps_its_name_and_reads_as_it_was() {
    let engine = rig().engine;
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let tiles = [tile(1, 1), tile(2, 2), tile(3, 16), tile(4, 64)];
    let places = stored(&mut pool, &tiles.iter().collect::<Vec<_>>());
    assert_eq!(places, [at(0, 0), at(0, 1), at(0, 2), at(0, 3)]);
    let (as_they_were, taken_before) = (laid(&pool, &places), pool.taken());
    assert_eq!(fold(&mut pool, &places), (4, Some(true)));
    // Folded, and no place given: every tile lies in its slot still.
    assert!(places.iter().all(|&at| pool.lies(at) == at));
    assert_eq!(pool.pages().len(), 1);
    assert_eq!(pool.settles_unwaited(engine), 4);
    let lies: Vec<TileAt> = places.iter().map(|&at| pool.lies(at)).collect();
    assert_eq!(lies, [folded_at(1, 0), folded_at(1, ONE), folded_at(1, ONE + TWO), at(1, 1)]);
    assert!(pool.hold(lies[3]).is_none());
    assert!(read(&pool, &lies[3..]).is_none());
    // The page of folded tiles is a page of the pool's, as large as one of
    // tiles here — and the page of tiles is away: the engine's stand-in in
    // its place, none of the pool's bytes, and its slots none.
    assert_eq!(pool.pages().len(), 2);
    assert_eq!((pool.pages()[0].size(), pool.bytes()), (NO_PAGE_BYTES, 4 * TILE_BYTES));
    let lain = u64::from(ONE + TWO + SIXTEEN) * GRANULE_BYTES + TILE_BYTES;
    assert_eq!(pool.idle_bytes(), 4 * TILE_BYTES - lain);
    assert!(read(&pool, &places) == Some(tiles.concat()));
    assert!(read(&pool, &[places[3], places[1]]) == Some([&tiles[3][..], &tiles[1][..]].concat()));
    let taken = pool.lying();
    assert!(places.iter().zip(&lies).all(|(&named, &lies)| taken.of(named) == lies));
    assert!(laid(&pool, &lies) == as_they_were);
    assert!(as_they_were.iter().any(|&byte| byte != 0));
    let stamps = pool.stamps();
    for (&named, &lies) in places.iter().zip(&lies) {
        assert!(stamps.of(named).is_some());
        assert_eq!(stamps.of(lies), stamps.of(named), "{named:?} lies at {lies:?}");
    }
    // What was taken of the pool before says the slots, and holds their
    // page as it was: a plan laid on it reads the tiles there. On the pool
    // as it stands a slot is no place.
    assert!(places.iter().all(|&at| taken_before.lying.of(at) == at));
    assert!(laid_on(&taken_before.pages, &places) == as_they_were);
    assert!(places.iter().all(|at| at.stored_on(pool.pages()).is_none()));
    // A name of no slot of the pool's is its own place: a page laid after
    // the pool's.
    assert_eq!(taken.of(at(7, 5)), at(7, 5));
    assert_eq!(pool.lies(at(7, 5)), at(7, 5));
    // Settled once: nothing is left to settle, and nothing to fold — a
    // tile that lies folded, or whole, is handed to no fold again.
    assert_eq!(pool.settles_unwaited(engine), 0);
    assert_eq!(fold(&mut pool, &places), (0, None));
    assert!(pool.to_fold(usize::MAX).is_empty());
    assert!(read(&pool, &places) == Some(tiles.concat()));
}

// A tile's folded place goes with its last hold: the run is free for the
// next tile folded — the first run that holds it, side by side runs one —,
// and the slot handed out again names a tile that lies in it as it is.
#[test]
fn a_tile_let_go_gives_its_folded_place_back() {
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let (a, b, c, d, e) = (tile(1, 1), tile(2, 2), tile(3, 16), tile(4, 1), tile(5, 2));
    let places = stored(&mut pool, &[&a, &b]);
    assert_eq!(settled(&mut pool, &places), 2);
    assert_eq!(pool.lies(places[1]), folded_at(1, ONE));
    // Held twice, it stays folded till the second lets it go.
    pool.hold(places[0]).expect("hold");
    pool.release(places[0]).expect("release");
    assert_eq!(pool.lies(places[0]), folded_at(1, 0));
    pool.release(places[0]).expect("release");
    assert_eq!(pool.lies(places[0]), places[0]);
    // Its slot again, another tile's: as it is, and read as itself.
    let third = stored(&mut pool, &[&c]);
    assert_eq!(third, [places[0]]);
    assert_eq!(pool.lies(third[0]), third[0]);
    assert!(read(&pool, &third) == Some(c.clone()));
    // Sixteen colours' 25 granules pass the run of one a let go left, and
    // a tile of one colour takes it.
    assert_eq!(settled(&mut pool, &third), 1);
    assert_eq!(pool.lies(third[0]), folded_at(1, ONE + TWO));
    let fourth = stored(&mut pool, &[&d]);
    assert_eq!(settled(&mut pool, &fourth), 1);
    assert_eq!(pool.lies(fourth[0]), folded_at(1, 0));
    // The runs of the two let go, side by side, are one: a tile of both
    // lies from the first.
    pool.release(places[1]).expect("release");
    pool.release(fourth[0]).expect("release");
    let fifth = stored(&mut pool, &[&e, &e]);
    assert_eq!(settled(&mut pool, &fifth), 2);
    assert_eq!(pool.lies(fifth[0]), folded_at(1, 0));
    assert_eq!(pool.lies(fifth[1]), folded_at(1, ONE + TWO + SIXTEEN));
    assert!(read(&pool, &[third[0], fifth[0], fifth[1]]) == Some([&c[..], &e[..], &e[..]].concat()));
}

// A tile whole's place goes with its last hold as a folded one's does: no
// stamp says a tile lies there, and its run is the next tile's that takes
// one — the page made holds it, and no page more is made.
#[test]
fn a_tile_whole_let_go_gives_its_place_back() {
    let mut pool = Pool::sized(3, MOST_NAMED, u64::MAX).expect("pool");
    let (a, b, c) = (tile(1, 1), tile(2, 64), tile(3, 64));
    let places = stored(&mut pool, &[&a, &b]);
    assert_eq!(settled(&mut pool, &places), 2);
    assert_eq!(pool.lies(places[1]), at(1, 1));
    // Two pages of three tiles' bytes — the page of tiles has a slot
    // free, the pool's room, and stays: idle are that slot, and the
    // folded page but for the tile whole and a granule.
    assert_eq!(pool.bytes(), 6 * TILE_BYTES);
    assert_eq!(pool.idle_bytes(), 3 * TILE_BYTES - u64::from(ONE) * GRANULE_BYTES);
    assert!(pool.stamps().of(at(1, 1)).is_some());
    pool.release(places[1]).expect("release");
    assert_eq!(pool.lies(places[1]), places[1]);
    assert!(pool.stamps().of(at(1, 1)).is_none());
    assert_eq!(pool.idle_bytes(), 5 * TILE_BYTES - u64::from(ONE) * GRANULE_BYTES);
    let again = stored(&mut pool, &[&c]);
    assert_eq!(again, [places[1]]);
    assert_eq!(settled(&mut pool, &again), 1);
    assert_eq!(pool.lies(again[0]), at(1, 1));
    assert_eq!(pool.bytes(), 6 * TILE_BYTES, "no page where its run is free again");
    assert!(read(&pool, &[places[0], again[0]]) == Some([&a[..], &c[..]].concat()));
}

// The page a tile whole needs is asked for by the fold that found it to
// fold to more than a folded tile takes: where no run holds a tile from
// a slot's beginning, and none where one does.
#[test]
fn a_fold_asks_for_the_page_a_tile_whole_needs() {
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let tiles = [tile(1, 64), tile(2, 1), tile(3, 64), tile(4, 64)];
    // Alone, on the page its fold asked for: the first slot's place.
    let first = stored(&mut pool, &[&tiles[0]]);
    assert_eq!(settled(&mut pool, &first), 1);
    assert_eq!((pool.lies(first[0]), pool.bytes()), (at(1, 0), 4 * TILE_BYTES));
    // A folded tile behind it, from the second slot's first granule: 63
    // granules are left, and the next tile whole is given a page. The
    // page of tiles the two filled is away by then.
    let second = stored(&mut pool, &[&tiles[1]]);
    assert_eq!(settled(&mut pool, &second), 1);
    assert_eq!(pool.lies(second[0]), folded_at(1, 64));
    let third = stored(&mut pool, &[&tiles[2]]);
    assert_eq!(third, [at(2, 0)]);
    assert_eq!(settled(&mut pool, &third), 1);
    assert_eq!((pool.lies(third[0]), pool.bytes()), (at(3, 0), 6 * TILE_BYTES));
    // The one after finds that page's second slot, and asks for none.
    let fourth = stored(&mut pool, &[&tiles[3]]);
    assert_eq!(settled(&mut pool, &fourth), 1);
    assert_eq!((pool.lies(fourth[0]), pool.bytes()), (at(3, 1), 4 * TILE_BYTES));
    let all = [first[0], second[0], third[0], fourth[0]];
    assert!(read(&pool, &all) == Some(tiles.concat()));
}

// A run wide enough for a tile, from no slot's beginning, is no run for a
// tile whole — to the fold that asks for its page, as to the settle that
// gives it its place: the two count on one giving, and a fold that
// counted on the run would ask for no page, its tile left at every rest.
#[test]
fn a_tile_whole_is_given_a_page_past_a_run_that_begins_no_slot() {
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    // A page of 128 granules: four tiles of sixteen colours and one of
    // two, 105 of them, and the three in the middle let go — 25..100
    // free, the first slot's 64 begun by a tile and the second's ended by
    // one.
    let folded = [tile(1, 16), tile(2, 16), tile(3, 16), tile(4, 16), tile(5, 2)];
    let places = stored(&mut pool, &folded.iter().collect::<Vec<_>>());
    assert_eq!(settled(&mut pool, &places), 5);
    assert_eq!(pool.lies(places[4]), folded_at(3, 4 * SIXTEEN));
    for &at in &places[1..4] {
        pool.release(at).expect("release");
    }
    let bytes = pool.bytes();
    let whole = tile(6, 64);
    let named = stored(&mut pool, &[&whole]);
    assert_eq!(named, [at(2, 1)]);
    assert_eq!(settled(&mut pool, &named), 1);
    // On the page its fold asked for — made in the place of the page of
    // tiles given back whole, both its tiles let go —, and its own page
    // of tiles away with it settled: the pool's bytes are what they were.
    assert_eq!((pool.lies(named[0]), pool.bytes()), (at(1, 0), bytes));
    let held = [places[0], places[4], named[0]];
    assert!(read(&pool, &held) == Some([&folded[0][..], &folded[4][..], &whole[..]].concat()));
}

// Between a fold and its settling the books are their caller's: a tile let
// go meanwhile, and one let go and its slot handed out again — told by its
// stamp —, are given no place, and the tile now in the slot is read as
// itself.
#[test]
fn a_tile_let_go_or_handed_out_again_before_it_is_settled_stays_as_it_is() {
    let engine = rig().engine;
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let (a, b, c, again) = (tile(1, 1), tile(2, 1), tile(3, 1), tile(4, 2));
    let places = stored(&mut pool, &[&a, &b, &c]);
    assert_eq!(fold(&mut pool, &places), (3, Some(true)));
    pool.release(places[0]).expect("release");
    pool.release(places[1]).expect("release");
    // The slot let go last is handed out first.
    assert_eq!(stored(&mut pool, &[&again]), [places[1]]);
    assert_eq!(pool.settles_unwaited(engine), 1);
    let lies: Vec<TileAt> = places.iter().map(|&at| pool.lies(at)).collect();
    assert_eq!(lies, [places[0], places[1], folded_at(1, 0)]);
    assert!(read(&pool, &places[1..]) == Some([&again[..], &c[..]].concat()));
    // The one now in the slot folds as its own.
    assert_eq!(settled(&mut pool, &places), 1);
    assert_eq!(pool.lies(places[1]), folded_at(1, ONE));
    assert!(read(&pool, &places[1..]) == Some([&again[..], &c[..]].concat()));
}

// A fold is handed the tiles named that are held and lie as they are, each
// once: a slot nobody holds, a name past the pool, a folded place, a name
// said twice and a tile a fold has in hand are passed over — and with none
// left, nothing is handed over.
#[test]
fn a_fold_takes_the_held_tiles_named_as_they_are_each_once() {
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let (a, b) = (tile(1, 1), tile(2, 2));
    let places = stored(&mut pool, &[&a, &b]);
    assert_eq!(settled(&mut pool, &places[..1]), 1);
    let lies = pool.lies(places[0]);
    let named = [places[1], at(0, 2), at(0, 9), at(5, 0), lies, places[0], places[1]];
    assert_eq!(fold(&mut pool, &named), (1, Some(true)));
    assert_eq!(fold(&mut pool, &[at(0, 2), at(5, 0), lies, places[0], places[1]]), (0, None));
    assert_eq!(fold(&mut pool, &[]), (0, None));
    assert_eq!(pool.settles_unwaited(rig().engine), 1);
    assert_eq!(pool.lies(places[1]), folded_at(1, ONE));
}

// A folded tile goes to the first page of folded tiles with a run that
// holds it, and a page is made only where none has one — one a fold,
// within the pool's bytes: past them a tile no page has a run for stays as
// it is, one behind it that a run holds does not, and the pool hands a
// fold nothing till a folded place is let go — then the one left, which
// takes it.
#[test]
fn a_page_of_folded_tiles_is_made_where_none_has_room_and_none_past_the_pool_s_bytes() {
    let engine = rig().engine;
    // A page of one tile, and so one of 64 granules: two tiles of sixteen
    // colours, and no third.
    let tiles = [tile(1, 16), tile(2, 16), tile(3, 16)];
    let mut pool = Pool::sized(1, MOST_NAMED, u64::MAX).expect("pool");
    let places = stored(&mut pool, &tiles.iter().collect::<Vec<_>>());
    assert_eq!(places, [at(0, 0), at(1, 0), at(2, 0)]);
    // One a fold, what a page holds at the most each may take — a tile
    // whole: the second's finds the run left, and the third's asks for
    // the second page.
    assert_eq!(pool.to_fold(usize::MAX), places[..1]);
    assert_eq!(folded_whole(&mut pool, usize::MAX), 3);
    let lies: Vec<TileAt> = places.iter().map(|&at| pool.lies(at)).collect();
    assert_eq!(lies, [folded_at(3, 0), folded_at(3, SIXTEEN), folded_at(4, 0)]);
    assert_eq!(pool.bytes(), 2 * TILE_BYTES, "the two pages of folded tiles: each page of tiles is away");
    assert!(read(&pool, &places) == Some(tiles.concat()));
    // A tile stored now takes a page of tiles of its own, no folded one's
    // — and one of a single colour, folded, the run left on the first
    // page of folded tiles, not the second's.
    let small = tile(4, 1);
    let more = stored(&mut pool, &[&tiles[0], &small]);
    assert_eq!(more, [at(5, 0), at(6, 0)]);
    assert_eq!(settled(&mut pool, &more[1..]), 1);
    assert_eq!(pool.lies(more[1]), folded_at(3, 2 * SIXTEEN));
    assert_eq!(pool.bytes(), 3 * TILE_BYTES, "no page where a run holds it");

    // Five pages' bytes: the four of tiles and one of folded tiles. The
    // third tile finds no run and no page more; the one behind it, of a
    // single colour, the run left.
    let all = [&tiles[0], &tiles[1], &tiles[2], &small];
    let mut pool = Pool::sized(1, MOST_NAMED, 5 * TILE_BYTES).expect("pool");
    let places = stored(&mut pool, &all);
    assert_eq!(settled(&mut pool, &places), 3);
    let lies: Vec<TileAt> = places.iter().map(|&at| pool.lies(at)).collect();
    assert_eq!(lies, [folded_at(4, 0), folded_at(4, SIXTEEN), places[2], folded_at(4, 2 * SIXTEEN)]);
    assert_eq!(pool.bytes(), 2 * TILE_BYTES, "the page of the tile left, and the folded one");
    let bytes = |tiles: &[&Vec<u8>]| tiles.iter().flat_map(|tile| tile.iter().copied()).collect();
    assert!(read(&pool, &places) == Some(bytes(&all)));
    // Nothing is left of that fold, and the pool — kept to the bytes it
    // has now, three pages of tiles given back — hands a fold nothing as
    // it stands: the tile left would find no place again, till a folded
    // place is let go. Then that tile is next, into the place.
    pool.set_most_bytes(pool.bytes());
    assert_eq!(pool.settles_unwaited(engine), 0);
    assert!(pool.to_fold(usize::MAX).is_empty());
    pool.release(places[0]).expect("release");
    assert_eq!(pool.to_fold(usize::MAX), places[2..3]);
    assert_eq!(folded_whole(&mut pool, usize::MAX), 1);
    assert_eq!(pool.lies(places[2]), folded_at(4, 0));
    assert!(read(&pool, &places[1..]) == Some(bytes(&all[1..])));
}

// A page of folded tiles is made against the budget a page of tiles is:
// none at a line of nothing — the tile stays as it is, and the pool hands
// a fold nothing within that budget —, and one once the budget gives it.
#[test]
fn a_page_of_folded_tiles_is_made_within_the_budget() {
    // A page its tile fills: one with a slot free is the pool's room.
    let mut pool = Pool::sized(1, MOST_NAMED, u64::MAX).expect("pool");
    let a = tile(1, 2);
    let places = stored(&mut pool, &[&a]);
    pool.set_budget_instead(Some(0));
    assert_eq!(settled(&mut pool, &places), 0);
    assert_eq!(pool.lies(places[0]), places[0]);
    assert_eq!(pool.bytes(), TILE_BYTES);
    assert!(pool.to_fold(usize::MAX).is_empty());
    pool.set_budget_instead(Some(u64::MAX));
    assert_eq!(pool.to_fold(usize::MAX), places);
    assert_eq!(folded_whole(&mut pool, usize::MAX), 1);
    assert_eq!(pool.lies(places[0]), folded_at(1, 0));
    assert!(read(&pool, &places) == Some(a));
}

// A page of folded tiles is made where a page is: in the place of one
// given back first, its stand-in's bytes the pool's no more — and what
// names a tile there, its stamp and its bytes, is what named it.
#[test]
fn a_page_of_folded_tiles_takes_the_place_of_a_page_given_back() {
    let engine = rig().engine;
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let (a, b) = (tile(1, 1), tile(2, 2));
    let places = stored(&mut pool, &[&a, &a, &b]);
    assert_eq!(places, [at(0, 0), at(0, 1), at(1, 0)]);
    pool.release(places[0]).expect("release");
    pool.release(places[1]).expect("release");
    pool.give_back(engine, 0);
    assert_eq!(pool.bytes(), 2 * TILE_BYTES);
    assert_eq!(settled(&mut pool, &places[2..]), 1);
    assert_eq!(pool.lies(places[2]), folded_at(0, 0));
    assert_eq!(pool.bytes(), 4 * TILE_BYTES);
    let stamps = pool.stamps();
    assert!(stamps.of(places[2]).is_some());
    assert_eq!(stamps.of(folded_at(0, 0)), stamps.of(places[2]));
    assert!(read(&pool, &places[2..]) == Some(b));
    // The pages of tiles go on where they were: the slot left on the
    // second, then a page after it.
    assert_eq!(stored(&mut pool, &[&a, &a]), [at(1, 1), at(2, 0)]);
}

// A page of folded tiles is no more granules than a folded place's number
// names — 32 MiB —, where a page of tiles is more.
#[test]
fn a_page_of_folded_tiles_is_no_more_granules_than_a_place_names() {
    let mut pool = Pool::sized(1024, MOST_NAMED, u64::MAX).expect("pool");
    let places = stored(&mut pool, &[&tile(1, 2)]);
    assert_eq!(settled(&mut pool, &places), 1);
    assert_eq!(pool.lies(places[0]), folded_at(1, 0));
    assert_eq!(pool.bytes(), 1024 * TILE_BYTES + u64::from(FOLDED) * GRANULE_BYTES);
}

// A tile is held, let go and read by the slot that names it: where it lies
// folded is no name — no hold, no let go and no read takes it.
#[test]
fn a_folded_place_is_no_name() {
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let a = tile(1, 2);
    let places = stored(&mut pool, &[&a]);
    assert_eq!(settled(&mut pool, &places), 1);
    let lies = pool.lies(places[0]);
    assert_eq!(lies, folded_at(1, 0));
    assert!(pool.hold(lies).is_none());
    assert!(pool.release(lies).is_none());
    assert!(read(&pool, &[lies]).is_none());
    assert!(read(&pool, &places) == Some(a));
}

// The bytes nobody's tile lies in: the slots no tile is held in — a folded
// tile's slot is its name's still — and the granules no folded tile lies
// in.
#[test]
fn the_idle_bytes_are_the_free_slots_and_the_granules_no_tile_lies_in() {
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let (a, b) = (tile(1, 1), tile(2, 2));
    let places = stored(&mut pool, &[&a, &b]);
    assert_eq!(pool.idle_bytes(), 2 * TILE_BYTES);
    assert_eq!(settled(&mut pool, &places), 2);
    let folded = u64::from(ONE + TWO) * GRANULE_BYTES;
    assert_eq!(pool.bytes(), 8 * TILE_BYTES);
    assert_eq!(pool.idle_bytes(), 6 * TILE_BYTES - folded);
    pool.release(places[1]).expect("release");
    assert_eq!(pool.idle_bytes(), 7 * TILE_BYTES - u64::from(ONE) * GRANULE_BYTES);
    // The place let go is no tile's: no stamp says one lies there.
    assert!(pool.stamps().of(folded_at(1, ONE)).is_none());
    assert!(pool.stamps().of(folded_at(1, 0)).is_some());
}

// What is taken of where the tiles lie says a number of its own after
// every move of a tile — one folded and settled, one let go where it lay
// folded — and the same where none moved: a tile stored, held, let go as it
// is, or folded and not yet settled. No two pools say one number. And a
// word is read by it to where its tile lies — none names none —, the pool
// taken whole being its pages, that taking and its stamps.
#[test]
fn what_is_taken_of_where_the_tiles_lie_is_told_by_the_last_move() {
    let engine = rig().engine;
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let other = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let made = pool.lying().as_of();
    assert_ne!(made, other.lying().as_of());
    let (a, b) = (tile(1, 1), tile(2, 2));
    let places = stored(&mut pool, &[&a, &b, &a]);
    pool.hold(places[2]).expect("hold");
    pool.release(places[2]).expect("release");
    pool.release(places[2]).expect("release");
    assert_eq!(fold(&mut pool, &places[..2]), (2, Some(true)));
    assert_eq!(pool.lying().as_of(), made);
    assert_eq!(pool.settles_unwaited(engine), 2);
    let folded = pool.lying().as_of();
    assert_ne!(folded, made);
    assert_eq!(pool.settles_unwaited(engine), 0);
    assert_eq!(pool.lying().as_of(), folded);
    pool.release(places[0]).expect("release");
    let let_go = pool.lying().as_of();
    assert_ne!(let_go, folded);
    let taken = pool.taken();
    assert_eq!(taken.lying.as_of(), let_go);
    assert_eq!(taken.lying.of_word(places[1].word()), Some(folded_at(1, ONE)));
    assert_eq!(taken.lying.of_word(places[0].word()), Some(places[0]));
    assert_eq!(taken.lying.of_word(NO_TILE), None);
    assert_eq!(taken.pages.len(), 2);
    assert!(taken.stamps.of(places[1]).is_some());
    assert_eq!(taken.stamps.of(folded_at(1, ONE)), pool.stamps().of(places[1]));
}

// The tiles next to fold are the pool's held ones that lie as they are and
// that no fold was handed as they are — a page's before the next page's, no
// more than asked, and no more than a page of folded tiles holds at the
// most each may take — a tile whole: one a fold has in hand and one
// settled, folded or whole, are none of them; a slot handed out again is;
// and with a slot let go its page is the pool's room, whose tiles are
// none of them till it is full again.
#[test]
fn the_tiles_next_to_fold_are_the_held_ones_no_fold_was_handed() {
    let engine = rig().engine;
    // A page of two tiles: one of folded tiles holds two at the most
    // each may take. A fold named four takes them all the same — what
    // they fold to is one page's here.
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let tiles = [tile(1, 1), tile(2, 64), tile(3, 2), tile(4, 1), tile(5, 2), tile(6, 1)];
    let places = stored(&mut pool, &tiles.iter().collect::<Vec<_>>());
    assert_eq!(places, [at(0, 0), at(0, 1), at(1, 0), at(1, 1), at(2, 0), at(2, 1)]);
    assert!(pool.to_fold(0).is_empty());
    assert_eq!(pool.to_fold(1), places[..1]);
    assert_eq!(pool.to_fold(usize::MAX), places[..2]);
    // In a fold's hand, they are next no more, told or not.
    let number = numbered();
    assert_eq!(handed(&mut pool, &places[..4], number), 4);
    assert_eq!(pool.to_fold(usize::MAX), places[4..]);
    assert_eq!(told_within(number, Duration::from_secs(120)), Some(true));
    assert_eq!(pool.to_fold(usize::MAX), places[4..]);
    // Settled, nor: the folded, and the one whole.
    assert_eq!(pool.settles_unwaited(engine), 4);
    assert_eq!(pool.lies(places[1]), at(3, 1));
    assert_eq!(pool.to_fold(usize::MAX), places[4..]);
    // A slot let go, its page is the pool's room: neither tile of it is
    // next. Handed out again it holds another tile, which is — its page
    // full.
    pool.release(places[4]).expect("release");
    assert!(pool.to_fold(usize::MAX).is_empty());
    assert_eq!(stored(&mut pool, &[&tiles[0]]), [places[4]]);
    assert_eq!(pool.to_fold(usize::MAX), places[4..]);
    assert_eq!(folded_whole(&mut pool, usize::MAX), 2);
    assert!(pool.to_fold(usize::MAX).is_empty());
    let stored = [&tiles[0], &tiles[1], &tiles[2], &tiles[3], &tiles[0], &tiles[5]];
    assert!(read(&pool, &places) == Some(stored.iter().flat_map(|tile| tile.iter().copied()).collect()));
}

// A tile a settle found no place for is a fold's to take again while the
// pool may make a page of folded tiles — and no fold's while it may make
// none, till it may again: then it is folded onto the page that comes.
#[test]
fn a_tile_left_for_want_of_a_place_is_next_again_while_a_page_may_come() {
    // A page of one tile holds two folded tiles of sixteen colours:
    // three named to one fold ask for one page, and the third finds no
    // place on it.
    let tiles = [tile(1, 16), tile(2, 16), tile(3, 16)];
    let mut pool = Pool::sized(1, MOST_NAMED, u64::MAX).expect("pool");
    let places = stored(&mut pool, &tiles.iter().collect::<Vec<_>>());
    assert_eq!(settled(&mut pool, &places), 2);
    assert_eq!(pool.lies(places[2]), places[2]);
    assert_eq!(pool.bytes(), 2 * TILE_BYTES, "one page a fold, and the two tiles' own away");
    assert_eq!(pool.to_fold(usize::MAX), places[2..]);
    pool.set_most_bytes(pool.bytes());
    assert!(pool.to_fold(usize::MAX).is_empty(), "no page may come, and no place was let go");
    pool.set_most_bytes(u64::MAX);
    assert_eq!(pool.to_fold(usize::MAX), places[2..]);
    assert_eq!(settled(&mut pool, &places[2..]), 1);
    assert_eq!(pool.lies(places[2]), folded_at(4, 0));
    assert!(read(&pool, &places) == Some(tiles.concat()));
}

// A page of folded tiles made ahead within other bounds than the pool has
// as its fold is settled goes, as a page of tiles made ahead does
// (`Pool::claimed`): the pool's bytes are what they were, none waits made,
// and its tile is a fold's to take again — onto a page made within the
// bounds the pool has then.
#[test]
fn a_page_of_folded_tiles_made_within_other_bounds_goes() {
    let engine = rig().engine;
    // A page its tile fills: one with a slot free is the pool's room.
    let mut pool = Pool::sized(1, MOST_NAMED, u64::MAX).expect("pool");
    let a = tile(1, 2);
    let places = stored(&mut pool, &[&a]);
    // Whatever page of tiles the store asked for ahead is made by here.
    engine.on_pages_thread(|| ());
    let ahead = pool.ahead_bytes();
    assert_eq!(fold(&mut pool, &places), (1, Some(true)));
    assert_eq!(pool.ahead_bytes(), ahead + TILE_BYTES, "⛔premise: its page is made");
    pool.set_budget_instead(Some(0));
    assert_eq!(pool.settles_unwaited(engine), 0);
    assert_eq!((pool.bytes(), pool.ahead_bytes()), (TILE_BYTES, ahead));
    assert_eq!(pool.lies(places[0]), places[0]);
    pool.set_budget_instead(Some(u64::MAX));
    assert_eq!(pool.to_fold(usize::MAX), places);
    assert_eq!(settled(&mut pool, &places), 1);
    assert_eq!((pool.bytes(), pool.ahead_bytes()), (TILE_BYTES, ahead), "the folded page, its tile's own away");
    assert_eq!(pool.lies(places[0]), folded_at(1, 0));
    assert!(read(&pool, &places) == Some(a));
}

// The page a fold's tiles need is asked for unless every tile of it finds
// a run of its own on the pages made: one that holds the run left is no
// word on another, and a run holds no two tiles for being wide enough
// for each.
#[test]
fn a_fold_asks_for_a_page_unless_every_tile_of_it_finds_a_run_of_its_own() {
    // A page of 64 granules, two tiles of sixteen colours on it: a run of
    // 14 is left. Pages 0 and 1 hold the tiles, page 2 their folds.
    let begun = || {
        let mut pool = Pool::sized(1, MOST_NAMED, u64::MAX).expect("pool");
        let two = [tile(1, 16), tile(2, 16)];
        let places = stored(&mut pool, &two.iter().collect::<Vec<_>>());
        assert_eq!(settled(&mut pool, &places), 2);
        pool
    };
    let lies = |pool: &Pool, places: &[TileAt]| places.iter().map(|&at| pool.lies(at)).collect::<Vec<_>>();
    // One of a single colour holds the run left, one of sixteen none.
    let mut pool = begun();
    let tiles = [tile(3, 1), tile(4, 16)];
    let places = stored(&mut pool, &tiles.iter().collect::<Vec<_>>());
    assert_eq!(settled(&mut pool, &places), 2);
    assert_eq!(lies(&pool, &places), [folded_at(2, 2 * SIXTEEN), folded_at(5, 0)]);
    // Three of two colours, 5 granules each: the run holds two of them.
    let mut pool = begun();
    let tiles = [tile(3, 2), tile(4, 2), tile(5, 2)];
    let places = stored(&mut pool, &tiles.iter().collect::<Vec<_>>());
    assert_eq!(settled(&mut pool, &places), 3);
    let run = 2 * SIXTEEN;
    assert_eq!(lies(&pool, &places), [folded_at(2, run), folded_at(2, run + TWO), folded_at(6, 0)]);
    assert!(read(&pool, &places) == Some(tiles.concat()));
}

// A page of folded tiles made ahead is not taken past the pool's own
// bytes, where those were cut since its fold was handed over: it goes,
// its tile stays as it is, and the pool hands a fold nothing till it may
// make a page again.
#[test]
fn a_page_of_folded_tiles_made_ahead_is_not_taken_past_the_pool_s_bytes() {
    let engine = rig().engine;
    let mut pool = Pool::sized(1, MOST_NAMED, u64::MAX).expect("pool");
    let a = tile(1, 2);
    let places = stored(&mut pool, &[&a]);
    engine.on_pages_thread(|| ());
    let ahead = pool.ahead_bytes();
    assert_eq!(fold(&mut pool, &places), (1, Some(true)));
    assert_eq!(pool.ahead_bytes(), ahead + TILE_BYTES, "⛔premise: its page is made");
    pool.set_most_bytes(pool.bytes());
    assert_eq!(pool.settles_unwaited(engine), 0);
    assert_eq!((pool.bytes(), pool.ahead_bytes()), (TILE_BYTES, ahead));
    assert_eq!(pool.lies(places[0]), places[0]);
    assert!(pool.to_fold(usize::MAX).is_empty(), "no page may come");
    pool.set_most_bytes(u64::MAX);
    assert_eq!(pool.to_fold(usize::MAX), places);
    assert_eq!(settled(&mut pool, &places), 1);
    assert_eq!(pool.lies(places[0]), folded_at(1, 0));
    assert!(read(&pool, &places) == Some(a));
}

// A page of tiles away keeps its tiles' names and is no room: a slot of it
// let go is handed to no tile — of its own cel, or another's —, and the
// page is given back whole with the last of its tiles, its place the next
// page's.
#[test]
fn a_page_away_hands_out_no_slot_and_is_given_back_with_its_last_tile() {
    let engine = rig().engine;
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let (a, b) = (tile(1, 1), tile(2, 2));
    let cel = pool.cel();
    let places = pool.store(engine, cel, &[&a[..], &b[..]]).expect("store");
    assert_eq!(settled(&mut pool, &places), 2);
    assert_eq!((pool.pages()[0].size(), pool.bytes()), (NO_PAGE_BYTES, 2 * TILE_BYTES));
    pool.release(places[1]).expect("release");
    assert!(read(&pool, &places[..1]) == Some(a.clone()), "held by its name, read where it lies");
    // Its own cel's next tile, and another's: on a page made for them.
    assert_eq!(pool.fresh(engine, cel), Ok(at(2, 0)));
    let other = pool.cel();
    assert_eq!(pool.fresh(engine, other), Ok(at(2, 1)));
    // The last of its tiles let go, it is a page given back: no name of
    // it is held, and the next page is made in its place.
    pool.release(places[0]).expect("release");
    assert!(pool.hold(places[0]).is_none());
    assert_eq!(pool.fresh(engine, other), Ok(at(0, 0)));
    assert_eq!(pool.pages()[0].size(), 2 * TILE_BYTES);
}

// The pool's room is the page of tiles with the most slots free, the first
// such: its tiles are none of those next to fold, and it stays made
// whatever its tiles lie as — till it is full, and the room no more.
#[test]
fn the_pool_s_room_folds_none_of_its_tiles_and_stays_made() {
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let tiles: Vec<Vec<u8>> = (1..=7).map(|seed| tile(seed, 1 + seed % 2)).collect();
    // The first page full, the second with a slot free: the room.
    let places = stored(&mut pool, &tiles.iter().collect::<Vec<_>>());
    assert_eq!(pool.to_fold(usize::MAX), places[..4]);
    // Two slots free on the first, the most: the second's tiles are next.
    pool.release(places[0]).expect("release");
    pool.release(places[1]).expect("release");
    assert_eq!(pool.to_fold(usize::MAX), places[4..]);
    // As many free on each: the first of them is the room.
    pool.release(places[4]).expect("release");
    assert_eq!(pool.to_fold(usize::MAX), places[5..]);
    assert_eq!(folded_whole(&mut pool, usize::MAX), 2);
    assert_eq!((pool.pages()[1].size(), pool.bytes()), (NO_PAGE_BYTES, 8 * TILE_BYTES), "the second away");
    // The room's tiles, folded where a fold is handed them by name, lie on
    // the page of folded tiles — and their page stays made, for its slots.
    assert_eq!(settled(&mut pool, &places[2..4]), 2);
    assert!(places[2..4].iter().all(|&at| pool.lies(at).folded().is_some()));
    assert_eq!((pool.pages()[0].size(), pool.bytes()), (4 * TILE_BYTES, 8 * TILE_BYTES));
    // Full, it is the room no more: the two stored there are next, and
    // with them settled it is away.
    let more = stored(&mut pool, &[&tiles[0], &tiles[1]]);
    assert_eq!(more, [places[1], places[0]]);
    assert_eq!(pool.to_fold(usize::MAX), [places[0], places[1]]);
    assert_eq!(folded_whole(&mut pool, usize::MAX), 2);
    assert_eq!((pool.pages()[0].size(), pool.bytes()), (NO_PAGE_BYTES, 4 * TILE_BYTES));
    let held = [more[0], more[1], places[2], places[3], places[5], places[6]];
    let stored = [&tiles[0], &tiles[1], &tiles[2], &tiles[3], &tiles[5], &tiles[6]];
    assert!(read(&pool, &held) == Some(stored.iter().flat_map(|tile| tile.iter().copied()).collect()));
}

// A rest that finds no tile to fold gives back what no settle did: the page
// of tiles whose last tile lying on it was let go since, and the page of
// folded tiles no tile lies on — its place the next page's.
#[test]
fn a_fold_that_finds_none_gives_back_the_pages_no_tile_lies_on() {
    use super::gpu_engine_pool_fold;
    let engine = rig().engine;
    let mut pool = Pool::sized(3, MOST_NAMED, u64::MAX).expect("pool");
    let tiles = [tile(1, 1), tile(2, 2), tile(3, 1), tile(4, 2)];
    // The first page full, the second the room.
    let places = stored(&mut pool, &tiles.iter().collect::<Vec<_>>());
    assert_eq!(settled(&mut pool, &places[..2]), 2);
    assert_eq!(pool.bytes(), 9 * TILE_BYTES, "the third tile lies on the first page");
    pool.release(places[2]).expect("release");
    assert_eq!(pool.bytes(), 9 * TILE_BYTES, "a let go gives no page back");
    // SAFETY: the pool and the engine are live, the kernels never let go;
    // a fold that hands nothing over calls `told` never.
    let rested = |pool: &mut Pool| unsafe { gpu_engine_pool_fold(pool, engine, kernels(), usize::MAX, told, numbered()) };
    assert_eq!(rested(&mut pool), 0);
    assert_eq!((pool.pages()[0].size(), pool.bytes()), (NO_PAGE_BYTES, 6 * TILE_BYTES));
    assert!(read(&pool, &places[..2]) == Some(tiles[..2].concat()));
    // Its tiles let go, the page of folded tiles holds none.
    pool.release(places[0]).expect("release");
    pool.release(places[1]).expect("release");
    assert_eq!(pool.bytes(), 6 * TILE_BYTES);
    assert_eq!(rested(&mut pool), 0);
    assert_eq!((pool.pages()[2].size(), pool.bytes()), (NO_PAGE_BYTES, 3 * TILE_BYTES));
    assert!(read(&pool, &places[3..]) == Some(tiles[3].clone()));
    // The next page of folded tiles is made in the first place given back.
    let more = stored(&mut pool, &[&tiles[0]]);
    assert_eq!(settled(&mut pool, &more), 1);
    assert_eq!(pool.lies(more[0]), folded_at(0, 0));
}

// A page that names no tile is nobody's, not one away: a rest leaves it
// made — the pages nobody holds go back where the pool is asked for them
// (`Pool::give_back`) —, and its slots are the next tiles'.
#[test]
fn a_rest_gives_back_no_page_that_names_no_tile() {
    use super::gpu_engine_pool_fold;
    let engine = rig().engine;
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let tiles = [tile(1, 1), tile(2, 2), tile(3, 1), tile(4, 2)];
    let places = stored(&mut pool, &tiles.iter().collect::<Vec<_>>());
    for &at in &places {
        pool.release(at).expect("release");
    }
    // Two pages nobody holds: the first is the room, and the second
    // names no tile — none lies on it, and none elsewhere is its.
    // SAFETY: the pool and the engine are live, the kernels never let go;
    // a fold that hands nothing over calls `told` never.
    let rested = unsafe { gpu_engine_pool_fold(&mut pool, engine, kernels(), usize::MAX, told, numbered()) };
    assert_eq!(rested, 0);
    assert_eq!((pool.pages()[1].size(), pool.bytes()), (2 * TILE_BYTES, 4 * TILE_BYTES));
    let cel = pool.cel();
    let pages: Vec<u16> = (0..4).map(|_| pool.fresh(engine, cel).expect("a slot").page).collect();
    assert_eq!(pages, [0, 0, 1, 1]);
}

// A settle's tiles whole are copied whatever the put of its folded tiles
// says: a put that fails — a write that names no folded place, here —
// encodes nothing and says so, and the tile whole lies in its place behind
// the one submit.
#[test]
fn a_settle_s_tiles_whole_are_copied_though_its_put_fails() {
    use super::folded::copies_submitted;
    let engine = rig().engine;
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let tiles = [tile(1, 2), tile(2, 2), tile(3, 2)];
    // Two on the first page and the third on the second, whose other slot
    // is free.
    let places = stored(&mut pool, &tiles.iter().collect::<Vec<_>>());
    assert_eq!(places, [at(0, 0), at(0, 1), at(1, 0)], "premise");
    // SAFETY: the kernels are never let go.
    let fold = unsafe { &*kernels() };
    let folded = fold.folded(engine, pool.pages(), &places[..1]).expect("folded");
    let (writes, moves) = ([(0, at(0, 0))], [(places[1], at(1, 1))]);
    let put = engine.on_thread(|| copies_submitted(engine, pool.pages(), &folded, &writes, &moves));
    assert_eq!(put, None, "a write to no folded place");
    assert!(laid_on(pool.pages(), &[at(1, 1)]) == tiles[1], "the tile whole lies where it was moved");
}

/// What a rest asks of the pool, as its verb asks it
/// (`gpu_engine_pool_fold`): how many tiles it handed a fold, told by
/// `number`.
fn asked_at_rest(pool: &mut Pool, number: u64) -> usize {
    // SAFETY: the pool and the rig's engine are live, the kernels never
    // let go, and `told` is any thread's to call.
    unsafe { super::gpu_engine_pool_fold(pool, rig().engine, kernels(), usize::MAX, told, number) }
}

/// A pool of pages of four tiles and `most_bytes` at most, three tiles
/// stored on its one page — a slot free, less than half a page — and the
/// next page made ahead: the pool, where its tiles are, and a page's
/// bytes.
fn a_page_ahead_of_three_tiles(most_bytes: u64) -> (Pool, Vec<TileAt>, u64) {
    use super::tests::ahead;
    let mut pool = Pool::sized(4, MOST_NAMED, most_bytes).expect("pool");
    let tiles = [tile(1, 1), tile(2, 2), tile(3, 1)];
    let places = stored(&mut pool, &tiles.iter().collect::<Vec<_>>());
    rig().engine.on_pages_thread(|| ());
    // SAFETY: the pool is live.
    assert_eq!(unsafe { ahead(&pool) }, "made", "premise");
    (pool, places, 4 * TILE_BYTES)
}

// A rest that finds no tile to fold takes the page made ahead as the
// pool's room, where the pool is half a page from needing it: the tiles
// of the room that was are next, and its buffer is given back once they
// lie folded. Not while tiles are next.
#[test]
fn a_rest_with_none_to_fold_takes_the_page_made_ahead_as_the_pool_s_room() {
    use super::tests::ahead;
    let engine = rig().engine;
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let page = 4 * TILE_BYTES;
    let tiles: Vec<Vec<u8>> = (1..=7).map(|seed| tile(seed, 1 + seed % 2)).collect();
    // The first page full and the second with a slot of its four free:
    // the room, and less than half a page — the next is made ahead.
    let places = stored(&mut pool, &tiles.iter().collect::<Vec<_>>());
    engine.on_pages_thread(|| ());
    // SAFETY: the pool is live, here and wherever it is asked below.
    let stands = |pool: &Pool| (unsafe { ahead(pool) }, pool.bytes());
    assert_eq!(stands(&pool), ("made", 2 * page), "premise");
    // The first page's tiles are next: the page made ahead stands.
    let number = numbered();
    assert_eq!(asked_at_rest(&mut pool, number), 4);
    assert_eq!(stands(&pool), ("made", 2 * page), "tiles next, it is not taken");
    assert_eq!(told_within(number, Duration::from_secs(120)), Some(true));
    assert_eq!(pool.settles_unwaited(engine), 4);
    assert_eq!((pool.pages()[0].size(), pool.bytes()), (NO_PAGE_BYTES, 2 * page), "the first away, folded");
    // None is next, the second page the room: the page made ahead is the
    // room in its place — a page of the pool's, counted once —, and the
    // second's three tiles are next.
    assert!(pool.to_fold(usize::MAX).is_empty(), "premise");
    let number = numbered();
    assert_eq!(asked_at_rest(&mut pool, number), 3);
    assert_eq!(stands(&pool), ("unasked", 3 * page));
    assert_eq!(told_within(number, Duration::from_secs(120)), Some(true));
    assert_eq!(pool.settles_unwaited(engine), 3);
    assert_eq!((pool.pages()[1].size(), pool.bytes()), (NO_PAGE_BYTES, 2 * page), "the room that was, away");
    assert!(read(&pool, &places) == Some(tiles.concat()), "every tile reads as it was");
    // The next tile is the new room's first, no page made for it, and a
    // rest finds nothing more.
    let cel = pool.cel();
    assert_eq!(pool.fresh(engine, cel), Ok(at(3, 0)));
    assert_eq!(asked_at_rest(&mut pool, numbered()), 0);
    assert_eq!(stands(&pool), ("unasked", 2 * page));
}

// Where half a page is free again — a tile let go since the page was
// asked for — a rest leaves the page made ahead standing: how long one
// made stands is its asking's to say, as it was.
#[test]
fn a_rest_takes_no_page_made_ahead_with_half_a_page_free() {
    use super::tests::ahead;
    let (mut pool, places, page) = a_page_ahead_of_three_tiles(u64::MAX);
    pool.release(places[2]).expect("release");
    assert_eq!(asked_at_rest(&mut pool, numbered()), 0);
    // SAFETY: the pool is live.
    assert_eq!((unsafe { ahead(&pool) }, pool.pages().len(), pool.bytes()), ("made", 1, page));
}

// Nor where the pool has no room — every page full, every tile a fold's
// already: the page made ahead stands for the next store, as it did.
#[test]
fn a_rest_takes_no_page_made_ahead_where_the_pool_has_no_room() {
    use super::tests::ahead;
    let engine = rig().engine;
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let tiles = [tile(1, 1), tile(2, 2), tile(3, 1), tile(4, 2)];
    stored(&mut pool, &tiles.iter().collect::<Vec<_>>());
    engine.on_pages_thread(|| ());
    assert_eq!(folded_whole(&mut pool, usize::MAX), 4);
    assert_eq!(asked_at_rest(&mut pool, numbered()), 0);
    // SAFETY: the pool is live.
    assert_eq!((unsafe { ahead(&pool) }, pool.bytes()), ("made", 4 * TILE_BYTES), "the page of folded tiles alone");
}

// A rest takes no page made ahead past the bytes the pool may make: it
// goes there, as at a store.
#[test]
fn a_rest_lets_the_page_made_ahead_go_past_the_pool_s_bytes() {
    use super::tests::ahead;
    let (mut pool, _, page) = a_page_ahead_of_three_tiles(u64::MAX);
    pool.set_most_bytes(page);
    assert_eq!(asked_at_rest(&mut pool, numbered()), 0);
    // SAFETY: the pool is live.
    assert_eq!((unsafe { ahead(&pool) }, pool.pages().len(), pool.bytes()), ("unasked", 1, page));
}

// Nor one made against another budget than the pool keeps to now: it
// stands, the next store's to let go.
#[test]
fn a_rest_takes_no_page_made_ahead_against_another_budget() {
    use super::tests::ahead;
    let (mut pool, _, page) = a_page_ahead_of_three_tiles(u64::MAX);
    pool.set_budget_instead(Some(0));
    assert_eq!(asked_at_rest(&mut pool, numbered()), 0);
    // SAFETY: the pool is live.
    assert_eq!((unsafe { ahead(&pool) }, pool.pages().len(), pool.bytes()), ("made", 1, page));
}
