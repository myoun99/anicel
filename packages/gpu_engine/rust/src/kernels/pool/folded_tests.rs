//! The pool's folded tiles on a real GPU: a tile folded keeps its name and
//! reads as it was — off the pool, and by a pass laid on where it lies —,
//! its place goes with its last hold, one let go or handed out again
//! before it is settled stays as it is, one that folds to more than a
//! folded tile takes lies whole beside the folded, and the pages of
//! folded tiles are made and filled as the books say — a page's runs
//! first, the books alone —, and the tiles next to fold are the pool's to
//! say.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Condvar, Mutex, OnceLock};
use std::time::{Duration, Instant};

use super::folded::{Arena, Takes};
use super::{MOST_NAMED, Pool};
use crate::kernels::composite::tests::{Rig, rig};
use crate::device::Engine;
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
        .on_thread(|| composite.copied(engine, pool.pages(), &set, &tiles, composite.widest()))
        .expect("copied");
    read_buffer(engine, &copied.out)
}

/// Writes over the slots of the tiles named at `places`, on `engine` —
/// the pool's —: what a slot holds once its tile lies folded is nobody's
/// to read.
pub(crate) fn scrubbed(engine: &Engine, pool: &Pool, places: &[TileAt]) {
    let scrub = vec![0xa5; TILE_BYTES as usize];
    let written = engine.on_thread(|| {
        for at in places {
            let slot = at.as_it_is().expect("a slot");
            engine.queue.write_buffer(&pool.pages()[usize::from(at.page)], slot, &scrub);
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
// to whatever reads it, and no name.
#[test]
fn a_tile_folded_keeps_its_name_and_reads_as_it_was() {
    let engine = rig().engine;
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let tiles = [tile(1, 1), tile(2, 2), tile(3, 16), tile(4, 64)];
    let places = stored(&mut pool, &tiles.iter().collect::<Vec<_>>());
    assert_eq!(places, [at(0, 0), at(0, 1), at(0, 2), at(0, 3)]);
    let (as_they_were, taken_before) = (laid(&pool, &places), pool.lying());
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
    // tiles here.
    assert_eq!(pool.pages().len(), 2);
    assert_eq!(pool.bytes(), 2 * 4 * TILE_BYTES);
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
    // What was taken of the pool before says the slots, whose bytes stand.
    assert!(places.iter().all(|&at| taken_before.of(at) == at));
    assert!(laid(&pool, &places) == as_they_were);
    // A name of no slot of the pool's is its own place: a page laid after
    // the pool's.
    assert_eq!(taken.of(at(7, 5)), at(7, 5));
    assert_eq!(pool.lies(at(7, 5)), at(7, 5));
    // Settled once: nothing is left to settle, and nothing to fold — a
    // tile that lies folded, or whole, is handed to no fold again.
    assert_eq!(pool.settles_unwaited(engine), 0);
    assert_eq!(fold(&mut pool, &places), (0, None));
    assert!(pool.to_fold(usize::MAX).is_empty());
    // Whatever names a tile settled reads it where it lies: its slot's
    // bytes written over — the lane to come gives them back —, a read by
    // its name hands the tile still.
    scrubbed(rig().engine, &pool, &places);
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
    let mut pool = Pool::sized(2, MOST_NAMED, u64::MAX).expect("pool");
    let (a, b, c) = (tile(1, 1), tile(2, 64), tile(3, 64));
    let places = stored(&mut pool, &[&a, &b]);
    assert_eq!(settled(&mut pool, &places), 2);
    assert_eq!(pool.lies(places[1]), at(1, 1));
    // Two pages of two tiles' bytes: the slots held, and of the folded
    // page the tile whole and a granule.
    assert_eq!(pool.bytes(), 4 * TILE_BYTES);
    assert_eq!(pool.idle_bytes(), TILE_BYTES - u64::from(ONE) * GRANULE_BYTES);
    assert!(pool.stamps().of(at(1, 1)).is_some());
    pool.release(places[1]).expect("release");
    assert_eq!(pool.lies(places[1]), places[1]);
    assert!(pool.stamps().of(at(1, 1)).is_none());
    assert_eq!(pool.idle_bytes(), 3 * TILE_BYTES - u64::from(ONE) * GRANULE_BYTES);
    let again = stored(&mut pool, &[&c]);
    assert_eq!(again, [places[1]]);
    assert_eq!(settled(&mut pool, &again), 1);
    assert_eq!(pool.lies(again[0]), at(1, 1));
    assert_eq!(pool.bytes(), 4 * TILE_BYTES, "no page where its run is free again");
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
    // granules are left, and the next tile whole is given a page.
    let second = stored(&mut pool, &[&tiles[1]]);
    assert_eq!(settled(&mut pool, &second), 1);
    assert_eq!(pool.lies(second[0]), folded_at(1, 64));
    let third = stored(&mut pool, &[&tiles[2]]);
    assert_eq!(third, [at(2, 0)]);
    assert_eq!(settled(&mut pool, &third), 1);
    assert_eq!((pool.lies(third[0]), pool.bytes()), (at(3, 0), 8 * TILE_BYTES));
    // The one after finds that page's second slot, and asks for none.
    let fourth = stored(&mut pool, &[&tiles[3]]);
    assert_eq!(settled(&mut pool, &fourth), 1);
    assert_eq!((pool.lies(fourth[0]), pool.bytes()), (at(3, 1), 8 * TILE_BYTES));
    let all = [first[0], second[0], third[0], fourth[0]];
    assert!(read(&pool, &all) == Some(tiles.concat()));
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
    assert_eq!(pool.bytes(), 5 * TILE_BYTES);
    assert!(read(&pool, &places) == Some(tiles.concat()));
    // A tile stored now takes a page of tiles of its own, no folded one's
    // — and one of a single colour, folded, the run left on the first
    // page of folded tiles, not the second's.
    let small = tile(4, 1);
    let more = stored(&mut pool, &[&tiles[0], &small]);
    assert_eq!(more, [at(5, 0), at(6, 0)]);
    assert_eq!(settled(&mut pool, &more[1..]), 1);
    assert_eq!(pool.lies(more[1]), folded_at(3, 2 * SIXTEEN));
    assert_eq!(pool.bytes(), 7 * TILE_BYTES, "no page where a run holds it");

    // Five pages' bytes: the four of tiles and one of folded tiles. The
    // third tile finds no run and no page more; the one behind it, of a
    // single colour, the run left.
    let all = [&tiles[0], &tiles[1], &tiles[2], &small];
    let mut pool = Pool::sized(1, MOST_NAMED, 5 * TILE_BYTES).expect("pool");
    let places = stored(&mut pool, &all);
    assert_eq!(settled(&mut pool, &places), 3);
    let lies: Vec<TileAt> = places.iter().map(|&at| pool.lies(at)).collect();
    assert_eq!(lies, [folded_at(4, 0), folded_at(4, SIXTEEN), places[2], folded_at(4, 2 * SIXTEEN)]);
    assert_eq!(pool.bytes(), 5 * TILE_BYTES);
    let bytes = |tiles: &[&Vec<u8>]| tiles.iter().flat_map(|tile| tile.iter().copied()).collect();
    assert!(read(&pool, &places) == Some(bytes(&all)));
    // Nothing is left of that fold, and the pool hands a fold nothing as
    // it stands — the tile left would find no place again —, till a
    // folded place is let go: then that tile is next, into the place.
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
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let a = tile(1, 2);
    let places = stored(&mut pool, &[&a]);
    pool.set_budget_instead(Some(0));
    assert_eq!(settled(&mut pool, &places), 0);
    assert_eq!(pool.lies(places[0]), places[0]);
    assert_eq!(pool.bytes(), 4 * TILE_BYTES);
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
    assert_eq!(pool.bytes(), 3 * TILE_BYTES);
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
// settled, folded or whole, are none of them; a slot handed out again is,
// and one let go is not.
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
    // Its slot handed out again holds another tile, which is — the first
    // page's before the third's.
    pool.release(places[1]).expect("release");
    assert_eq!(stored(&mut pool, &[&tiles[0]]), [places[1]]);
    assert_eq!(pool.to_fold(usize::MAX), [places[1], places[4]]);
    pool.release(places[4]).expect("release");
    assert_eq!(pool.to_fold(usize::MAX), [places[1], places[5]]);
    assert_eq!(folded_whole(&mut pool, usize::MAX), 2);
    assert!(pool.to_fold(usize::MAX).is_empty());
    let held = [places[0], places[1], places[2], places[3], places[5]];
    let stored = [&tiles[0], &tiles[0], &tiles[2], &tiles[3], &tiles[5]];
    assert!(read(&pool, &held) == Some(stored.iter().flat_map(|tile| tile.iter().copied()).collect()));
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
    assert_eq!(pool.bytes(), 4 * TILE_BYTES, "one page a fold");
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
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let a = tile(1, 2);
    let places = stored(&mut pool, &[&a]);
    // Whatever page of tiles the store asked for ahead is made by here.
    engine.on_pages_thread(|| ());
    let ahead = pool.ahead_bytes();
    assert_eq!(fold(&mut pool, &places), (1, Some(true)));
    assert_eq!(pool.ahead_bytes(), ahead + 4 * TILE_BYTES, "⛔premise: its page is made");
    pool.set_budget_instead(Some(0));
    assert_eq!(pool.settles_unwaited(engine), 0);
    assert_eq!((pool.bytes(), pool.ahead_bytes()), (4 * TILE_BYTES, ahead));
    assert_eq!(pool.lies(places[0]), places[0]);
    pool.set_budget_instead(Some(u64::MAX));
    assert_eq!(pool.to_fold(usize::MAX), places);
    assert_eq!(settled(&mut pool, &places), 1);
    assert_eq!((pool.bytes(), pool.ahead_bytes()), (8 * TILE_BYTES, ahead));
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
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let a = tile(1, 2);
    let places = stored(&mut pool, &[&a]);
    engine.on_pages_thread(|| ());
    let ahead = pool.ahead_bytes();
    assert_eq!(fold(&mut pool, &places), (1, Some(true)));
    assert_eq!(pool.ahead_bytes(), ahead + 4 * TILE_BYTES, "⛔premise: its page is made");
    pool.set_most_bytes(pool.bytes());
    assert_eq!(pool.settles_unwaited(engine), 0);
    assert_eq!((pool.bytes(), pool.ahead_bytes()), (4 * TILE_BYTES, ahead));
    assert_eq!(pool.lies(places[0]), places[0]);
    assert!(pool.to_fold(usize::MAX).is_empty(), "no page may come");
    pool.set_most_bytes(u64::MAX);
    assert_eq!(pool.to_fold(usize::MAX), places);
    assert_eq!(settled(&mut pool, &places), 1);
    assert_eq!(pool.lies(places[0]), folded_at(1, 0));
    assert!(read(&pool, &places) == Some(a));
}
