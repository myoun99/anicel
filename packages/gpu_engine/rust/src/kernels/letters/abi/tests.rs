//! The letters' C ABI on a real GPU: faces handed over as files and a
//! picture built call by call set the very picture the same faces and
//! passes built in Rust do, and what is refused says why.

use std::sync::Mutex;

use super::*;
use crate::kernels::composite::{TILE_BYTES, TileAt};
use crate::kernels::composite::tests::rig;
use crate::kernels::letters::glyphs_tests::{faces, file, here, run};
use crate::kernels::letters::mapped::tests::path_of;
use crate::testing::{done_here, last_error, read_buffer};

const WORDS: [f32; 6] = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0];
/// Turned a little, scaled and moved off the grid's pixels: a stand.
const STAND: [f32; 6] = [1.4, 0.3, -0.3, 1.4, 20.25, 7.5];

/// The app's faces — BIZ UDPGothic, 나눔고딕, Noto Sans SC, each family's
/// files together — through the ABI.
fn handed() -> *mut Faces {
    let files = [
        (file("BIZUDPGothic-Regular.ttf"), 0),
        (file("BIZUDPGothic-Bold.ttf"), 0),
        (file("NanumGothic-Regular.ttf"), 1),
        (file("NanumGothic-Bold.ttf"), 1),
        (file("NotoSansSC-Regular.ttf"), 2),
        (file("NotoSansSC-Bold.ttf"), 2),
    ];
    faces_of(&files)
}

fn faces_of(files: &[(Vec<u8>, u32)]) -> *mut Faces {
    let handed = gpu_engine_faces_handed();
    for (bytes, family) in files {
        // SAFETY: `handed` is not yet set up; `bytes` holds its length.
        unsafe { gpu_engine_faces_file(handed, *family, bytes.as_ptr(), bytes.len()) };
    }
    // SAFETY: `handed` is set up once, here.
    unsafe { gpu_engine_faces_of(handed) }
}

/// `text` — one cluster a letter, Latin, Hangul and a simplified
/// character, so each family draws one — as the ABI is handed a run.
fn run_of(letters: *mut Lettering, text: &str, at: [f32; 6]) -> bool {
    let set = run(text, 30 * 64, (5 * 64, 40 * 64), 31 * 64);
    let mut ends = Vec::new();
    let mut origins = Vec::new();
    let mut end = 0;
    for cluster in &set.clusters {
        end += cluster.text.len() as u32;
        ends.push(end);
        origins.extend(cluster.origin);
    }
    // SAFETY: each buffer holds what it is said to.
    unsafe {
        gpu_engine_letters_run(
            letters,
            at.as_ptr(),
            set.size,
            400,
            false,
            text.as_ptr(),
            text.len(),
            ends.as_ptr(),
            origins.as_ptr(),
            ends.len(),
        )
    }
}

/// What lands of letters through the C ABI told of their pictures: each
/// one's number and whether it was put (`gpu_engine_letters_land`).
static PUT: Mutex<Vec<(u64, bool)>> = Mutex::new(Vec::new());

extern "C" fn put(number: u64, done: bool) {
    PUT.lock().unwrap().push((number, done));
}

fn was_put(number: u64) -> Option<bool> {
    PUT.lock().unwrap().iter().find(|&&(told, _)| told == number).map(|&(_, done)| done)
}

/// Lands every tile of `rect` of `letters`' covers in a fresh slot of
/// `cel` of `pool` through the ABI, waiting for none of it, told as
/// `number`: what it returned, and each tile's place and change.
///
/// # Safety
/// Every pointer is live, the pool and the executor made on `engine`.
unsafe fn land(
    letters: *const Lettering,
    (engine, composite): (*const Engine, *const Composite),
    (pool, cel): (*mut Pool, u32),
    rect: [i32; 4],
    number: u64,
) -> (isize, Vec<u32>, Vec<u8>) {
    let [x0, y0, columns, rows] = rect;
    let asks: Vec<i32> =
        (0..rows).flat_map(|down| (0..columns).flat_map(move |across| [x0 + across, y0 + down])).collect();
    let count = asks.len() / 2;
    let (mut places, mut changes) = (vec![0; count], vec![0; count]);
    // SAFETY: see the function's contract; `asks` holds `2 × count` and
    // the rest `count`.
    let landed = unsafe {
        gpu_engine_letters_land(
            letters,
            engine,
            composite,
            pool,
            cel,
            asks.as_ptr(),
            count,
            places.as_mut_ptr(),
            changes.as_mut_ptr(),
            put,
            number,
        )
    };
    (landed, places, changes)
}

