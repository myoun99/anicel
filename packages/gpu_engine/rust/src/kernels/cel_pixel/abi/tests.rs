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

/// The verbs' pass compiled through the ABI, once for the tests here.
fn verbs() -> *mut CelPixels {
    struct Compiled(*mut CelPixels);
    // SAFETY: the pass is made once and only read after.
    unsafe impl Send for Compiled {}
    // SAFETY: as above.
    unsafe impl Sync for Compiled {}
    static PASS: OnceLock<Compiled> = OnceLock::new();
    PASS.get_or_init(|| {
        // SAFETY: the engine is live for the process.
        let pass = unsafe { gpu_engine_cel_pixels_new(rig().engine) };
        assert!(!pass.is_null(), "compile the verbs: {}", last_error());
        Compiled(pass)
    })
    .0
}

/// 색 변환 to `value`: R, G and B of the pixels with ink.
fn recolour(value: &[u8; 3]) -> VerbSpec {
    VerbSpec {
        bytes: 3,
        base: 0,
        stride: 1,
        takes_empty: 0,
        threshold: 0,
        keeps_matches: 0,
        red: std::ptr::null(),
        green: std::ptr::null(),
        blue: std::ptr::null(),
        incoming: value.as_ptr(),
        length: 3,
        step: 0,
        undo: 0,
        count: 0,
    }
}

/// What `spec` left of the cel `words` name, `columns` × 1 from (`x0`, 0).
fn passed(pool: &Pool, x0: i32, columns: u32, words: &[u32], spec: &VerbSpec) -> *mut Passed {
    let engine = rig().engine;
    // SAFETY: every pointer is live and `words` holds the set's tiles.
    let passed = unsafe {
        gpu_engine_cel_pixels_run(verbs(), engine, pool, x0, 0, columns, 1, words.as_ptr(), std::ptr::null(), spec)
    };
    assert!(!passed.is_null(), "{}", last_error());
    passed
}

/// What `passed` landed of its `count` walked tiles from `first` on: what
/// the call returned, and each tile's place and change.
fn landed(passed: *mut Passed, pool: &mut Pool, first: usize, count: usize) -> (isize, Vec<u32>, Vec<u8>) {
    let (mut places, mut changes) = (vec![7; count], vec![7; count]);
    let cel = pool.cel().0;
    // SAFETY: every pointer is live; each of `places` and `changes` holds `count`.
    let returned = unsafe {
        gpu_engine_cel_passed_land(passed, rig().engine, pool, cel, first, count, places.as_mut_ptr(), changes.as_mut_ptr())
    };
    (returned, places, changes)
}

fn first_pixel(pool: &Pool, word: u32) -> [u8; 4] {
    let mut bytes = vec![0; TILE_TEXELS as usize * 4];
    let at = TileAt::of_word(word).expect("a tile's word");
    pool.read(rig().engine, &[at], &mut bytes).expect("read");
    [bytes[0], bytes[1], bytes[2], bytes[3]]
}

/// A tile whose every pixel is `rgba`.
fn flat(rgba: u32) -> Vec<u8> {
    le_bytes(&vec![rgba; TILE_TEXELS as usize])
}

