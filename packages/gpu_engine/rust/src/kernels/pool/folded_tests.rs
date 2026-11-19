//! The pool's folded tiles on a real GPU: a tile folded keeps its name and
//! reads as it was — off the pool, and by a pass laid on where it lies —,
//! its place goes with its last hold, one let go or handed out again
//! before it is settled stays as it is, and the pages of folded tiles are
//! made and filled as the books say.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Condvar, Mutex};
use std::time::{Duration, Instant};

use super::{MOST_NAMED, Pool};
use crate::kernels::composite::tests::{Rig, rig};
use crate::kernels::composite::{FOLDED, GRANULE_BYTES, TILE, TILE_BYTES, TileAt, TileSet};
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
fn tile(seed: u32, colours: u32) -> Vec<u8> {
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

extern "C" fn told(number: u64, folded: bool) {
    TOLD.lock().unwrap().push((number, folded));
    TELLING.notify_all();
}

/// Hands over a fold of the tiles named at `places` and waits till it is
/// told: how many it handed over, and whether they folded — none where
/// none was handed over.
fn fold(pool: &mut Pool, places: &[TileAt]) -> (usize, Option<bool>) {
    let number = NUMBERS.fetch_add(1, Ordering::Relaxed);
    let handed = pool.folds_unwaited(rig().engine, places, (told, number));
    if handed == 0 {
        return (0, None);
    }
    let deadline = Instant::now() + Duration::from_secs(120);
    let mut said = TOLD.lock().unwrap();
    loop {
        if let Some(mine) = said.iter().position(|&(told, _)| told == number) {
            return (handed, Some(said.remove(mine).1));
        }
        assert!(Instant::now() < deadline, "the fold was never told");
        said = TELLING.wait_timeout(said, Duration::from_secs(1)).unwrap().0;
    }
}

/// Folds the tiles named at `places` and settles them: how many settled.
fn settled(pool: &mut Pool, places: &[TileAt]) -> usize {
    assert_eq!(fold(pool, places).1, Some(true));
    pool.settle(rig().engine)
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

// A tile folded keeps the name it was stored under: its slot's book says
// where it lies, a read of the pool by that name hands its bytes as they
// were — unfolded, beside one that stayed as it is —, a pass laid on where
// each lies copies what it copied of the slots, and its stamp is the one
// its name has. One that folds to more than a folded tile takes stays.
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
    assert_eq!(pool.settle(engine), 3);
    let lies: Vec<TileAt> = places.iter().map(|&at| pool.lies(at)).collect();
    assert_eq!(lies, [folded_at(1, 0), folded_at(1, ONE), folded_at(1, ONE + TWO), at(0, 3)]);
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
    // Settled once: nothing is left to settle, and a folded tile is not
    // folded again — the one that stayed alone is handed over.
    assert_eq!(pool.settle(engine), 0);
    assert_eq!(fold(&mut pool, &places), (1, Some(true)));
    assert_eq!(pool.settle(engine), 0);
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
    assert_eq!(pool.settle(engine), 1);
    let lies: Vec<TileAt> = places.iter().map(|&at| pool.lies(at)).collect();
    assert_eq!(lies, [places[0], places[1], folded_at(1, 0)]);
    assert!(read(&pool, &places[1..]) == Some([&again[..], &c[..]].concat()));
    // The one now in the slot folds as its own.
    assert_eq!(settled(&mut pool, &places), 1);
    assert_eq!(pool.lies(places[1]), folded_at(1, ONE));
    assert!(read(&pool, &places[1..]) == Some([&again[..], &c[..]].concat()));
}

// A fold is handed the tiles named that are held and lie as they are, each
// once: a slot nobody holds, a name past the pool, a folded place and a
// name said twice are passed over — and with none left, nothing is handed
// over.
#[test]
fn a_fold_takes_the_held_tiles_named_as_they_are_each_once() {
    let mut pool = Pool::sized(4, MOST_NAMED, u64::MAX).expect("pool");
    let (a, b) = (tile(1, 1), tile(2, 2));
    let places = stored(&mut pool, &[&a, &b]);
    assert_eq!(settled(&mut pool, &places[..1]), 1);
    let lies = pool.lies(places[0]);
    let named = [places[1], at(0, 2), at(0, 9), at(5, 0), lies, places[0], places[1]];
    assert_eq!(fold(&mut pool, &named), (1, Some(true)));
    assert_eq!(fold(&mut pool, &[at(0, 2), at(5, 0), lies, places[0]]), (0, None));
    assert_eq!(fold(&mut pool, &[]), (0, None));
    assert_eq!(pool.settle(rig().engine), 1);
    assert_eq!(pool.lies(places[1]), folded_at(1, ONE));
}

// A folded tile goes to the first page of folded tiles with a run that
// holds it, and a page is made only where none has one — within the pool's
// bytes: past them the tiles left stay as they are, and fold once a place
// is free.
#[test]
fn a_page_of_folded_tiles_is_made_where_none_has_room_and_none_past_the_pool_s_bytes() {
    let engine = rig().engine;
    // A page of one tile, and so one of 64 granules: two tiles of sixteen
    // colours, and no third.
    let tiles = [tile(1, 16), tile(2, 16), tile(3, 16)];
    let mut pool = Pool::sized(1, MOST_NAMED, u64::MAX).expect("pool");
    let places = stored(&mut pool, &tiles.iter().collect::<Vec<_>>());
    assert_eq!(places, [at(0, 0), at(1, 0), at(2, 0)]);
    assert_eq!(settled(&mut pool, &places), 3);
    let lies: Vec<TileAt> = places.iter().map(|&at| pool.lies(at)).collect();
    assert_eq!(lies, [folded_at(3, 0), folded_at(3, SIXTEEN), folded_at(4, 0)]);
    assert_eq!(pool.bytes(), 5 * TILE_BYTES);
    assert!(read(&pool, &places) == Some(tiles.concat()));
    // A tile stored now takes a page of tiles of its own, no folded one's.
    assert_eq!(stored(&mut pool, &[&tiles[0]]), [at(5, 0)]);

    // Four pages' bytes: the three of tiles and one of folded tiles.
    let mut pool = Pool::sized(1, MOST_NAMED, 4 * TILE_BYTES).expect("pool");
    let places = stored(&mut pool, &tiles.iter().collect::<Vec<_>>());
    assert_eq!(settled(&mut pool, &places), 2);
    assert_eq!(pool.lies(places[2]), places[2]);
    assert_eq!(pool.bytes(), 4 * TILE_BYTES);
    assert!(read(&pool, &places) == Some(tiles.concat()));
    // Nothing is left of that fold: the tile is folded when it is asked
    // again, into the place one let go leaves.
    assert_eq!(pool.settle(engine), 0);
    pool.release(places[0]).expect("release");
    assert_eq!(settled(&mut pool, &places), 1);
    assert_eq!(pool.lies(places[2]), folded_at(3, 0));
    assert!(read(&pool, &places[1..]) == Some(tiles[1..].concat()));
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
}