/// The straight RGBA8 tiles of `letters`' covers, and where: each of
/// `rect`'s landed in a slot of a pool of its own through the ABI, and
/// read there once the engine's thread has put them.
fn read(engine: &Engine, composite: &Composite, letters: *const Lettering, rect: [i32; 4]) -> ([i32; 4], Vec<u8>) {
    let mut pool = Pool::new(engine, u64::MAX).expect("pool");
    let cel = pool.cel();
    // SAFETY: every pointer is live, the pool made on `engine`.
    let (landed, places, changes) = unsafe { land(letters, (engine, composite), (&mut pool, cel.0), rect, 0) };
    let count = places.len();
    assert_eq!(landed, count as isize, "{}", last_error());
    assert!(changes.iter().all(|&change| change == 1), "each landed inked");
    assert_eq!(done_here(engine), Ok(()), "the picture put");
    let places: Vec<TileAt> = places.into_iter().map(|word| TileAt::of_word(word).expect("a slot")).collect();
    let mut bytes = vec![0; count * TILE_BYTES as usize];
    pool.read(engine, &places, &mut bytes).expect("read");
    (rect, bytes)
}

#[test]
fn a_picture_built_call_by_call_is_the_one_built_in_rust() {
    let rig = rig();
    let handed_faces = handed();
    assert!(!handed_faces.is_null(), "{}", last_error());
    let letters = gpu_engine_letters_new();
    // SAFETY: `letters` is live.
    unsafe {
        assert!(gpu_engine_letters_pass(letters, 0xFF20_2020, false, 3 * 64));
        assert!(run_of(letters, "A셀业", WORDS));
        assert!(gpu_engine_letters_pass(letters, 0xC0FF_FFFF, false, 0));
        assert!(run_of(letters, "A셀业", WORDS));
        assert!(gpu_engine_letters_rect(letters, WORDS.as_ptr(), [0, 44 * 64, 100 * 64, 46 * 64].as_ptr()));
    }
    let mut rect = [0; 4];
    // SAFETY: every pointer is live.
    let covered = unsafe { gpu_engine_letters_cover(letters, handed_faces, STAND.as_ptr(), rect.as_mut_ptr()) };
    assert!(covered, "{}", last_error());
    let handed = read(rig.engine, &rig.composite, letters, rect);

    let [a, b, c, d, e, f] = STAND;
    let covered = set(
        faces(),
        Affine { a, b, c, d, e, f },
        &[
            Pass {
                colour: 0xFF20_2020,
                hard: false,
                paint: Paint::Stroke { width: 3 * 64 },
                shapes: here(vec![Shape::Letters(run("A셀业", 30 * 64, (5 * 64, 40 * 64), 31 * 64))]),
            },
            Pass {
                colour: 0xC0FF_FFFF,
                hard: false,
                paint: Paint::Fill,
                shapes: here(vec![
                    Shape::Letters(run("A셀业", 30 * 64, (5 * 64, 40 * 64), 31 * 64)),
                    Shape::Rect([0, 44 * 64, 100 * 64, 46 * 64]),
                ]),
            },
        ],
    )
    .expect("covered");
    let built = lettered(rig.engine, &rig.composite, &covered).expect("laid");
    let at = covered.rect;
    let built = ([at.x0, at.y0, at.columns as i32, at.rows as i32], read_buffer(rig.engine, &built));
    assert_eq!(handed.0, built.0, "the rectangle");
    assert!(handed.1 == built.1, "the pixels");
    assert!(handed.1.chunks_exact(4).any(|pixel| pixel[3] != 0), "LIVENESS: letters were laid");
    // SAFETY: each came from its `_new`.
    unsafe {
        gpu_engine_letters_free(letters);
        gpu_engine_faces_free(handed_faces);
    }
}

