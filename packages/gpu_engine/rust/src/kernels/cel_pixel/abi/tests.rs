//! The ink scan's C ABI on a real GPU, checked by hand: a cel named by
//! words is walked where its words say, each tile's box comes back in its
//! six words, and what the ABI is not given room for, or a tile past the
//! pool, is refused with why.

use std::sync::OnceLock;

use super::*;
use crate::kernels::composite::{NO_TILE, TILE, TILE_TEXELS, TileAt};
use crate::kernels::shared::le_bytes;
use crate::testing::{first_engine, last_error};

struct Rig {
    engine: &'static Engine,
    ink: *mut Ink,
}

// SAFETY: the scan is made once and only read after.
unsafe impl Send for Rig {}
// SAFETY: as above.
unsafe impl Sync for Rig {}

/// One device and one scan compiled through the ABI for every test here.
fn rig() -> &'static Rig {
    static RIG: OnceLock<Rig> = OnceLock::new();
    RIG.get_or_init(|| {
        let engine = first_engine();
        // SAFETY: `engine` is live for the process.
        let ink = unsafe { gpu_engine_ink_new(engine) };
        assert!(!ink.is_null(), "compile the ink scan: {}", last_error());
        Rig { engine, ink }
    })
}

/// A tile whose pixels at `inked` hold an opaque red, and none elsewhere.
fn inked(pixels: &[(u32, u32)]) -> Vec<u8> {
    let mut words = vec![0u32; TILE_TEXELS as usize];
    for &(x, y) in pixels {
        words[(y * TILE + x) as usize] = 0xff00_00ff;
    }
    le_bytes(&words)
}

/// A pool holding `tiles`, and their places.
fn stored(tiles: &[Vec<u8>]) -> (Pool, Vec<TileAt>) {
    let engine = rig().engine;
    let mut pool = Pool::new(engine, u64::MAX).expect("pool");
    let cel = pool.cel();
    let bytes: Vec<&[u8]> = tiles.iter().map(Vec::as_slice).collect();
    let places = pool.store(engine, cel, &bytes).expect("store");
    (pool, places)
}

/// The scan of the cel `words` name — `columns` × `rows` from (`x0`,
/// `y0`) — with `capacity` words of room: what it returned and put.
fn scanned(pool: &Pool, (x0, y0): (i32, i32), (columns, rows): (u32, u32), words: &[u32], capacity: usize) -> (isize, Vec<i32>) {
    let Rig { engine, ink } = rig();
    let mut out = vec![-7; capacity];
    // SAFETY: every pointer is live, `words` holds the set's tiles and
    // `out` its capacity.
    let walked = unsafe {
        gpu_engine_ink_run(*ink, *engine, pool, x0, y0, columns, rows, words.as_ptr(), out.as_mut_ptr(), capacity)
    };
    (walked, out)
}

/// Five tiles of a 3 × 2 cel from (−2, −1), the second missing: each box
/// unlike the others and unlike itself turned, so a word put in another's
/// place, or a tile read as another, says so — one tile stored but holding
/// no ink.
fn five() -> (Pool, Vec<u32>) {
    let tiles = [
        inked(&[(3, 5), (90, 40)]),
        inked(&[(120, 2)]),
        inked(&[]),
        inked(&[(0, 127), (7, 64)]),
        inked(&[(60, 61)]),
    ];
    let (pool, at) = stored(&tiles);
    let words = vec![at[0].word(), NO_TILE, at[1].word(), at[2].word(), at[3].word(), at[4].word()];
    (pool, words)
}

#[rustfmt::skip]
const FIVE_INKS: [i32; 30] = [
    -2, -1,   3,  5,  91, 41,
     0, -1, 120,  2, 121,  3,
    -2,  0,   0,  0,   0,  0,
    -1,  0,   0, 64,   8, 128,
     0,  0,  60, 61,  61, 62,
];

#[test]
fn each_walked_tile_puts_where_it_is_and_its_box() {
    let (pool, words) = five();
    assert_eq!(scanned(&pool, (-2, -1), (3, 2), &words, 30), (5, FIVE_INKS.to_vec()));
}

/// Exactly the walk's words is room enough, and nothing past them is
/// written; one word fewer is refused before anything runs.
#[test]
fn a_scan_given_too_little_room_is_refused_with_why() {
    let (pool, words) = five();
    let (walked, out) = scanned(&pool, (-2, -1), (3, 2), &words, 31);
    assert_eq!((walked, &out[..30], out[30]), (5, &FIVE_INKS[..], -7));
    let (walked, out) = scanned(&pool, (-2, -1), (3, 2), &words, 29);
    assert_eq!((walked, out), (-1, vec![-7; 29]));
    assert!(last_error().contains("room for 29 words"), "{}", last_error());
}

/// A cel of no tiles walks none, and asks for no room: `out` may be null.
#[test]
fn a_cel_of_no_tiles_walks_none() {
    let (pool, _) = five();
    let Rig { engine, ink } = rig();
    let words = [NO_TILE; 2];
    // SAFETY: every pointer is live but `out`, of no room, which a cel of no
    // tiles needs.
    let walked = unsafe {
        gpu_engine_ink_run(*ink, *engine, &pool, 0, 0, 2, 1, words.as_ptr(), std::ptr::null_mut(), 0)
    };
    assert_eq!(walked, 0);
}

/// A word's high half is its page: a pool of one page has none past it.
#[test]
fn a_tile_named_on_a_page_past_the_pool_is_refused_with_why() {
    let (pool, words) = five();
    assert_eq!(pool.pages().len(), 1);
    let past = [words[0], TileAt { page: 1, slot: 0 }.word()];
    assert_eq!(scanned(&pool, (0, 0), (2, 1), &past, 12).0, -1);
    assert!(last_error().contains("names page 1 of a pool of 1"), "{}", last_error());
}