#[test]
fn a_verb_says_what_it_walked_what_its_pixels_held_and_lands_what_it_took() {
    let (mut pool, at) = stored(&[flat(0xff30_2010), flat(0), flat(0x8040_5060)]);
    let words = [at[0].word(), NO_TILE, at[1].word(), at[2].word()];
    let spec = recolour(&[1, 2, 3]);
    let ran = passed(&pool, -1, 4, &words, &spec);
    // SAFETY: `ran` is live.
    assert_eq!(unsafe { gpu_engine_cel_passed_walked(ran) }, 3);
    let mut tiles = [9; 6];
    // SAFETY: two words a walked tile.
    unsafe { gpu_engine_cel_passed_tiles(ran, tiles.as_mut_ptr()) };
    assert_eq!(tiles, [-1, 0, 1, 0, 2, 0]);
    // SAFETY: `ran` is live.
    assert_eq!(unsafe { gpu_engine_cel_passed_run_count(ran) }, 2);
    let mut runs = [9; 4];
    // SAFETY: two words a run.
    unsafe { gpu_engine_cel_passed_runs(ran, runs.as_mut_ptr()) };
    let texels = TILE_TEXELS as u32;
    assert_eq!(runs, [0x30_2010, texels, 0x40_5060, texels]);
    let (returned, places, changes) = landed(ran, &mut pool, 0, 3);
    assert_eq!((returned, &changes[..]), (3, &[1, 0, 1][..]));
    assert_eq!(places[1], NO_TILE);
    assert_eq!(first_pixel(&pool, places[0]), [1, 2, 3, 0xff]);
    assert_eq!(first_pixel(&pool, places[2]), [1, 2, 3, 0x80]);
    assert_eq!(first_pixel(&pool, words[0]), [0x10, 0x20, 0x30, 0xff]);
    // SAFETY: `ran` is not used after.
    unsafe { gpu_engine_cel_passed_free(ran) };
}

/// A landing that went on after a full pool starts past what landed.
#[test]
fn a_landing_from_a_later_tile_puts_that_tile() {
    let (mut pool, at) = stored(&[flat(0xff00_0001), flat(0x7700_0002)]);
    let words = [at[0].word(), at[1].word()];
    let spec = recolour(&[9, 8, 7]);
    let ran = passed(&pool, 0, 2, &words, &spec);
    let (returned, places, changes) = landed(ran, &mut pool, 1, 1);
    assert_eq!((returned, &changes[..]), (1, &[1][..]));
    assert_eq!(first_pixel(&pool, places[0]), [9, 8, 7, 0x77]);
    // SAFETY: `ran` is not used after.
    unsafe { gpu_engine_cel_passed_free(ran) };
}

#[test]
fn a_landing_past_the_walk_is_refused_with_why() {
    let (mut pool, at) = stored(&[flat(0xff00_0001)]);
    let words = [at[0].word()];
    let spec = recolour(&[9, 8, 7]);
    let ran = passed(&pool, 0, 1, &words, &spec);
    let (returned, ..) = landed(ran, &mut pool, 0, 2);
    assert_eq!(returned, -1);
    assert!(last_error().contains("of a walk of 1"), "{}", last_error());
    // SAFETY: `ran` is not used after.
    unsafe { gpu_engine_cel_passed_free(ran) };
}

/// An alpha verb's tile left with no alpha is not `Cleared` and takes a
/// slot: the colour under it is what the undo's selector reads.
#[test]
fn a_tile_a_verb_emptied_lands_with_its_colour() {
    let (mut pool, at) = stored(&[flat(0xff30_2010)]);
    let words = [at[0].word()];
    let nothing = [0u8];
    let spec = VerbSpec {
        bytes: 1,
        base: 3,
        stride: 0,
        takes_empty: 1,
        incoming: nothing.as_ptr(),
        length: 1,
        ..recolour(&[0, 0, 0])
    };
    let ran = passed(&pool, 0, 1, &words, &spec);
    let (returned, places, changes) = landed(ran, &mut pool, 0, 1);
    assert_eq!((returned, &changes[..]), (1, &[1][..]));
    assert_eq!(first_pixel(&pool, places[0]), [0x10, 0x20, 0x30, 0]);
    // SAFETY: `ran` is not used after.
    unsafe { gpu_engine_cel_passed_free(ran) };
}

#[test]
fn a_verb_the_kernel_refuses_runs_to_none_with_why() {
    let (pool, at) = stored(&[flat(0xff30_2010)]);
    let words = [at[0].word()];
    let spec = VerbSpec { bytes: 4, ..recolour(&[0, 0, 0]) };
    let engine = rig().engine;
    // SAFETY: every pointer is live and `words` holds the set's tile.
    let ran = unsafe {
        gpu_engine_cel_pixels_run(verbs(), engine, &pool, 0, 0, 1, 1, words.as_ptr(), std::ptr::null(), &spec)
    };
    assert!(ran.is_null());
    assert!(last_error().contains("no channel"), "{}", last_error());
}