#[test]
fn each_tile_lands_in_its_place_across_and_down() {
    let rig = rig();
    let handed_faces = handed();
    assert!(!handed_faces.is_null(), "{}", last_error());
    let letters = gpu_engine_letters_new();
    // SAFETY: `letters` is live; the rect holds four words.
    unsafe {
        assert!(gpu_engine_letters_pass(letters, 0xFF20_2020, false, 0));
        assert!(gpu_engine_letters_rect(letters, WORDS.as_ptr(), [10 * 64, 20 * 64, 300 * 64, 200 * 64].as_ptr()));
    }
    let mut rect = [0; 4];
    // SAFETY: every pointer is live.
    let covered = unsafe { gpu_engine_letters_cover(letters, handed_faces, WORDS.as_ptr(), rect.as_mut_ptr()) };
    assert!(covered, "{}", last_error());
    assert_eq!(rect[2..], [3, 2], "⛔premise: three columns of tiles and two rows");
    // SAFETY: `letters` is live, and covered.
    let covered = unsafe { (*letters).covered.clone() }.expect("covered");
    let laid = lettered(rig.engine, &rig.composite, &covered).expect("laid");
    let picture = read_buffer(rig.engine, &laid);

    let (_, landed) = read(rig.engine, &rig.composite, letters, rect);

    assert!(landed == picture, "a tile landed in another's place");
    // SAFETY: each came from its `_new`.
    unsafe {
        gpu_engine_letters_free(letters);
        gpu_engine_faces_free(handed_faces);
    }
}

#[test]
fn faces_handed_over_in_no_family_order_are_refused() {
    let biz = file("BIZUDPGothic-Regular.ttf");
    assert!(faces_of(&[(biz.clone(), 1)]).is_null());
    assert!(last_error().contains("family 1"), "{}", last_error());
    assert!(faces_of(&[(biz.clone(), 0), (biz.clone(), 2)]).is_null());
    assert!(last_error().contains("family 2"), "{}", last_error());
    // The first refusal is the one told: the files after it are not looked at.
    assert!(faces_of(&[(biz.clone(), 0), (biz.clone(), 2), (biz.clone(), 5)]).is_null());
    assert!(last_error().contains("family 2"), "{}", last_error());
    assert!(faces_of(&[(biz, 0), (b"no face".to_vec(), 1)]).is_null());
    assert!(last_error().contains("family 1 holds no face"), "{}", last_error());
    assert!(faces_of(&[]).is_null());
    assert!(last_error().contains("none was given"), "{}", last_error());
}

#[test]
fn a_shape_with_no_pass_to_go_to_is_refused() {
    let letters = gpu_engine_letters_new();
    assert!(!run_of(letters, "A", WORDS));
    assert!(last_error().contains("none was begun"), "{}", last_error());
    // SAFETY: `letters` is live; the rect holds four words.
    unsafe {
        assert!(!gpu_engine_letters_rect(letters, WORDS.as_ptr(), [0, 0, 64, 64].as_ptr()));
        assert!(!gpu_engine_letters_pass(letters, 0xFF00_0000, false, -64));
        assert!(last_error().contains("an outline -64 wide"), "{}", last_error());
        gpu_engine_letters_free(letters);
    }
}

#[test]
fn clusters_that_do_not_cut_the_letters_whole_are_refused() {
    let letters = gpu_engine_letters_new();
    let text = "A셀";
    let ask = |ends: &[u32]| {
        let origins = vec![0; 2 * ends.len()];
        // SAFETY: each buffer holds what it is said to.
        unsafe {
            gpu_engine_letters_run(
                letters,
                WORDS.as_ptr(),
                64,
                400,
                false,
                text.as_ptr(),
                text.len(),
                ends.as_ptr(),
                origins.as_ptr(),
                ends.len(),
            )
        }
    };
    // SAFETY: `letters` is live.
    assert!(unsafe { gpu_engine_letters_pass(letters, 0xFF00_0000, false, 0) });
    assert!(ask(&[1, 4]), "{}", last_error());
    assert!(!ask(&[1]), "short of the letters");
    assert!(last_error().contains("the letters at 4"), "{}", last_error());
    assert!(!ask(&[2, 4]), "inside 셀");
    assert!(!ask(&[1, 1, 4]), "an empty cluster");
    assert!(!ask(&[1, 9]), "past the letters");
    // A run wrong twice over says the first: its weight.
    let origins = [0; 2];
    // SAFETY: each buffer holds what it is said to.
    let twice = unsafe {
        gpu_engine_letters_run(
            letters,
            WORDS.as_ptr(),
            64,
            0,
            false,
            text.as_ptr(),
            text.len(),
            [1].as_ptr(),
            origins.as_ptr(),
            1,
        )
    };
    assert!(!twice);
    assert!(last_error().contains("a weight of 0"), "{}", last_error());
    // SAFETY: made by `gpu_engine_letters_new`.
    unsafe { gpu_engine_letters_free(letters) };
}

#[test]
fn letters_that_cover_nothing_are_no_picture_and_no_failure() {
    let rig = rig();
    let faces = handed();
    let letters = gpu_engine_letters_new();
    // SAFETY: `letters` is live.
    unsafe {
        assert!(gpu_engine_letters_pass(letters, 0xFF00_0000, false, 0));
        assert!(run_of(letters, " ", WORDS));
    }
    let cover = |to_grid: *const f32| {
        let mut rect = [-1; 4];
        // SAFETY: every pointer is live or null where the ABI says so.
        let covered = unsafe { gpu_engine_letters_cover(letters, faces, to_grid, rect.as_mut_ptr()) };
        (covered, rect)
    };
    assert_eq!(cover(WORDS.as_ptr()), (true, [0; 4]), "a space: no picture, its rectangle none");
    let mut pool = Pool::new(rig.engine, u64::MAX).expect("pool");
    let cel = pool.cel();
    // SAFETY: every pointer is live, the pool made on the rig's engine.
    let (landed, _, _) = unsafe { land(letters, (rig.engine, &rig.composite), (&mut pool, cel.0), [0, 0, 1, 1], 301) };
    assert_eq!(landed, -1, "no picture to land");
    assert!(last_error().contains("cover no pixel"), "{}", last_error());
    assert_eq!(cover(std::ptr::null()), (false, [-1; 4]), "a failure: its rectangle as it was");
    assert!(last_error().contains("no placement was given"), "{}", last_error());
    assert_eq!(was_put(301), None, "nothing handed over");
    // SAFETY: each came from its `_new`.
    unsafe {
        gpu_engine_letters_free(letters);
        gpu_engine_faces_free(faces);
    }
}

/// A picture of one box — over three columns of tiles and two rows of
/// them —, covered.
fn a_box_covered(faces: *const Faces) -> (*mut Lettering, [i32; 4]) {
    let letters = gpu_engine_letters_new();
    let mut rect = [0; 4];
    // SAFETY: `letters` and `faces` are live; the boxes hold four words,
    // the placement six floats.
    unsafe {
        assert!(gpu_engine_letters_pass(letters, 0xFF20_2020, false, 0));
        assert!(gpu_engine_letters_rect(letters, WORDS.as_ptr(), [10 * 64, 20 * 64, 300 * 64, 200 * 64].as_ptr()));
        assert!(gpu_engine_letters_cover(letters, faces, WORDS.as_ptr(), rect.as_mut_ptr()), "{}", last_error());
    }
    (letters, rect)
}

// A plate's picture is the engine's thread's to lay and put, its caller
// waiting for none of it (the-ui-thread-never-enters-the-driver,
// 2026-11-18): its slots are told while that thread stands still, and the
// picture is told put — and its pixels are there — once the thread goes on.
#[test]
fn a_plate_tells_its_slots_while_the_engines_thread_stands_still() {
    use crate::device::{gpu_engine_close, gpu_engine_open_first, gpu_engine_stand_still};
    use crate::kernels::composite::abi::{gpu_engine_composite_free, gpu_engine_composite_new};
    use crate::kernels::pool::{gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_new, gpu_engine_pool_read};
    use crate::testing::a_device_of_its_own;
    let _turn = a_device_of_its_own();
    let faces = handed();
    let (letters, rect) = a_box_covered(faces);
    let tile = TILE_BYTES as usize;
    let (mut first, mut second) = (vec![0; 6 * tile], vec![0; 6 * tile]);
    // SAFETY: the engine is this test's own, live till its close; every
    // other pointer is live, and `first` and `second` hold six tiles each.
    unsafe {
        let engine = gpu_engine_open_first();
        assert!(!engine.is_null(), "{}", last_error());
        let composite = gpu_engine_composite_new(engine);
        assert!(!composite.is_null(), "{}", last_error());
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        // ⛔premise: a page with room — a page is made on the engine's
        // thread, which stands still below.
        let (landed, places, _) = land(letters, (engine, composite), (pool, cel), rect, 401);
        assert_eq!(landed, 6, "{}", last_error());
        assert_eq!(done_here(&*engine), Ok(()));
        assert_eq!(was_put(401), Some(true), "⛔premise: a picture is told");
        assert!(gpu_engine_pool_read(pool, engine, places.as_ptr(), 6, first.as_mut_ptr()), "{}", last_error());
        gpu_engine_stand_still(engine, 2_000);
        let (landed, places, _) = land(letters, (engine, composite), (pool, cel), rect, 402);
        assert_eq!(landed, 6, "its slots told");
        assert_eq!(was_put(402), None, "told its slots before its picture was laid");
        assert_eq!(done_here(&*engine), Ok(()));
        assert_eq!(was_put(402), Some(true));
        assert!(gpu_engine_pool_read(pool, engine, places.as_ptr(), 6, second.as_mut_ptr()), "{}", last_error());
        assert!(second == first, "its slots hold its picture");
        assert!(first.chunks_exact(4).any(|pixel| pixel[3] != 0), "LIVENESS: the box was laid");
        gpu_engine_pool_free(pool);
        gpu_engine_composite_free(composite);
        gpu_engine_close(engine);
        gpu_engine_letters_free(letters);
        gpu_engine_faces_free(faces);
    }
}

// A plate the device refuses to lay or put says so: its slots were told,
// as the books are the caller's, the picture is told not put and the
// caller's next done fails — and no place is said unwritten: the plate's
// tiles have no bytes to be stored again from (`gpu_engine_letters_land`).
#[test]
fn a_plate_the_device_refuses_is_told_not_put() {
    use crate::device::{gpu_engine_close, gpu_engine_lose, gpu_engine_open_first};
    use crate::kernels::composite::abi::{gpu_engine_composite_free, gpu_engine_composite_new};
    use crate::kernels::pool::{gpu_engine_pool_cel, gpu_engine_pool_free, gpu_engine_pool_new, gpu_engine_pool_unwritten};
    use crate::testing::a_device_of_its_own;
    let _turn = a_device_of_its_own();
    let faces = handed();
    let (letters, rect) = a_box_covered(faces);
    let (mut pages, mut slots) = ([u16::MAX; 6], [u16::MAX; 6]);
    // SAFETY: the engine is this test's own, live till its close; every
    // other pointer is live, `pages` and `slots` six each.
    unsafe {
        let engine = gpu_engine_open_first();
        assert!(!engine.is_null(), "{}", last_error());
        let composite = gpu_engine_composite_new(engine);
        assert!(!composite.is_null(), "{}", last_error());
        let pool = gpu_engine_pool_new(engine, u64::MAX, u64::MAX);
        let cel = gpu_engine_pool_cel(pool);
        assert_eq!(land(letters, (engine, composite), (pool, cel), rect, 501).0, 6, "{}", last_error());
        assert_eq!(done_here(&*engine), Ok(()));
        assert_eq!(was_put(501), Some(true), "⛔premise");
        // Said gone at once, as wgpu says it of a device it gave up for want
        // of memory (`gpu_engine_lose`): a loss told at the next wait would
        // come after the land.
        gpu_engine_lose(engine, true);
        assert_eq!(land(letters, (engine, composite), (pool, cel), rect, 502).0, 6, "its slots told");
        assert!(done_here(&*engine).is_err(), "the next done is told");
        assert_eq!(was_put(502), Some(false));
        assert_eq!(gpu_engine_pool_unwritten(pool, pages.as_mut_ptr(), slots.as_mut_ptr(), 6), 0, "none said unwritten");
        gpu_engine_pool_free(pool);
        gpu_engine_composite_free(composite);
        gpu_engine_close(engine);
        gpu_engine_letters_free(letters);
        gpu_engine_faces_free(faces);
    }
}

/// `text`'s letters as the ABI is handed a word's run: one cluster a
/// letter, `step` 64ths apart from the box's left, on a baseline at `y`.
fn word_run_of(word: *mut Wording, text: &str, size: i32, y: i32, step: i32) -> bool {
    let set = run(text, size, (0, y), step);
    let mut ends = Vec::new();
    let mut origins = Vec::new();
    let mut end = 0;
    for cluster in &set.clusters {
        end += cluster.text.len() as u32;
        ends.push(end);
        origins.extend(cluster.origin);
    }
    // SAFETY: each buffer holds what it is said to.
    unsafe {
        gpu_engine_word_run(
            word,
            set.size,
            400,
            false,
            text.as_ptr(),
            text.len(),
            ends.as_ptr(),
            origins.as_ptr(),
            ends.len(),
        )
    }
}

/// Three pixels a px, the layout's origin two pixels in: a word rastered
/// twice over at a ratio of 1.5.
const TWICE_OVER: [f32; 6] = [3.0, 0.0, 0.0, 3.0, 2.0, 2.0];

/// What the same runs built in Rust raster to, laid as [`TWICE_OVER`].
fn rastered_in_rust(faces: &Faces, runs: Vec<Run>, [width, height]: [u32; 2]) -> Vec<u8> {
    let to_raster = Affine { a: 3.0, b: 0.0, c: 0.0, d: 3.0, e: 2.0, f: 2.0 };
    let mut bytes = vec![0; (width * height) as usize];
    words::rastered(faces, &here(runs.into_iter().map(Shape::Letters).collect()), to_raster, width, &mut bytes);
    bytes
}

#[test]
fn a_word_built_call_by_call_rasters_as_the_one_built_in_rust() {
    let handed_faces = handed();
    let word = gpu_engine_word_new();
    // Two runs, in two styles: a word set in more than one.
    assert!(word_run_of(word, "3a", 12 * 64, 12 * 64, 7 * 64), "{}", last_error());
    assert!(word_run_of(word, "셀", 9 * 64, 12 * 64, 0), "{}", last_error());
    let (width, height) = (76u32, 49u32);
    let mut bytes = vec![7u8; (width * height) as usize];
    // SAFETY: every pointer is live, and `bytes` holds the raster.
    let rastered =
        unsafe { gpu_engine_word_raster(word, handed_faces, TWICE_OVER.as_ptr(), width, height, bytes.as_mut_ptr()) };
    assert!(rastered, "{}", last_error());

    let runs = vec![run("3a", 12 * 64, (0, 12 * 64), 7 * 64), run("셀", 9 * 64, (0, 12 * 64), 0)];
    assert!(bytes == rastered_in_rust(faces(), runs, [width, height]), "the coverage");
    assert!(bytes.iter().any(|&alpha| alpha != 0), "LIVENESS: the word has ink");
    // SAFETY: each came from its `_new`.
    unsafe {
        gpu_engine_word_free(word);
        gpu_engine_faces_free(handed_faces);
    }
}

#[test]
fn a_raster_the_engine_refuses_writes_nothing_and_says_why() {
    let handed_faces = handed();
    let word = gpu_engine_word_new();
    assert!(word_run_of(word, "3a", 12 * 64, 12 * 64, 7 * 64));
    let mut bytes = vec![7u8; 70_000];
    for (width, height, why) in [(0, 16, "pixels has none"), (65_537, 1, "a side is 65536 at most")] {
        // SAFETY: every pointer is live; a refused raster is written to none.
        let rastered =
            unsafe { gpu_engine_word_raster(word, handed_faces, TWICE_OVER.as_ptr(), width, height, bytes.as_mut_ptr()) };
        assert!(!rastered, "{width} × {height}");
        assert!(last_error().contains(why), "{}", last_error());
    }
    // SAFETY: every pointer but the placement is live, which is asked first.
    let unplaced = unsafe { gpu_engine_word_raster(word, handed_faces, std::ptr::null(), 14, 15, bytes.as_mut_ptr()) };
    assert!(!unplaced);
    assert!(last_error().contains("no placement was given"), "{}", last_error());
    assert!(bytes.iter().all(|&byte| byte == 7), "a refused raster wrote");
    // SAFETY: each came from its `_new`.
    unsafe {
        gpu_engine_word_free(word);
        gpu_engine_faces_free(handed_faces);
    }
}

#[test]
fn a_word_is_whole_where_every_letter_of_every_run_is_some_family_s() {
    let handed_faces = handed();
    // BIZ UDPGothic alone: no Hangul, which the app's second family draws.
    let biz = faces_of(&[(file("BIZUDPGothic-Regular.ttf"), 0)]);
    let whole_in = |runs: &[&str], faces: *mut Faces| {
        let word = gpu_engine_word_new();
        for text in runs {
            assert!(word_run_of(word, text, 12 * 64, 12 * 64, 7 * 64), "{}", last_error());
        }
        // SAFETY: both are live.
        let whole = unsafe { gpu_engine_word_whole(word, faces) };
        // SAFETY: it came from its `_new`.
        unsafe { gpu_engine_word_free(word) };
        whole
    };
    // A letter each family draws: Latin, Hangul, a simplified character.
    assert!(whole_in(&["3a셀们"], handed_faces));
    assert!(whole_in(&["3a"], biz));
    assert!(!whole_in(&["3a셀"], biz), "a letter the one family has not");
    // None of the three has an emoji; in a later run it tells as well.
    assert!(!whole_in(&["3😀"], handed_faces));
    assert!(!whole_in(&["3a", "😀"], handed_faces));
    assert!(whole_in(&[], handed_faces), "a word of no run lacks nothing");
    // SAFETY: each came from `gpu_engine_faces_of`.
    unsafe {
        gpu_engine_faces_free(biz);
        gpu_engine_faces_free(handed_faces);
    }
}

#[test]
fn a_word_s_run_is_read_as_a_pass_s_is() {
    let word = gpu_engine_word_new();
    // A run's weight is `FontWeight`'s, 1 to 1000.
    let origins = [0; 2];
    for weight in [0, 1001] {
        // SAFETY: each buffer holds what it is said to.
        let heavy = unsafe { gpu_engine_word_run(word, 64, weight, false, "A".as_ptr(), 1, [1].as_ptr(), origins.as_ptr(), 1) };
        assert!(!heavy, "{weight}");
        assert!(last_error().contains(&format!("a weight of {weight}")), "{}", last_error());
    }
    for weight in [1, 1000] {
        // SAFETY: each buffer holds what it is said to.
        let set = unsafe { gpu_engine_word_run(word, 64, weight, false, "A".as_ptr(), 1, [1].as_ptr(), origins.as_ptr(), 1) };
        assert!(set, "{weight}: {}", last_error());
    }
    // A run wrong twice over says the first: its weight.
    // SAFETY: each buffer holds what it is said to.
    let twice = unsafe { gpu_engine_word_run(word, 64, 0, false, "A셀".as_ptr(), 4, [1].as_ptr(), origins.as_ptr(), 1) };
    assert!(!twice);
    assert!(last_error().contains("a weight of 0"), "{}", last_error());
    // A run's clusters are read as the letters' are: cut short is refused.
    let text = "A셀";
    // SAFETY: each buffer holds what it is said to.
    let short = unsafe { gpu_engine_word_run(word, 64, 400, false, text.as_ptr(), text.len(), [1].as_ptr(), origins.as_ptr(), 1) };
    assert!(!short);
    assert!(last_error().contains("the letters at 4"), "{}", last_error());
    // SAFETY: it came from its `_new`.
    unsafe { gpu_engine_word_free(word) };
}

#[test]
fn faces_in_another_order_outlive_the_faces_they_were_ordered_from() {
    let handed_faces = handed();
    let order = [2u32, 0, 1];
    // SAFETY: `handed_faces` is live and `order` holds three.
    let chinese = unsafe { gpu_engine_faces_ordered(handed_faces, order.as_ptr(), order.len()) };
    assert!(!chinese.is_null(), "{}", last_error());
    // SAFETY: it came from `gpu_engine_faces_of`; `chinese` shares, not borrows.
    unsafe { gpu_engine_faces_free(handed_faces) };
    let word = gpu_engine_word_new();
    assert!(word_run_of(word, "日3", 12 * 64, 12 * 64, 12 * 64), "{}", last_error());
    let (width, height) = (76u32, 49u32);
    let mut bytes = vec![7u8; (width * height) as usize];
    // SAFETY: every pointer is live, and `bytes` holds the raster.
    let rastered = unsafe { gpu_engine_word_raster(word, chinese, TWICE_OVER.as_ptr(), width, height, bytes.as_mut_ptr()) };
    assert!(rastered, "{}", last_error());

    let ordered = faces().ordered(&order).expect("an order");
    let runs = || vec![run("日3", 12 * 64, (0, 12 * 64), 12 * 64)];
    assert!(bytes == rastered_in_rust(&ordered, runs(), [width, height]), "the coverage");
    assert!(bytes != rastered_in_rust(faces(), runs(), [width, height]), "LIVENESS: the order tells");
    // An order naming a family past them is refused, and says so.
    let past = [3u32];
    // SAFETY: `chinese` is live and `past` holds one.
    let refused = unsafe { gpu_engine_faces_ordered(chinese, past.as_ptr(), past.len()) };
    assert!(refused.is_null());
    assert!(last_error().contains("names family 3"), "{}", last_error());
    // SAFETY: each came from its `_new` or its order.
    unsafe {
        gpu_engine_word_free(word);
        gpu_engine_faces_free(chinese);
    }
}

/// The app's faces as [`handed`] hands them, each file mapped from where
/// it lies instead of copied ([`gpu_engine_faces_file_at`]).
fn mapped_faces() -> *mut Faces {
    let handed = gpu_engine_faces_handed();
    for (name, family) in [
        ("BIZUDPGothic-Regular.ttf", 0),
        ("BIZUDPGothic-Bold.ttf", 0),
        ("NanumGothic-Regular.ttf", 1),
        ("NanumGothic-Bold.ttf", 1),
        ("NotoSansSC-Regular.ttf", 2),
        ("NotoSansSC-Bold.ttf", 2),
    ] {
        assert!(map(handed, family, &path_of(name)), "{name}");
    }
    // SAFETY: `handed` is set up once, here.
    unsafe { gpu_engine_faces_of(handed) }
}

/// Maps the file at `path` into `handed` as one of family `family`'s.
fn map(handed: *mut FacesHanded, family: u32, path: &str) -> bool {
    // SAFETY: `handed` is not yet set up; `path` holds its length.
    unsafe { gpu_engine_faces_file_at(handed, family, path.as_ptr(), path.len()) }
}

#[test]
fn faces_mapped_from_their_files_set_a_word_as_faces_copied_from_them_do() {
    let mapped = mapped_faces();
    assert!(!mapped.is_null(), "{}", last_error());
    let copied = handed();
    let word = gpu_engine_word_new();
    // A letter of each family, in both weights.
    assert!(word_run_of(word, "3셀业", 12 * 64, 12 * 64, 12 * 64), "{}", last_error());
    let (width, height) = (120u32, 49u32);
    let raster = |faces: *const Faces| {
        let mut bytes = vec![7u8; (width * height) as usize];
        // SAFETY: every pointer is live, and `bytes` holds the raster.
        let rastered =
            unsafe { gpu_engine_word_raster(word, faces, TWICE_OVER.as_ptr(), width, height, bytes.as_mut_ptr()) };
        assert!(rastered, "{}", last_error());
        bytes
    };
    let from_files = raster(mapped);
    assert!(from_files == raster(copied), "the coverage");
    assert!(from_files.iter().any(|&alpha| alpha != 0), "LIVENESS: the word has ink");
    // SAFETY: each came from its `_new` or `_of`.
    unsafe {
        gpu_engine_word_free(word);
        gpu_engine_faces_free(mapped);
        gpu_engine_faces_free(copied);
    }
}

#[test]
fn a_file_that_cannot_be_mapped_is_not_handed() {
    let handed = gpu_engine_faces_handed();
    assert!(!map(handed, 0, &path_of("no-such-face.ttf")));
    let not_utf8 = [0xFFu8, 0xFE];
    // SAFETY: `handed` is not yet set up; `not_utf8` holds its length.
    assert!(!unsafe { gpu_engine_faces_file_at(handed, 0, not_utf8.as_ptr(), not_utf8.len()) });
    // Nothing was handed: the next file is family 0's first.
    assert!(map(handed, 0, &path_of("NanumGothic-Regular.ttf")));
    // SAFETY: `handed` is set up once, here.
    let faces = unsafe { gpu_engine_faces_of(handed) };
    assert!(!faces.is_null(), "{}", last_error());
    // SAFETY: it came from `gpu_engine_faces_of`.
    unsafe { gpu_engine_faces_free(faces) };
}

#[test]
fn a_mapped_file_handed_out_of_family_order_is_refused() {
    let handed = gpu_engine_faces_handed();
    assert!(map(handed, 1, &path_of("NanumGothic-Regular.ttf")));
    // SAFETY: `handed` is set up once, here.
    assert!(unsafe { gpu_engine_faces_of(handed) }.is_null());
    assert!(last_error().contains("family 1"), "{}", last_error());
}
